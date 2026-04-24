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

        /**
         * Tracks whether a Flutter engine is currently attached to this
         * plugin. Read by PlaybackService to decide whether native
         * scrobbling (+ updateNowPlaying) should fire — when Dart is
         * running, it handles those from RadioPlayerController via its
         * own nowPlayingStream listener, and we'd otherwise double up.
         * Volatile so reads across threads see the latest write.
         */
        @Volatile
        var isFlutterAttached: Boolean = false
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
        isFlutterAttached = true
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
                    // If Android Auto started the service cold, there's
                    // already a media item + state in the session. Dart
                    // subscribes to `Player.Listener` events via the
                    // controller, but those only fire on *changes* — not
                    // the current snapshot. Sync the current state so the
                    // UI matches what's actually playing.
                    emitSyncStateIfPlaying(c)
                } catch (t: Throwable) {
                    Log.e(TAG, "MediaController connect failed", t)
                }
            },
            MoreExecutors.directExecutor()
        )
    }

    /// Snapshot the controller's currently-playing station (if any) and
    /// push it to Dart via a "syncState" event. Dart's handler rebuilds
    /// the RadioStation from the station JSON cached in SharedPreferences
    /// by previous `syncFavorites`/`syncRecent`/`syncGenreStations` calls.
    /// Without this, opening JustRadio on the phone while AA has been
    /// playing a station shows a blank player.
    private fun emitSyncStateIfPlaying(c: MediaController) {
        val item = c.currentMediaItem
        if (item == null) {
            Log.d(TAG, "syncState: currentMediaItem is null (nothing playing)")
            return
        }
        val mediaId = item.mediaId
        Log.d(TAG, "syncState: currentMediaItem mediaId=$mediaId isPlaying=${c.isPlaying}")
        if (!mediaId.startsWith(PlaybackService.STATION_PREFIX)) {
            Log.d(TAG, "syncState: skipping, not a station: $mediaId")
            return
        }
        val ctx = context ?: run {
            Log.d(TAG, "syncState: context null")
            return
        }
        val stationJson = findStationJson(ctx, mediaId) ?: run {
            Log.d(TAG, "syncState: no station JSON cached for $mediaId")
            return
        }
        val md = item.mediaMetadata
        val artworkUri = md.artworkUri?.toString().orEmpty()
        val title = md.title?.toString().orEmpty()
        val artist = md.artist?.toString().orEmpty()
        val album = md.albumTitle?.toString().orEmpty()
        Log.d(TAG, "syncState: emitting station=${stationJson.optString("name")} artist=$artist title=$title isPlaying=${c.isPlaying}")
        // Same mapping Dart uses to reconstruct a RadioStation in
        // NativeAudioPlayerService._onSyncState.
        val stationMap = jsonToMap(stationJson)
        sendEvent(
            mapOf(
                "type" to "syncState",
                "station" to stationMap,
                "title" to title,
                "artist" to artist,
                "album" to album,
                "albumArtUrl" to artworkUri,
                "isPlaying" to c.isPlaying,
            )
        )
        // Mirror the playback state event so any listener that only
        // watches state (not syncState) flips to the right value.
        sendEvent(
            mapOf(
                "type" to "state",
                "state" to if (c.isPlaying) "playing" else "paused",
            )
        )
    }

    /// Walk the same SharedPreferences lists PlaybackService uses to
    /// serve the AA browse tree. Returns the raw JSONObject for the
    /// matching station, or null when nothing matches. Favorites /
    /// recent / genre_stations.* are the only places a station JSON
    /// lives — if the user played something not in any of those (edge
    /// case), we return null and skip the sync.
    private fun findStationJson(ctx: Context, mediaId: String): JSONObject? {
        val uuid = mediaId.removePrefix(PlaybackService.STATION_PREFIX)
        if (uuid.isEmpty()) return null
        val prefs = ctx.getSharedPreferences(
            PlaybackService.PREFS_NAME, Context.MODE_PRIVATE
        )
        // Fixed-key lists first (common hit path).
        for (key in listOf(PlaybackService.KEY_FAVORITES, PlaybackService.KEY_RECENT)) {
            findStationInArray(prefs.getString(key, null), uuid)?.let { return it }
        }
        // Genre lists — keyed by tag.
        for ((k, v) in prefs.all) {
            if (!k.startsWith("genre_stations.")) continue
            findStationInArray(v as? String, uuid)?.let { return it }
        }
        return null
    }

    private fun findStationInArray(json: String?, uuid: String): JSONObject? {
        if (json.isNullOrEmpty()) return null
        val arr = try { JSONArray(json) } catch (_: Throwable) { return null }
        for (i in 0 until arr.length()) {
            val obj = arr.optJSONObject(i) ?: continue
            if (obj.optString("stationuuid") == uuid) return obj
        }
        return null
    }

    private fun jsonToMap(obj: JSONObject): Map<String, Any?> {
        val out = mutableMapOf<String, Any?>()
        val keys = obj.keys()
        while (keys.hasNext()) {
            val k = keys.next()
            val v = obj.opt(k)
            out[k] = if (v === JSONObject.NULL) null else v
        }
        return out
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        Log.d(TAG, "onDetachedFromEngine")
        isFlutterAttached = false
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
            "requestSync" -> {
                // Called by Dart once it has subscribed to the event channel.
                // Necessary because the auto-emit in MediaController.connect's
                // future callback can fire before the eventSink is attached,
                // silently dropping the syncState event. Calling this after
                // onListen guarantees delivery.
                val c = controller
                if (c != null) {
                    emitSyncStateIfPlaying(c)
                } else {
                    Log.d(TAG, "requestSync: controller not connected yet")
                }
                result.success(null)
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
                // Android Auto picks up the new art from MediaMetadata.
                val url = call.argument<String>("url") ?: ""
                val c = controller
                val current = c?.currentMediaItem
                Log.d(
                    TAG,
                    "setAlbumArt url='$url' controller=${c != null} currentItem=${current != null}"
                )
                if (c != null && current != null) {
                    val artUri = if (url.isEmpty()) null else android.net.Uri.parse(url)
                    val newMeta = current.mediaMetadata.buildUpon()
                        .setArtworkUri(artUri)
                        .build()
                    val updated = current.buildUpon().setMediaMetadata(newMeta).build()
                    c.replaceMediaItem(c.currentMediaItemIndex, updated)
                    Log.d(TAG, "setAlbumArt -> replaceMediaItem done")
                }
                result.success(null)
            }
            "syncLastfmSession" -> {
                val sessionKey = call.argument<String>("sessionKey") ?: ""
                val username = call.argument<String>("username") ?: ""
                writePref(PlaybackService.KEY_LASTFM_SESSION, sessionKey)
                writePref(PlaybackService.KEY_LASTFM_USERNAME, username)
                // Poke the service so it refreshes the love button and
                // clears the cache if the user just logged out.
                controller?.sendCustomCommand(
                    SessionCommand(PlaybackService.CMD_DART_AUTH_CHANGED, Bundle.EMPTY),
                    Bundle().apply { putBoolean("loggedIn", sessionKey.isNotEmpty()) }
                )
                result.success(null)
            }
            "syncLastfmConfig" -> {
                val apiKey = call.argument<String>("apiKey") ?: ""
                val apiSecret = call.argument<String>("apiSecret") ?: ""
                writePref(PlaybackService.KEY_LASTFM_API_KEY, apiKey)
                writePref(PlaybackService.KEY_LASTFM_API_SECRET, apiSecret)
                result.success(null)
            }
            "setLovedState" -> {
                val artist = call.argument<String>("artist") ?: ""
                val title = call.argument<String>("title") ?: ""
                val loved = call.argument<Boolean>("loved") ?: false
                controller?.sendCustomCommand(
                    SessionCommand(PlaybackService.CMD_DART_SET_LOVED, Bundle.EMPTY),
                    Bundle().apply {
                        putString("artist", artist)
                        putString("title", title)
                        putBoolean("loved", loved)
                    }
                )
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    private fun writePref(key: String, value: String) {
        val ctx = context ?: return
        ctx.getSharedPreferences(PlaybackService.PREFS_NAME, Context.MODE_PRIVATE)
            .edit()
            .putString(key, value)
            .apply()
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
        // Fold bundle contents directly into the event payload — Dart's
        // _onMetadataEvent picks up whichever fields are present, matching
        // the old plugin's flat-map behavior.
        if (action == PlaybackService.CMD_STREAM_INFO ||
            action == PlaybackService.CMD_RAW_METADATA
        ) {
            val result = mutableMapOf<String, Any?>("type" to "metadata")
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
        if (action == PlaybackService.CMD_LOVED_STATE) {
            return mapOf(
                "type" to "lovedStateChanged",
                "artist" to args.getString("artist"),
                "title" to args.getString("title"),
                "loved" to args.getBoolean("loved", false),
            )
        }
        return null
    }

    private fun sendEvent(payload: Map<String, Any?>) {
        mainHandler.post { eventSink?.success(payload) }
    }
}
