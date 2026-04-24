package com.justradio.just_radio

import android.content.Context
import android.content.SharedPreferences
import android.net.Uri
import android.os.Bundle
import android.util.Log
import androidx.media3.common.AudioAttributes
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
import androidx.media3.session.CommandButton
import androidx.media3.session.LibraryResult
import androidx.media3.session.MediaLibraryService
import androidx.media3.session.MediaSession
import androidx.media3.session.SessionCommand
import androidx.media3.session.SessionResult
import com.google.common.collect.ImmutableList
import com.google.common.util.concurrent.Futures
import com.google.common.util.concurrent.ListenableFuture
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors
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

        // Love-track button. AA (or the phone notification) invokes
        // CMD_TOGGLE_LOVED; the service calls Last.fm directly so Flutter
        // doesn't have to be running. State changes ride back to Dart via
        // CMD_LOVED_STATE (broadcast). When Dart is running and resolves
        // loved state first, it pushes CMD_DART_SET_LOVED so the AA
        // button matches without a redundant native HTTP call. Dart
        // signals auth changes via CMD_DART_AUTH_CHANGED so the service
        // re-reads creds + refreshes the button.
        const val CMD_TOGGLE_LOVED = "com.justradio.toggle_loved"
        const val CMD_LOVED_STATE = "com.justradio.loved_state"
        const val CMD_DART_SET_LOVED = "com.justradio.dart_set_loved"
        const val CMD_DART_AUTH_CHANGED = "com.justradio.dart_auth_changed"

        // Last.fm credentials mirrored into SharedPreferences by Dart so
        // the service can sign its own requests. See main.dart's
        // syncLastfmSession / syncLastfmConfig.
        const val KEY_LASTFM_SESSION = "lastfm_session_key"
        const val KEY_LASTFM_USERNAME = "lastfm_username"
        const val KEY_LASTFM_API_KEY = "lastfm_api_key"
        const val KEY_LASTFM_API_SECRET = "lastfm_api_secret"

        // Cached loved state keyed by "artist|title". Updated by both
        // Dart (setLovedState method) and native love-toggle flows so the
        // AA button renders correctly without re-hitting Last.fm.
        const val KEY_LOVED_TRACKS = "loved_tracks_json"

        // Cached album-art URLs keyed by "artist|title" (lowercased).
        // Written by the native lookup chain so repeat plays of the same
        // track skip the HTTP walk. Dart maintains its own Hive cache;
        // neither reads the other — idempotent double-hits are fine.
        const val KEY_ART_CACHE = "album_art_cache_json"

        // One-shot migration flag. Bump the suffix whenever the chain's
        // resolution logic changes (compilation filter, swap matcher,
        // whitespace-tolerant loose match, etc.) so previously-cached
        // wrong URLs don't stick around.
        const val KEY_ART_CACHE_MIGRATION = "album_art_cache_migration_v5"
    }

    private var mediaLibrarySession: MediaLibrarySession? = null
    private var player: ExoPlayer? = null
    private lateinit var prefs: SharedPreferences
    // Single-thread executor for Last.fm HTTP work. Serializes requests
    // (which is fine for the button's volume) and keeps the main thread
    // free. Released in onDestroy.
    private val lastfmExecutor: ExecutorService = Executors.newSingleThreadExecutor()
    // Separate lane for album-art lookups — can run for several seconds
    // through the iTunes→Deezer→MB+CAA chain, so we don't want it
    // blocking love-state checks behind it.
    private val albumArtExecutor: ExecutorService = Executors.newSingleThreadExecutor()
    // Last track we fired track.getInfo for — dedupe on redundant emits.
    private var lastLoveCheckedKey: String = ""
    // Last track we fired an album-art lookup for — dedupe HLS metadata
    // bursts (TIT2 + TPE1 land separately) so we don't race two chains.
    private var lastArtLookupKey: String = ""
    // Cached love-button visibility state. updateMediaItemTrackInfo can
    // fire 3x per track change (title → +artist → +album arrive in
    // quick succession) and each previously triggered a redundant
    // setMediaButtonPreferences, which causes AA to repaint its
    // Now Playing surface. Skip when nothing about the button has
    // actually changed.
    private var lastButtonState: Triple<Boolean, Boolean, Boolean>? = null

    // Scrobble tracking. We only scrobble when Flutter is NOT attached
    // — when Dart is running, RadioPlayerController handles it and we'd
    // double up. Kept as separate fields rather than a data class so
    // the update-on-metadata-burst path stays cheap.
    private var pendingScrobbleArtist: String? = null
    private var pendingScrobbleTitle: String? = null
    private var pendingScrobbleAlbum: String? = null
    private var pendingScrobbleStartMs: Long = 0
    private var lastScrobbledKey: String = ""
    private var lastNowPlayingKey: String = ""
    // Last.fm's canonical scrobble rule is "played >= 30s AND (>= half
    // the track OR >= 4 minutes)". We don't know radio track lengths,
    // so the 30s floor is what we enforce (matches Dart logic).
    private val scrobbleMinMs: Long = 30_000

    override fun onCreate() {
        super.onCreate()
        Log.d(TAG, "onCreate")
        prefs = getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        runArtCacheMigration()

        // Declare ourselves as music content and opt into ExoPlayer's
        // audio-focus plumbing. With handleAudioFocus=true, ExoPlayer
        // requests GAIN focus when playback starts (pausing other audio
        // apps — Spotify, YouTube Music, etc.), ducks on transient loss
        // (nav prompts), and pauses us on full loss (incoming call).
        val audioAttrs = AudioAttributes.Builder()
            .setUsage(C.USAGE_MEDIA)
            .setContentType(C.AUDIO_CONTENT_TYPE_MUSIC)
            .build()

        val exo = ExoPlayer.Builder(this)
            .setAudioAttributes(audioAttrs, /* handleAudioFocus = */ true)
            .setMediaSourceFactory(DefaultMediaSourceFactory(this))
            .setHandleAudioBecomingNoisy(true)
            .build()
        exo.addListener(PlayerListener())
        player = exo

        mediaLibrarySession = MediaLibrarySession.Builder(this, exo, LibraryCallback()).build()
    }

    override fun onDestroy() {
        Log.d(TAG, "onDestroy")
        // Flush a scrobble for the currently-playing track if it's
        // already past the 30-second bar. The executor fire-and-forget
        // may not complete before the process is reaped, but Android
        // grants services a brief (usually ~10s) grace window, and
        // Last.fm's endpoint responds in <500ms typically.
        maybeScrobblePendingTrack()
        mediaLibrarySession?.run {
            player.release()
            release()
        }
        mediaLibrarySession = null
        player = null
        lastfmExecutor.shutdown()
        albumArtExecutor.shutdown()
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
            // it can invoke them. Love-toggle is reachable from Android Auto
            // and the notification; the plugin (Dart side) only listens to
            // the broadcast variants.
            val base = super.onConnect(session, controller)
            val available = base.availableSessionCommands.buildUpon()
                .add(SessionCommand(CMD_STREAM_INFO, Bundle.EMPTY))
                .add(SessionCommand(CMD_RAW_METADATA, Bundle.EMPTY))
                .add(SessionCommand(CMD_TOGGLE_LOVED, Bundle.EMPTY))
                .add(SessionCommand(CMD_LOVED_STATE, Bundle.EMPTY))
                .add(SessionCommand(CMD_DART_SET_LOVED, Bundle.EMPTY))
                .add(SessionCommand(CMD_DART_AUTH_CHANGED, Bundle.EMPTY))
                .build()
            return MediaSession.ConnectionResult.accept(available, base.availablePlayerCommands)
        }

        override fun onCustomCommand(
            session: MediaSession,
            controller: MediaSession.ControllerInfo,
            customCommand: SessionCommand,
            args: Bundle,
        ): ListenableFuture<SessionResult> {
            when (customCommand.customAction) {
                CMD_TOGGLE_LOVED -> {
                    handleToggleLoved()
                    return Futures.immediateFuture(SessionResult(SessionResult.RESULT_SUCCESS))
                }
                CMD_DART_SET_LOVED -> {
                    val artist = args.getString("artist").orEmpty()
                    val title = args.getString("title").orEmpty()
                    val loved = args.getBoolean("loved", false)
                    if (artist.isNotEmpty() && title.isNotEmpty()) {
                        applyDartLovedState(artist, title, loved)
                    }
                    return Futures.immediateFuture(SessionResult(SessionResult.RESULT_SUCCESS))
                }
                CMD_DART_AUTH_CHANGED -> {
                    val loggedIn = args.getBoolean("loggedIn", false)
                    onLastfmAuthChanged(loggedIn)
                    return Futures.immediateFuture(SessionResult(SessionResult.RESULT_SUCCESS))
                }
            }
            return super.onCustomCommand(session, controller, customCommand, args)
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
            Log.d(TAG, "onMetadata: entries=${metadata.length()} types=${(0 until metadata.length()).map { metadata[it].javaClass.simpleName }}")
            for (i in 0 until metadata.length()) {
                when (val entry = metadata[i]) {
                    is IcyInfo -> {
                        Log.d(TAG, "  IcyInfo title='${entry.title}' url='${entry.url}'")
                        broadcast(CMD_RAW_METADATA, Bundle().apply {
                            putString("identifier", "icy/StreamTitle")
                            putString("title", entry.title)
                            putString("stringValue", entry.title)
                        })
                        // ExoPlayer's auto-population of MediaMetadata from
                        // IcyInfo uses populateFromMetadata(), which only
                        // fills null fields — it refuses to overwrite the
                        // title we set when constructing the MediaItem
                        // (the station name). Push the split manually.
                        applyIcyStreamTitleToMediaItem(entry.title)
                    }
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
                        // Same populateFromMetadata-refuses-to-overwrite issue
                        // as IcyInfo: our MediaItem pre-sets title to the
                        // station name, so TIT2 gets silently dropped by
                        // ExoPlayer's auto-population. Push ID3 fields onto
                        // the MediaItem explicitly.
                        when (id) {
                            "TIT2" -> updateMediaItemTrackInfo(title = value)
                            "TPE1" -> updateMediaItemTrackInfo(artist = value)
                            "TALB" -> updateMediaItemTrackInfo(album = value)
                        }
                    }
                }
            }
        }
    }

    /** Split a Shoutcast/Icecast StreamTitle ("Artist - Title") and push
     *  it onto the current MediaItem. Delegates to the unified helper
     *  below, which handles the HLS-ID3 case the same way. */
    private fun applyIcyStreamTitleToMediaItem(streamTitle: String?) {
        if (streamTitle.isNullOrBlank()) return
        val (artist, rawTitle) = if (streamTitle.contains(" - ")) {
            val parts = streamTitle.split(" - ", limit = 2)
            Pair(parts[0].trim(), parts[1].trim())
        } else {
            Pair(null, streamTitle.trim())
        }
        // SomaFM occasionally sends "Artist - Artist - Title" — after
        // splitting on the first " - " we end up with title starting
        // with another copy of the artist. Strip it so the real title
        // goes to the art-lookup query (observed: "Voodoo Warriors Of
        // Love - Voodoo Warriors Of Love - Beli" was dropping "Beli"
        // into the lookup as "Voodoo Warriors Of Love - Beli", missing
        // every provider).
        val title = if (artist != null && rawTitle.startsWith("$artist - ")) {
            rawTitle.substring(artist.length + 3).trim()
        } else {
            rawTitle
        }
        updateMediaItemTrackInfo(title = title, artist = artist)
    }

    /** Apply one or more track-level fields to the current MediaItem's
     *  MediaMetadata and re-emit via replaceMediaItem. ExoPlayer's built-
     *  in auto-population won't overwrite fields we pre-set at MediaItem
     *  creation (the station name lives in `title`), so we do it ourselves
     *  for both IcyInfo and HLS ID3 frames.
     *
     *  Any null argument means "don't touch this field." Each update
     *  triggers a no-op early-out if nothing actually changed, so callers
     *  can invoke freely without worrying about replaceMediaItem loops. */
    private fun updateMediaItemTrackInfo(
        title: String? = null,
        artist: String? = null,
        album: String? = null,
    ) {
        val p = player ?: return
        val current = p.currentMediaItem ?: return
        val existing = current.mediaMetadata

        val newTitle = if (!title.isNullOrBlank()) title else existing.title?.toString()
        val newArtist = if (!artist.isNullOrBlank()) artist else existing.artist?.toString()
        val newAlbum = if (!album.isNullOrBlank()) album else existing.albumTitle?.toString()

        if (existing.title?.toString() == newTitle
            && existing.artist?.toString() == newArtist
            && existing.albumTitle?.toString() == newAlbum
        ) return

        // Once real track metadata has arrived, flip the media type
        // from RADIO_STATION to MUSIC. Android Auto uses the type to
        // decide between the minimal radio card and the richer music
        // rendering (which on some head units samples colors from the
        // artwork for a gradient background). Stays as RADIO_STATION
        // until we have at least an artist+title pair.
        val hasTrackInfo =
            !newArtist.isNullOrBlank() && !newTitle.isNullOrBlank()
        val targetMediaType = if (hasTrackInfo) {
            MediaMetadata.MEDIA_TYPE_MUSIC
        } else {
            existing.mediaType ?: MediaMetadata.MEDIA_TYPE_RADIO_STATION
        }
        val merged = existing.buildUpon()
            .setTitle(newTitle)
            .setArtist(newArtist)
            .setAlbumTitle(newAlbum)
            .setMediaType(targetMediaType)
            .build()
        val updated = current.buildUpon().setMediaMetadata(merged).build()
        Log.d(TAG, "updateMediaItemTrackInfo -> title='$newTitle' artist='$newArtist' album='$newAlbum' type=$targetMediaType")
        p.replaceMediaItem(p.currentMediaItemIndex, updated)
        // Track identity may have flipped — re-resolve the loved state so
        // the AA/notification heart matches the new song.
        onTrackIdentityChanged()
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

    // ------------------------------------------------------------------
    // Last.fm love-track button
    // ------------------------------------------------------------------

    /** Current artist/title from the playing MediaItem, or null if none. */
    private fun currentArtistTitle(): Pair<String, String>? {
        val p = player ?: return null
        val md = p.currentMediaItem?.mediaMetadata ?: return null
        val artist = md.artist?.toString()?.trim().orEmpty()
        val title = md.title?.toString()?.trim().orEmpty()
        if (artist.isEmpty() || title.isEmpty()) return null
        return artist to title
    }

    private fun currentCreds(): LastfmClient.Creds? {
        val apiKey = prefs.getString(KEY_LASTFM_API_KEY, "").orEmpty()
        val apiSecret = prefs.getString(KEY_LASTFM_API_SECRET, "").orEmpty()
        val sk = prefs.getString(KEY_LASTFM_SESSION, "").orEmpty()
        if (apiKey.isEmpty() || apiSecret.isEmpty() || sk.isEmpty()) return null
        return LastfmClient.Creds(apiKey, apiSecret, sk)
    }

    private fun lovedCacheKey(artist: String, title: String) = "$artist|$title"

    private fun readLovedCache(): JSONObject {
        val json = prefs.getString(KEY_LOVED_TRACKS, null) ?: return JSONObject()
        return try { JSONObject(json) } catch (_: Throwable) { JSONObject() }
    }

    private fun writeLovedCache(cache: JSONObject) {
        prefs.edit().putString(KEY_LOVED_TRACKS, cache.toString()).apply()
    }

    private fun setCachedLoved(artist: String, title: String, loved: Boolean) {
        val cache = readLovedCache()
        cache.put(lovedCacheKey(artist, title), loved)
        writeLovedCache(cache)
    }

    private fun isCachedLoved(artist: String, title: String): Boolean {
        val cache = readLovedCache()
        return cache.optBoolean(lovedCacheKey(artist, title), false)
    }

    /** Build the heart CommandButton matching `loved`. */
    private fun lovedCommandButton(loved: Boolean): CommandButton {
        val icon =
            if (loved) CommandButton.ICON_HEART_FILLED else CommandButton.ICON_HEART_UNFILLED
        val label = if (loved) "Unlove on Last.fm" else "Love on Last.fm"
        return CommandButton.Builder(icon)
            .setSessionCommand(SessionCommand(CMD_TOGGLE_LOVED, Bundle.EMPTY))
            .setDisplayName(label)
            .build()
    }

    /** Publish the heart button reflecting the current track's loved
     *  state — or hide it entirely when Last.fm isn't linked. Dedupes
     *  against the last-published state so rapid HLS metadata bursts
     *  don't repeatedly flip AA's Now Playing surface. */
    private fun refreshLoveButton() {
        val session = mediaLibrarySession ?: return
        val creds = currentCreds()
        val pair = currentArtistTitle()
        val authed = creds != null
        val shouldShow = authed && pair != null
        val loved = if (shouldShow) isCachedLoved(pair!!.first, pair.second) else false
        val state = Triple(shouldShow, authed, loved)
        if (state == lastButtonState) return
        lastButtonState = state
        if (!shouldShow) {
            session.setMediaButtonPreferences(ImmutableList.of())
        } else {
            session.setMediaButtonPreferences(
                ImmutableList.of(lovedCommandButton(loved))
            )
        }
    }

    /** Broadcast a loved-state change so Dart's LovedTrackNotifier can
     *  mirror it without re-hitting the API. */
    private fun broadcastLovedState(artist: String, title: String, loved: Boolean) {
        broadcast(CMD_LOVED_STATE, Bundle().apply {
            putString("artist", artist)
            putString("title", title)
            putBoolean("loved", loved)
        })
    }

    /** Called when AA (or the notification) taps the heart. Flip state
     *  optimistically, call Last.fm, revert on failure. */
    private fun handleToggleLoved() {
        val creds = currentCreds() ?: return
        val (artist, title) = currentArtistTitle() ?: return
        val wantLoved = !isCachedLoved(artist, title)
        // Optimistic UI update — swap the button + cache immediately, then
        // make the network call. On failure we revert.
        setCachedLoved(artist, title, wantLoved)
        refreshLoveButton()
        broadcastLovedState(artist, title, wantLoved)

        lastfmExecutor.execute {
            val ok = if (wantLoved) {
                LastfmClient.loveTrack(artist, title, creds)
            } else {
                LastfmClient.unloveTrack(artist, title, creds)
            }
            if (!ok) {
                setCachedLoved(artist, title, !wantLoved)
                refreshLoveButton()
                broadcastLovedState(artist, title, !wantLoved)
            }
        }
    }

    /** Called when the current track changes. Drives love-state check,
     *  album-art lookup, and Last.fm scrobbling / updateNowPlaying (the
     *  latter only when Flutter isn't attached — Dart handles it
     *  otherwise). Each sub-step guards against re-running for the
     *  same track ID. */
    fun onTrackIdentityChanged() {
        val (artist, title) = currentArtistTitle() ?: run {
            lastLoveCheckedKey = ""
            lastArtLookupKey = ""
            refreshLoveButton()
            return
        }
        val album = player?.currentMediaItem?.mediaMetadata
            ?.albumTitle?.toString()?.takeIf { it.isNotBlank() }

        // Try to scrobble the PREVIOUS track before we overwrite its
        // tracking fields. If it played long enough and Flutter isn't
        // handling scrobbles, fire it off.
        maybeScrobblePendingTrack()

        // Record the new pending track. Start time is now; the next
        // track change (or service stop) decides whether to scrobble.
        val keyForThis = "$artist|$title"
        if (pendingScrobbleArtist != artist || pendingScrobbleTitle != title) {
            pendingScrobbleArtist = artist
            pendingScrobbleTitle = title
            pendingScrobbleAlbum = album
            pendingScrobbleStartMs = System.currentTimeMillis()
            // Tell Last.fm "now playing" once per new track.
            maybeUpdateNowPlaying(artist, title, album, keyForThis)
        } else if (pendingScrobbleAlbum == null && album != null) {
            // Album arrived late in the metadata burst — fold it in.
            pendingScrobbleAlbum = album
        }

        refreshLoveButton()
        resolveLovedState(artist, title)
        resolveAlbumArt(artist, title)
    }

    private fun maybeScrobblePendingTrack() {
        val artist = pendingScrobbleArtist ?: return
        val title = pendingScrobbleTitle ?: return
        val startMs = pendingScrobbleStartMs
        if (startMs <= 0) return
        val playedMs = System.currentTimeMillis() - startMs
        if (playedMs < scrobbleMinMs) return
        val key = "$artist|$title|$startMs"
        if (key == lastScrobbledKey) return
        // Dart owns scrobbling when Flutter is attached; otherwise we
        // do. The Volatile read guarantees we see the latest attach
        // state even though we may be on a background executor thread.
        if (AudioPlayerPlugin.isFlutterAttached) return
        val creds = currentCreds() ?: return
        lastScrobbledKey = key
        val album = pendingScrobbleAlbum
        val timestampSec = startMs / 1000
        lastfmExecutor.execute {
            val ok = LastfmClient.scrobble(artist, title, timestampSec, album, creds)
            Log.d(TAG, "native scrobble: $artist - $title (ok=$ok)")
        }
    }

    private fun maybeUpdateNowPlaying(
        artist: String,
        title: String,
        album: String?,
        key: String,
    ) {
        if (key == lastNowPlayingKey) return
        lastNowPlayingKey = key
        if (AudioPlayerPlugin.isFlutterAttached) return
        val creds = currentCreds() ?: return
        lastfmExecutor.execute {
            LastfmClient.updateNowPlaying(artist, title, album, creds)
        }
    }

    private fun resolveLovedState(artist: String, title: String) {
        val key = lovedCacheKey(artist, title)
        if (key == lastLoveCheckedKey) return
        lastLoveCheckedKey = key

        val creds = currentCreds()
        val username = prefs.getString(KEY_LASTFM_USERNAME, null)
        if (creds == null || username.isNullOrEmpty()) return

        lastfmExecutor.execute {
            val loved = LastfmClient.isTrackLoved(
                artist = artist,
                title = title,
                username = username,
                apiKey = creds.apiKey,
            )
            val prior = isCachedLoved(artist, title)
            if (prior == loved) return@execute
            setCachedLoved(artist, title, loved)
            refreshLoveButton()
            broadcastLovedState(artist, title, loved)
        }
    }

    private fun resolveAlbumArt(artist: String, title: String) {
        val key = "${artist.lowercase().trim()}|${title.lowercase().trim()}"
        if (key == lastArtLookupKey) return
        lastArtLookupKey = key

        // Fast path: previously cached URL. Apply synchronously so AA
        // shows the art on the next display frame.
        val cached = cachedArt(key)
        if (cached != null) {
            applyArtwork(cached, expectedArtist = artist, expectedTitle = title)
            return
        }

        albumArtExecutor.execute {
            val url = AlbumArtLookup.fetch(artist, title)
            if (url == null) return@execute
            putCachedArt(key, url)
            // Jump back to the main thread — ExoPlayer requires its
            // mutations on the app main looper.
            mediaLibrarySession?.let { session ->
                session.player.applicationLooper.let { looper ->
                    android.os.Handler(looper).post {
                        applyArtwork(url, expectedArtist = artist, expectedTitle = title)
                    }
                }
            }
        }
    }

    /** Swap the current MediaItem's artworkUri in place. Guards against
     *  stale lookups — the track may have changed between query and
     *  result. Idempotent: no-op if the URI already matches. */
    private fun applyArtwork(url: String, expectedArtist: String, expectedTitle: String) {
        val p = player ?: return
        val current = p.currentMediaItem ?: return
        val existing = current.mediaMetadata
        // Stale-lookup guard: only apply if the current track is still
        // the one we ran the query for.
        if (existing.artist?.toString() != expectedArtist
            || existing.title?.toString() != expectedTitle
        ) {
            Log.d(TAG, "applyArtwork: track changed since lookup, dropping")
            return
        }
        val incoming = Uri.parse(url)
        if (existing.artworkUri == incoming) return
        val merged = existing.buildUpon().setArtworkUri(incoming).build()
        val updated = current.buildUpon().setMediaMetadata(merged).build()
        p.replaceMediaItem(p.currentMediaItemIndex, updated)
        Log.d(TAG, "applyArtwork -> $url")
    }

    private fun cachedArt(key: String): String? {
        val json = prefs.getString(KEY_ART_CACHE, null) ?: return null
        val obj = try { JSONObject(json) } catch (_: Throwable) { return null }
        val v = obj.optString(key)
        return if (v.isNullOrEmpty()) null else v
    }

    private fun putCachedArt(key: String, url: String) {
        val existing = prefs.getString(KEY_ART_CACHE, null)
        val obj = try {
            if (existing == null) JSONObject() else JSONObject(existing)
        } catch (_: Throwable) {
            JSONObject()
        }
        obj.put(key, url)
        prefs.edit().putString(KEY_ART_CACHE, obj.toString()).apply()
    }

    /** Called from AudioPlayerPlugin when Dart pushes setLovedState. We
     *  use it to prime the cache and swap the button, so a Dart-initiated
     *  love shows up on the AA screen without waiting on the network. */
    fun applyDartLovedState(artist: String, title: String, loved: Boolean) {
        setCachedLoved(artist, title, loved)
        refreshLoveButton()
    }

    /** Called by AudioPlayerPlugin when Dart invokes syncLastfmSession.
     *  When the user logs out we clear the loved cache so a subsequent
     *  login doesn't surface stale state from a different account. */
    fun onLastfmAuthChanged(loggedIn: Boolean) {
        if (!loggedIn) {
            prefs.edit().remove(KEY_LOVED_TRACKS).apply()
            lastLoveCheckedKey = ""
        }
        refreshLoveButton()
        if (loggedIn) onTrackIdentityChanged()
    }

    /** One-shot clear of the native art cache after a chain logic
     *  change. Bumping KEY_ART_CACHE_MIGRATION's suffix forces the next
     *  startup to run this again. */
    private fun runArtCacheMigration() {
        if (prefs.getBoolean(KEY_ART_CACHE_MIGRATION, false)) return
        prefs.edit()
            .remove(KEY_ART_CACHE)
            .putBoolean(KEY_ART_CACHE_MIGRATION, true)
            .apply()
        Log.d(TAG, "art cache migration: cleared KEY_ART_CACHE")
    }
}
