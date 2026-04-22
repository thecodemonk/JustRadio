package com.justradio.just_radio

import android.content.Context
import android.content.SharedPreferences
import android.net.Uri
import android.os.Bundle
import android.util.Log
import androidx.media3.common.C
import androidx.media3.common.MediaItem
import androidx.media3.common.MediaMetadata
import androidx.media3.common.Metadata
import androidx.media3.common.PlaybackException
import androidx.media3.common.Player
import androidx.media3.common.Tracks
import androidx.media3.common.util.UnstableApi
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.exoplayer.source.DefaultMediaSourceFactory
import androidx.media3.extractor.metadata.icy.IcyHeaders
import androidx.media3.extractor.metadata.icy.IcyInfo
import androidx.media3.extractor.metadata.id3.TextInformationFrame
import androidx.media3.session.LibraryResult
import androidx.media3.session.MediaLibraryService
import androidx.media3.session.MediaSession
import androidx.media3.session.SessionCommand
import com.google.common.collect.ImmutableList
import com.google.common.util.concurrent.Futures
import com.google.common.util.concurrent.ListenableFuture
import org.json.JSONArray
import org.json.JSONObject

/**
 * Owns ExoPlayer + the MediaLibrarySession. Single source of truth for
 * playback across the phone UI, lock screen, and Android Auto.
 *
 * MediaLibraryService subsumes MediaBrowserServiceCompat — Android Auto
 * binds via the legacy `android.media.browse.MediaBrowserService` action
 * and media3 handles the protocol translation.
 *
 * The Flutter plugin (AudioPlayerPlugin) is a MediaController client; it
 * sends commands and listens for state/metadata updates here.
 *
 * Library tree data (favorites / recent / genres) is mirrored into
 * SharedPreferences by Dart so Android Auto can browse the app cold —
 * without a headless FlutterEngine being spun up. Deviates from the original
 * plan's "callback into Dart" approach because Android Auto can start this
 * service before the Flutter activity is ever running.
 */
@UnstableApi
class PlaybackService : MediaLibraryService() {

    companion object {
        private const val TAG = "PlaybackService"

        // Root + first-level node IDs for the Android Auto browse tree.
        const val ROOT_ID = "root"
        const val FAVORITES_ID = "favorites"
        const val RECENT_ID = "recent"
        const val GENRES_ID = "genres"

        // Playable leaf IDs are prefixed so we can recognize and route them.
        const val STATION_PREFIX = "station:"
        const val GENRE_PREFIX = "genre:"

        // SharedPreferences file + keys. Written by Dart via the method
        // channel whenever favorites/recent/genres change.
        const val PREFS_NAME = "justradio_library"
        const val KEY_FAVORITES = "favorites_json"
        const val KEY_RECENT = "recent_json"
        const val KEY_GENRES = "genres_json"
        fun keyForGenreStations(tag: String) = "genre_stations.$tag"

        // Custom session commands used to stream extras (stream info, icy
        // headers, raw id3 frames) that don't fit in MediaMetadata — the
        // MediaController plugin listens for these and forwards to Dart.
        const val CMD_STREAM_INFO = "com.justradio.stream_info"
        const val CMD_RAW_METADATA = "com.justradio.raw_metadata"
    }

    private var mediaLibrarySession: MediaLibrarySession? = null
    private var player: ExoPlayer? = null
    private lateinit var prefs: SharedPreferences

    override fun onCreate() {
        super.onCreate()
        Log.d(TAG, "onCreate")
        prefs = getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

        val exo = ExoPlayer.Builder(this)
            .setMediaSourceFactory(DefaultMediaSourceFactory(this))
            .setHandleAudioBecomingNoisy(true)
            .build()
        exo.addListener(PlayerListener())
        player = exo

        mediaLibrarySession = MediaLibrarySession.Builder(this, exo, LibraryCallback()).build()
    }

    override fun onDestroy() {
        Log.d(TAG, "onDestroy")
        mediaLibrarySession?.run {
            player.release()
            release()
        }
        mediaLibrarySession = null
        player = null
        super.onDestroy()
    }

