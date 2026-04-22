package com.justradio.just_radio

import android.content.Context
import android.os.Handler
import android.os.Looper
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
import androidx.media3.exoplayer.source.MediaSource
import androidx.media3.extractor.metadata.icy.IcyHeaders
import androidx.media3.extractor.metadata.icy.IcyInfo
import androidx.media3.extractor.metadata.id3.TextInformationFrame
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Native Android audio engine for JustRadio. Wraps ExoPlayer (media3) and surfaces:
 *   - playback state (via Player.Listener.onPlaybackStateChanged + onIsPlayingChanged)
 *   - timed metadata (ICY StreamTitle + HLS ID3 TIT2/TPE1) via
 *     Player.Listener.onMetadata — uniform for both protocols, which just_audio's
 *     icyMetadataStream does not cover.
 */
@UnstableApi
class AudioPlayerPlugin :
    FlutterPlugin,
    MethodChannel.MethodCallHandler,
    EventChannel.StreamHandler {

    private val mainHandler = Handler(Looper.getMainLooper())
    private var context: Context? = null
    private var methodChannel: MethodChannel? = null
    private var eventChannel: EventChannel? = null
    private var eventSink: EventChannel.EventSink? = null
    private var player: ExoPlayer? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        Log.d(TAG, "onAttachedToEngine: registering channels")
        context = binding.applicationContext
        methodChannel = MethodChannel(binding.binaryMessenger, "justradio/audio")
        methodChannel?.setMethodCallHandler(this)
        eventChannel = EventChannel(binding.binaryMessenger, "justradio/audio/events")
        eventChannel?.setStreamHandler(this)
    }

    companion object {
        private const val TAG = "AudioPlayerPlugin"
        // Flip to true to emit verbose metadata-pipeline debug events over the
        // event channel (track-group dumps, every onMetadata firing). Off by
        // default — useful only when a specific stream misbehaves.
        private const val VERBOSE_LOGGING = false
    }

    private fun sendDebug(message: () -> String) {
        if (!VERBOSE_LOGGING) return
        sendEvent(mapOf("type" to "debug", "message" to message()))
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        stopPlayer()
        methodChannel?.setMethodCallHandler(null)
        eventChannel?.setStreamHandler(null)
        methodChannel = null
        eventChannel = null
        context = null
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "ping" -> {
                // Dart calls this with retry at startup to confirm the plugin
                // is registered before subscribing to the event channel — the
                // event channel's listen invocation is fire-and-forget inside
                // Flutter, so we can't detect attach-race failures there.
                result.success(true)
            }
            "playStation" -> {
                val url = call.argument<String>("url") ?: ""
                playStation(url)
                result.success(null)
            }
            "play" -> {
                player?.play()
                result.success(null)
            }
            "pause" -> {
                player?.pause()
                result.success(null)
            }
            "stop" -> {
                stopPlayer()
                result.success(null)
            }
            "setVolume" -> {
                val volume = (call.argument<Double>("volume") ?: 1.0).toFloat()
                player?.volume = volume.coerceIn(0f, 1f)
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        eventSink = events
    }

    override fun onCancel(arguments: Any?) {
        eventSink = null
    }

    private fun playStation(url: String) {
        stopPlayer()
        val ctx = context ?: return
        if (url.isEmpty()) {
            sendEvent(mapOf("type" to "state", "state" to "error", "message" to "Invalid URL"))
            return
        }

        val exo = ExoPlayer.Builder(ctx).build()
        exo.addListener(PlayerListener())

        val mediaItem = MediaItem.fromUri(url)
        // DefaultMediaSourceFactory auto-detects HLS from .m3u8 URLs and
        // uses ExoPlayer's standard HLS pipeline with default extractor
        // flags. Our previous explicit HlsMediaSource.Factory used a
        // minimal config that missed ID3 metadata in fMP4 audio segments.
        val source: MediaSource = DefaultMediaSourceFactory(ctx).createMediaSource(mediaItem)

        exo.setMediaSource(source)
        exo.prepare()
        exo.playWhenReady = true
        player = exo
        sendEvent(mapOf("type" to "state", "state" to "loading"))
    }

    private fun stopPlayer() {
        player?.release()
        player = null
        sendEvent(mapOf("type" to "state", "state" to "stopped"))
    }

    private inner class PlayerListener : Player.Listener {
        override fun onPlaybackStateChanged(state: Int) {
            val stateName =
                when (state) {
                    Player.STATE_IDLE -> "idle"
                    Player.STATE_BUFFERING -> "loading"
                    Player.STATE_READY -> if (player?.isPlaying == true) "playing" else "paused"
                    Player.STATE_ENDED -> "stopped"
                    else -> "idle"
                }
            sendEvent(mapOf("type" to "state", "state" to stateName))
        }

        override fun onIsPlayingChanged(isPlaying: Boolean) {
            sendEvent(
                mapOf("type" to "state", "state" to if (isPlaying) "playing" else "paused")
            )
        }

        override fun onPlayerError(error: PlaybackException) {
            sendEvent(
                mapOf("type" to "state", "state" to "error", "message" to error.message)
            )
        }

        override fun onTracksChanged(tracks: Tracks) {
            // Dump every group/track so we can see what ExoPlayer selects for
            // HLS streams — metadata tracks should appear here if present.
            val summary = tracks.groups.joinToString(" | ") { group ->
                val typeName = when (group.type) {
                    C.TRACK_TYPE_AUDIO -> "audio"
                    C.TRACK_TYPE_VIDEO -> "video"
                    C.TRACK_TYPE_METADATA -> "metadata"
                    C.TRACK_TYPE_TEXT -> "text"
                    else -> "type=${group.type}"
                }
                val fmts = (0 until group.length).map { i ->
                    val f = group.getTrackFormat(i)
                    val selected = if (group.isTrackSelected(i)) "*" else " "
                    "${selected}${f.sampleMimeType ?: "?"} br=${f.bitrate}"
                }.joinToString(",")
                "$typeName[$fmts]"
            }
            sendDebug { "tracks: $summary" }

            for (group in tracks.groups) {
                if (group.type != C.TRACK_TYPE_AUDIO) continue
                for (i in 0 until group.length) {
                    if (!group.isTrackSelected(i)) continue
                    val bps = group.getTrackFormat(i).bitrate
                    if (bps > 0) {
                        sendEvent(
                            mapOf(
                                "type" to "metadata",
                                "identifier" to "stream/info",
                                "bitrate" to bps / 1000,
                            )
                        )
                    }
                }
            }
        }

        override fun onMediaMetadataChanged(mediaMetadata: MediaMetadata) {
            // Higher-level aggregated metadata from all sources. ExoPlayer
            // populates this from ICY/ID3 as it parses them — catches cases
            // where onMetadata itself doesn't fire for some HLS flows.
            val t = mediaMetadata.title?.toString()
            val a = mediaMetadata.artist?.toString()
            val al = mediaMetadata.albumTitle?.toString()
            if (t == null && a == null && al == null) return
            sendEvent(
                mapOf(
                    "type" to "metadata",
                    "identifier" to "media/aggregated",
                    "title" to t,
                    "artist" to a,
                    "album" to al,
                )
            )
        }

        override fun onMetadata(metadata: Metadata) {
            sendDebug {
                val classes = (0 until metadata.length()).joinToString(",") {
                    metadata[it].javaClass.simpleName
                }
                "onMetadata fired, entries=${metadata.length()} types=$classes"
            }
            for (i in 0 until metadata.length()) {
                val entry = metadata[i]
                when (entry) {
                    is IcyInfo -> {
                        val title = entry.title
                        sendEvent(
                            mapOf(
                                "type" to "metadata",
                                "identifier" to "icy/StreamTitle",
                                "stringValue" to title,
                                "title" to title,
                            )
                        )
                    }
                    is IcyHeaders -> {
                        sendEvent(
                            mapOf(
                                "type" to "metadata",
                                "identifier" to "icy/headers",
                                "streamName" to entry.name,
                                "genre" to entry.genre,
                                "bitrate" to entry.bitrate,
                                "streamUrl" to entry.url,
                            )
                        )
                    }
                    is TextInformationFrame -> {
                        // HLS ID3 frames — map TIT2/TPE1/TALB/TFLT to named
                        // fields, and parse TXXX user-defined frames where
                        // SomaFM embeds bitrate/sampleRate/channels under
                        // 3-letter descriptors (adr/asr/ach/etc.).
                        val id = entry.id ?: ""
                        val value = (entry.values.firstOrNull() ?: entry.value)
                        val description = entry.description
                        var bitrate: Int? = null
                        if (id == "TXXX") {
                            val n = value?.toIntOrNull()
                            val desc = description?.lowercase() ?: ""
                            val bitrateKeys = listOf(
                                "bitrate", "kbps", "adr", "audiodatarate", "br"
                            )
                            val nonBitrateKeys = listOf(
                                "sample", "asr", "channel", "ach", "enc",
                                "dev", "crd", "date", "time", "year"
                            )
                            val isBitrate = bitrateKeys.any { desc.contains(it) }
                            val isKnownOther = nonBitrateKeys.any { desc.contains(it) }
                            val byRange = !isKnownOther && n != null && n in 64..2000
                            if (n != null && (isBitrate || byRange)) {
                                bitrate = n
                            }
                        }
                        sendEvent(
                            mapOf(
                                "type" to "metadata",
                                "identifier" to "id3/$id",
                                "stringValue" to value,
                                "title" to if (id == "TIT2") value else null,
                                "artist" to if (id == "TPE1") value else null,
                                "album" to if (id == "TALB") value else null,
                                "codec" to if (id == "TFLT") value else null,
                                "bitrate" to bitrate,
                                "txxxDescriptor" to description,
                            )
                        )
                    }
                    else -> {
                        sendEvent(
                            mapOf(
                                "type" to "metadata",
                                "identifier" to entry.javaClass.simpleName,
                                "stringValue" to entry.toString(),
                            )
                        )
                    }
                }
            }
        }
    }

    private fun sendEvent(payload: Map<String, Any?>) {
        mainHandler.post { eventSink?.success(payload) }
    }
}
