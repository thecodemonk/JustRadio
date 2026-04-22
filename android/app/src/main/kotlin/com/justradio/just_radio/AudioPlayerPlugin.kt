package com.justradio.just_radio

import android.content.ComponentName
import android.content.Context
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.util.Log
import androidx.media3.common.MediaItem
import androidx.media3.common.MediaMetadata
import androidx.media3.common.PlaybackException
import androidx.media3.common.Player
import androidx.media3.common.util.UnstableApi
import androidx.media3.session.MediaController
import androidx.media3.session.SessionCommand
import androidx.media3.session.SessionResult
import androidx.media3.session.SessionToken
import com.google.common.util.concurrent.ListenableFuture
import com.google.common.util.concurrent.MoreExecutors
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.json.JSONArray
import org.json.JSONObject

/**
 * Flutter bridge to [PlaybackService]. Connects as a MediaController and
 * forwards play/pause/stop commands + state/metadata events to Dart. Also
 * mirrors favorites / recently played / genres into SharedPreferences so
 * [PlaybackService] can serve them to Android Auto without a Dart runtime
 * attached (Android Auto can start the service cold).
 */
@UnstableApi
class AudioPlayerPlugin :
    FlutterPlugin,
    MethodChannel.MethodCallHandler,
    EventChannel.StreamHandler {

    companion object {
        private const val TAG = "AudioPlayerPlugin"
    }

    private val mainHandler = Handler(Looper.getMainLooper())
    private var context: Context? = null
    private var methodChannel: MethodChannel? = null
    private var eventChannel: EventChannel? = null
    private var eventSink: EventChannel.EventSink? = null

    private var controllerFuture: ListenableFuture<MediaController>? = null
    private var controller: MediaController? = null

    /// Last volume Dart pushed down. Applied to the MediaController when it
    /// finishes connecting — if setVolume fires before connect (Dart restores
    /// the persisted slider value early at startup), we'd otherwise lose it.
    private var lastVolume: Float = 1f

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        Log.d(TAG, "onAttachedToEngine")
        val ctx = binding.applicationContext
        context = ctx
        methodChannel = MethodChannel(binding.binaryMessenger, "justradio/audio")
        methodChannel?.setMethodCallHandler(this)
        eventChannel = EventChannel(binding.binaryMessenger, "justradio/audio/events")
        eventChannel?.setStreamHandler(this)

        // Connect to the PlaybackService. buildAsync will start the service
        // if it isn't already running. ping() from Dart awaits this future
        // before subscribing to the event channel.
        //
        // Two listener interfaces: Player.Listener (state/metadata changes)
        // is registered on the controller post-connect via addListener;
        // MediaController.Listener (onCustomCommand, onDisconnected) is set
        // on the Builder before connect. The same object implements both.
        val listener = ControllerListener()
        val token = SessionToken(ctx, ComponentName(ctx, PlaybackService::class.java))
        val future = MediaController.Builder(ctx, token)
            .setListener(listener)
            .buildAsync()
        controllerFuture = future
        future.addListener(
            {
                try {
                    val c = future.get()
                    controller = c
                    c.addListener(listener)
                    // Catch up on any volume Dart set before we finished
                    // connecting — the persisted startup value gets pushed
                    // from VolumeController.init before the controller is
                    // usually ready.
                    c.volume = lastVolume.coerceIn(0f, 1f)
                    Log.d(TAG, "MediaController connected")
                } catch (t: Throwable) {
                    Log.e(TAG, "MediaController connect failed", t)
                }
            },
            MoreExecutors.directExecutor()
        )
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        Log.d(TAG, "onDetachedFromEngine")
        controllerFuture?.let { MediaController.releaseFuture(it) }
        controllerFuture = null
        controller = null
        methodChannel?.setMethodCallHandler(null)
        eventChannel?.setStreamHandler(null)
        methodChannel = null
        eventChannel = null
        context = null
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "ping" -> {
                // Dart retries this until the plugin is registered AND the
                // controller is connected. Returning true here signals both.
                result.success(controller != null)
            }
            "playStation" -> {
                val url = call.argument<String>("url") ?: ""
                val uuid = call.argument<String>("stationuuid") ?: ""
                val name = call.argument<String>("name") ?: ""
                val favicon = call.argument<String>("favicon") ?: ""
                playUrl(url, uuid, name, favicon)
                result.success(null)
            }
            "play" -> {
                controller?.play()
                result.success(null)
            }
            "pause" -> {
                controller?.pause()
                result.success(null)
            }
            "stop" -> {
                controller?.stop()
                controller?.clearMediaItems()
                sendEvent(mapOf("type" to "state", "state" to "stopped"))
                result.success(null)
            }
            "setVolume" -> {
                val volume = (call.argument<Double>("volume") ?: 1.0).toFloat()
                lastVolume = volume.coerceIn(0f, 1f)
                controller?.volume = lastVolume
                result.success(null)
            }
            "syncFavorites" -> {
                val list = call.argument<List<Map<String, Any?>>>("stations") ?: emptyList()
                writePrefsJson(PlaybackService.KEY_FAVORITES, list)
                result.success(null)
            }
            "syncRecent" -> {
                val list = call.argument<List<Map<String, Any?>>>("stations") ?: emptyList()
                writePrefsJson(PlaybackService.KEY_RECENT, list)
                result.success(null)
            }
            "syncGenres" -> {
                val list = call.argument<List<Map<String, Any?>>>("genres") ?: emptyList()
                writePrefsJson(PlaybackService.KEY_GENRES, list)
                result.success(null)
            }
            "syncGenreStations" -> {
                val tag = call.argument<String>("tag") ?: ""
                val list = call.argument<List<Map<String, Any?>>>("stations") ?: emptyList()
                if (tag.isNotEmpty()) {
                    writePrefsJson(PlaybackService.keyForGenreStations(tag), list)
                }
                result.success(null)
            }
            "setAlbumArt" -> {
                // Update the current MediaItem's artworkUri without
                // interrupting playback. media3's replaceMediaItem is safe
                // for in-place metadata changes when the URI is unchanged.
                // Android Auto picks up the new art via onMediaMetadataChanged.
                val url = call.argument<String>("url") ?: ""
                val c = controller
                val current = c?.currentMediaItem
                if (c != null && current != null) {
                    val artUri = if (url.isEmpty()) null else android.net.Uri.parse(url)
                    val newMeta = current.mediaMetadata.buildUpon()
                        .setArtworkUri(artUri)
                        .build()
                    val updated = current.buildUpon().setMediaMetadata(newMeta).build()
                    c.replaceMediaItem(c.currentMediaItemIndex, updated)
                }
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    private fun playUrl(url: String, uuid: String, name: String, favicon: String) {
        val c = controller
        if (c == null || url.isEmpty()) {
            sendEvent(mapOf("type" to "state", "state" to "error", "message" to "Invalid URL"))
            return
        }
        val uri = android.net.Uri.parse(url)
        val metadata = MediaMetadata.Builder()
            .setTitle(name.ifEmpty { "JustRadio" })
            .setArtworkUri(favicon.takeIf { it.isNotEmpty() }?.let { android.net.Uri.parse(it) })
            .setIsBrowsable(false)
            .setIsPlayable(true)
            .setMediaType(MediaMetadata.MEDIA_TYPE_RADIO_STATION)
            .build()
        val requestMetadata = MediaItem.RequestMetadata.Builder()
            .setMediaUri(uri)
            .build()
        val itemId =
            if (uuid.isNotEmpty()) PlaybackService.STATION_PREFIX + uuid else "adhoc:$url"
        val mediaItem = MediaItem.Builder()
            .setMediaId(itemId)
            .setUri(uri)
            .setMediaMetadata(metadata)
            .setRequestMetadata(requestMetadata)
            .build()
        c.setMediaItem(mediaItem)
        c.prepare()
        c.play()
        sendEvent(mapOf("type" to "state", "state" to "loading"))
    }

    private fun writePrefsJson(key: String, items: List<Map<String, Any?>>) {
        val ctx = context ?: return
        val arr = JSONArray()
        for (item in items) {
            val obj = JSONObject()
            for ((k, v) in item) {
                obj.put(k, v ?: JSONObject.NULL)
            }
            arr.put(obj)
        }
        ctx.getSharedPreferences(PlaybackService.PREFS_NAME, Context.MODE_PRIVATE)
            .edit()
            .putString(key, arr.toString())
            .apply()
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        eventSink = events
    }

    override fun onCancel(arguments: Any?) {
        eventSink = null
    }

    private inner class ControllerListener : Player.Listener, MediaController.Listener {
        override fun onPlaybackStateChanged(state: Int) {
            val name = when (state) {
                Player.STATE_IDLE -> "idle"
                Player.STATE_BUFFERING -> "loading"
                Player.STATE_READY ->
                    if (controller?.isPlaying == true) "playing" else "paused"
                Player.STATE_ENDED -> "stopped"
                else -> "idle"
            }
            sendEvent(mapOf("type" to "state", "state" to name))
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

        override fun onMediaMetadataChanged(mediaMetadata: MediaMetadata) {
            val title = mediaMetadata.title?.toString()
            val artist = mediaMetadata.artist?.toString()
            val album = mediaMetadata.albumTitle?.toString()
            if (title == null && artist == null && album == null) return
            sendEvent(
                mapOf(
                    "type" to "metadata",
                    "identifier" to "media/aggregated",
                    "title" to title,
                    "artist" to artist,
                    "album" to album,
                )
            )
        }

        // Stream info, icy headers, and raw ID3 frames are pushed from the
        // service via broadcastCustomCommand — everything that doesn't fit
        // cleanly into MediaMetadata.
        override fun onCustomCommand(
            controller: MediaController,
            command: SessionCommand,
            args: Bundle
        ): ListenableFuture<SessionResult> {
            val payload = bundleToEvent(command.customAction, args)
            if (payload != null) sendEvent(payload)
            return com.google.common.util.concurrent.Futures.immediateFuture(
                SessionResult(SessionResult.RESULT_SUCCESS)
            )
        }
    }

    private fun bundleToEvent(action: String, args: Bundle): Map<String, Any?>? {
        val result = mutableMapOf<String, Any?>("type" to "metadata")
        // Fold bundle contents directly into the event payload — Dart's
        // _onMetadataEvent picks up whichever fields are present, matching
        // the old plugin's flat-map behavior.
        if (action == PlaybackService.CMD_STREAM_INFO ||
            action == PlaybackService.CMD_RAW_METADATA
        ) {
            result["identifier"] = args.getString("identifier")
                ?: if (action == PlaybackService.CMD_STREAM_INFO) "stream/info" else "raw"
            args.getString("title")?.let { result["title"] = it }
            args.getString("artist")?.let { result["artist"] = it }
            args.getString("album")?.let { result["album"] = it }
            args.getString("codec")?.let { result["codec"] = it }
            args.getString("streamName")?.let { result["streamName"] = it }
            args.getString("genre")?.let { result["genre"] = it }
            args.getString("streamUrl")?.let { result["streamUrl"] = it }
            args.getString("stringValue")?.let { result["stringValue"] = it }
            args.getString("txxxDescriptor")?.let { result["txxxDescriptor"] = it }
            args.getString("error")?.let { result["message"] = it }
            if (args.containsKey("bitrate")) {
                val br = args.getInt("bitrate", 0)
                if (br > 0) result["bitrate"] = br
            }
            return result
        }
        return null
    }

    private fun sendEvent(payload: Map<String, Any?>) {
        mainHandler.post { eventSink?.success(payload) }
    }
}