    override fun onGetSession(controllerInfo: MediaSession.ControllerInfo): MediaLibrarySession? =
        mediaLibrarySession

    // ------------------------------------------------------------------
    // Library tree — reads from SharedPreferences populated by Dart.
    // ------------------------------------------------------------------

    private inner class LibraryCallback : MediaLibrarySession.Callback {

        override fun onConnect(
            session: MediaSession,
            controller: MediaSession.ControllerInfo
        ): MediaSession.ConnectionResult {
            // Advertise our custom commands to the connecting controller so
            // it can invoke them (the plugin side sends none today, but it
            // receives broadcastCustomCommand from the service).
            val base = super.onConnect(session, controller)
            val available = base.availableSessionCommands.buildUpon()
                .add(SessionCommand(CMD_STREAM_INFO, Bundle.EMPTY))
                .add(SessionCommand(CMD_RAW_METADATA, Bundle.EMPTY))
                .build()
            return MediaSession.ConnectionResult.accept(available, base.availablePlayerCommands)
        }

        override fun onGetLibraryRoot(
            session: MediaLibrarySession,
            browser: MediaSession.ControllerInfo,
            params: LibraryParams?
        ): ListenableFuture<LibraryResult<MediaItem>> {
            val root = browsable(ROOT_ID, "JustRadio", MediaMetadata.MEDIA_TYPE_FOLDER_MIXED)
            return Futures.immediateFuture(LibraryResult.ofItem(root, params))
        }

        override fun onGetChildren(
            session: MediaLibrarySession,
            browser: MediaSession.ControllerInfo,
            parentId: String,
            page: Int,
            pageSize: Int,
            params: LibraryParams?
        ): ListenableFuture<LibraryResult<ImmutableList<MediaItem>>> {
            val items: ImmutableList<MediaItem> = when {
                parentId == ROOT_ID -> rootChildren()
                parentId == FAVORITES_ID -> stationsFromPrefs(KEY_FAVORITES)
                parentId == RECENT_ID -> stationsFromPrefs(KEY_RECENT)
                parentId == GENRES_ID -> genres()
                parentId.startsWith(GENRE_PREFIX) ->
                    stationsFromPrefs(keyForGenreStations(parentId.removePrefix(GENRE_PREFIX)))
                else -> ImmutableList.of()
            }
            return Futures.immediateFuture(LibraryResult.ofItemList(items, params))
        }

        override fun onGetItem(
            session: MediaLibrarySession,
            browser: MediaSession.ControllerInfo,
            mediaId: String
        ): ListenableFuture<LibraryResult<MediaItem>> {
            val item = if (mediaId.startsWith(STATION_PREFIX)) {
                resolveStation(mediaId) ?: return notFound()
            } else {
                return notFound()
            }
            return Futures.immediateFuture(LibraryResult.ofItem(item, null))
        }

        override fun onAddMediaItems(
            session: MediaSession,
            controller: MediaSession.ControllerInfo,
            mediaItems: MutableList<MediaItem>
        ): ListenableFuture<MutableList<MediaItem>> {
            // The localConfiguration (carrying the playback URI) is stripped
            // across IPC for security, so we reconstruct it here:
            //   1. If the controller stashed the URI in requestMetadata, use
            //      it — the Flutter plugin does this for ad-hoc URL playback.
            //   2. Otherwise (Android Auto playing a station from the browse
            //      tree), resolve via the SharedPreferences mirror by mediaId.
            val resolved = mediaItems.map { item ->
                when {
                    item.localConfiguration != null -> item
                    item.requestMetadata.mediaUri != null ->
                        item.buildUpon().setUri(item.requestMetadata.mediaUri).build()
                    item.mediaId.startsWith(STATION_PREFIX) ->
                        resolveStation(item.mediaId) ?: item
                    else -> item
                }
            }.toMutableList()
            return Futures.immediateFuture(resolved)
        }

        private fun notFound() =
            Futures.immediateFuture(LibraryResult.ofError<MediaItem>(LibraryResult.RESULT_ERROR_BAD_VALUE))
    }

    private fun rootChildren(): ImmutableList<MediaItem> = ImmutableList.of(
        browsable(FAVORITES_ID, "Favorites", MediaMetadata.MEDIA_TYPE_FOLDER_MIXED),
        browsable(RECENT_ID, "Recently Played", MediaMetadata.MEDIA_TYPE_FOLDER_MIXED),
        browsable(GENRES_ID, "Browse by Genre", MediaMetadata.MEDIA_TYPE_FOLDER_MIXED),
    )

    private fun genres(): ImmutableList<MediaItem> {
        val json = prefs.getString(KEY_GENRES, null) ?: return ImmutableList.of()
        val list = try {
            JSONArray(json)
        } catch (_: Throwable) {
            return ImmutableList.of()
        }
        val builder = ImmutableList.builder<MediaItem>()
        for (i in 0 until list.length()) {
            val obj = list.optJSONObject(i) ?: continue
            val name = obj.optString("name")
            if (name.isEmpty()) continue
            val title = name.replaceFirstChar { it.uppercaseChar() }
            builder.add(browsable(GENRE_PREFIX + name, title, MediaMetadata.MEDIA_TYPE_FOLDER_MIXED))
        }
        return builder.build()
    }

    private fun stationsFromPrefs(key: String): ImmutableList<MediaItem> {
        val json = prefs.getString(key, null) ?: return ImmutableList.of()
        val list = try {
            JSONArray(json)
        } catch (_: Throwable) {
            return ImmutableList.of()
        }
        val builder = ImmutableList.builder<MediaItem>()
        for (i in 0 until list.length()) {
            val obj = list.optJSONObject(i) ?: continue
            val station = stationFromJson(obj) ?: continue
            builder.add(station)
        }
        return builder.build()
    }

    /** Resolve a `station:<uuid>` media ID to a playable MediaItem by
     *  searching the mirrored lists. Slow path on cold start, but lists are
     *  small (30 recent, user-sized favorites) so linear scan is fine. */
    private fun resolveStation(mediaId: String): MediaItem? {
        if (!mediaId.startsWith(STATION_PREFIX)) return null
        for (key in listOf(KEY_FAVORITES, KEY_RECENT)) {
            val match = findStationIn(prefs.getString(key, null), mediaId)
            if (match != null) return match
        }
        // Genre station lists are keyed by tag — scan all prefs that match
        // the naming scheme.
        for ((k, v) in prefs.all) {
            if (!k.startsWith("genre_stations.")) continue
            val match = findStationIn(v as? String, mediaId)
            if (match != null) return match
        }
        return null
    }

    private fun findStationIn(json: String?, mediaId: String): MediaItem? {
        json ?: return null
        val arr = try {
            JSONArray(json)
        } catch (_: Throwable) {
            return null
        }
        for (i in 0 until arr.length()) {
            val obj = arr.optJSONObject(i) ?: continue
            val uuid = obj.optString("stationuuid")
            if (STATION_PREFIX + uuid == mediaId) {
                return stationFromJson(obj)
            }
        }
        return null
    }

    private fun stationFromJson(obj: JSONObject): MediaItem? {
        val uuid = obj.optString("stationuuid").ifEmpty { return null }
        val name = obj.optString("name", "Unknown")
        val streamUrl = obj.optString("streamUrl", "").ifEmpty {
            obj.optString("url_resolved", "").ifEmpty { obj.optString("url", "") }
        }
        if (streamUrl.isEmpty()) return null
        val favicon = obj.optString("favicon").takeIf { it.isNotEmpty() }?.let {
            try { Uri.parse(it) } catch (_: Throwable) { null }
        }
        val tags = obj.optString("tags")
        val metadata = MediaMetadata.Builder()
            .setTitle(name)
            .setSubtitle(tags)
            .setArtworkUri(favicon)
            .setIsBrowsable(false)
            .setIsPlayable(true)
            .setMediaType(MediaMetadata.MEDIA_TYPE_RADIO_STATION)
            .build()
        return MediaItem.Builder()
            .setMediaId(STATION_PREFIX + uuid)
            .setUri(streamUrl)
            .setMediaMetadata(metadata)
            .build()
    }

    private fun browsable(id: String, title: String, type: Int): MediaItem {
        val meta = MediaMetadata.Builder()
            .setTitle(title)
            .setIsBrowsable(true)
            .setIsPlayable(false)
            .setMediaType(type)
            .build()
        return MediaItem.Builder()
            .setMediaId(id)
            .setMediaMetadata(meta)
            .build()
    }

    // ------------------------------------------------------------------
    // Metadata pipeline — identical parsing to the old plugin, but now
    // runs server-side. Title/artist/album flow through the player's
    // own onMediaMetadataChanged so MediaController clients + Android
    // Auto pick them up automatically. Stream info (bitrate, codec,
    // streamName, raw ICY fields) ride on a custom session command
    // because MediaMetadata has no clean slot for them.
    // ------------------------------------------------------------------

    private inner class PlayerListener : Player.Listener {
        override fun onPlayerError(error: PlaybackException) {
            broadcast(CMD_STREAM_INFO, Bundle().apply {
                putString("error", error.message)
            })
        }

        override fun onTracksChanged(tracks: Tracks) {
            for (group in tracks.groups) {
                if (group.type != C.TRACK_TYPE_AUDIO) continue
                for (i in 0 until group.length) {
                    if (!group.isTrackSelected(i)) continue
                    val bps = group.getTrackFormat(i).bitrate
                    if (bps > 0) {
                        broadcast(CMD_STREAM_INFO, Bundle().apply {
                            putInt("bitrate", bps / 1000)
                        })
                    }
                }
            }
        }

        override fun onMetadata(metadata: Metadata) {
            for (i in 0 until metadata.length()) {
                when (val entry = metadata[i]) {
                    is IcyInfo -> broadcast(CMD_RAW_METADATA, Bundle().apply {
                        putString("identifier", "icy/StreamTitle")
                        putString("title", entry.title)
                        putString("stringValue", entry.title)
                    })
                    is IcyHeaders -> broadcast(CMD_STREAM_INFO, Bundle().apply {
                        putString("streamName", entry.name)
                        putString("genre", entry.genre)
                        putInt("bitrate", entry.bitrate)
                        putString("streamUrl", entry.url)
                    })
                    is TextInformationFrame -> {
                        val id = entry.id ?: ""
                        // `entry.value` is deprecated in media3 1.10+ — values
                        // is the list replacement. A TextInformationFrame
                        // always carries at least one value in practice.
                        val value = entry.values.firstOrNull()
                        val description = entry.description
                        val bitrate = if (id == "TXXX") parseTxxxBitrate(value, description) else null
                        broadcast(CMD_RAW_METADATA, Bundle().apply {
                            putString("identifier", "id3/$id")
                            putString("stringValue", value)
                            if (id == "TIT2") putString("title", value)
                            if (id == "TPE1") putString("artist", value)
                            if (id == "TALB") putString("album", value)
                            if (id == "TFLT") putString("codec", value)
                            if (bitrate != null) putInt("bitrate", bitrate)
                            if (description != null) putString("txxxDescriptor", description)
                        })
                    }
                }
            }
        }
    }

    /** TXXX frames carry arbitrary user-defined text — SomaFM uses them for
     *  bitrate/sampleRate/channels under 3-letter descriptors. Map the
     *  bitrate-ish ones, skip the rest. */
    private fun parseTxxxBitrate(value: String?, description: String?): Int? {
        val n = value?.toIntOrNull() ?: return null
        val desc = description?.lowercase() ?: ""
        val bitrateKeys = listOf("bitrate", "kbps", "adr", "audiodatarate", "br")
        val nonBitrateKeys = listOf(
            "sample", "asr", "channel", "ach", "enc",
            "dev", "crd", "date", "time", "year"
        )
        val isBitrate = bitrateKeys.any { desc.contains(it) }
        val isKnownOther = nonBitrateKeys.any { desc.contains(it) }
        val byRange = !isKnownOther && n in 64..2000
        return if (isBitrate || byRange) n else null
    }

    private fun broadcast(commandAction: String, args: Bundle) {
        val session = mediaLibrarySession ?: return
        session.broadcastCustomCommand(SessionCommand(commandAction, Bundle.EMPTY), args)
    }
}
