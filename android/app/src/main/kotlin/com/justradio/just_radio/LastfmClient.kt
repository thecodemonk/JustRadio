package com.justradio.just_radio

import android.util.Log
import java.net.HttpURLConnection
import java.net.URL
import java.net.URLEncoder
import java.security.MessageDigest
import org.json.JSONObject

/**
 * Native Last.fm client used by [PlaybackService] when Flutter isn't
 * running — Android Auto can start the service cold, so the love button
 * must be wired up without Dart.
 *
 * Mirrors the Dart LastfmRepository for track.love / track.unlove /
 * track.getInfo. Signing is MD5 over alphabetically-sorted key+value
 * pairs followed by the shared secret, matching
 * [lib/core/utils/md5_helper.dart].
 *
 * All methods block the calling thread on I/O. Callers dispatch to a
 * background executor.
 */
internal object LastfmClient {
    private const val TAG = "LastfmClient"
    private const val BASE_URL = "https://ws.audioscrobbler.com/2.0/"

    data class Creds(
        val apiKey: String,
        val apiSecret: String,
        val sessionKey: String,
    )

    /** Toggle a track's loved state. Returns true on success. */
    fun loveTrack(artist: String, title: String, creds: Creds): Boolean =
        signedPost(
            linkedMapOf(
                "method" to "track.love",
                "artist" to artist,
                "track" to title,
            ),
            creds,
        )

    fun unloveTrack(artist: String, title: String, creds: Creds): Boolean =
        signedPost(
            linkedMapOf(
                "method" to "track.unlove",
                "artist" to artist,
                "track" to title,
            ),
            creds,
        )

    /** Tell Last.fm the user is currently listening to this track.
     *  Fires once per track change; does NOT record a scrobble. Last.fm
     *  uses this to paint the "now listening to" indicator on the
     *  user's profile. */
    fun updateNowPlaying(
        artist: String,
        title: String,
        album: String?,
        creds: Creds,
    ): Boolean {
        val params = linkedMapOf(
            "method" to "track.updateNowPlaying",
            "artist" to artist,
            "track" to title,
        )
        if (!album.isNullOrBlank()) params["album"] = album
        return signedPost(params, creds)
    }

    /** Record a scrobble — the track has played long enough to count.
     *  Callers enforce the 30-second minimum; this method just fires
     *  the signed POST. `timestampSec` is when the track STARTED, in
     *  Unix epoch seconds UTC. */
    fun scrobble(
        artist: String,
        title: String,
        timestampSec: Long,
        album: String?,
        creds: Creds,
    ): Boolean {
        val params = linkedMapOf(
            "method" to "track.scrobble",
            "artist" to artist,
            "track" to title,
            "timestamp" to timestampSec.toString(),
        )
        if (!album.isNullOrBlank()) params["album"] = album
        return signedPost(params, creds)
    }

    /** Unauth'd lookup: whether `username` has loved this track. Returns
     *  false on any failure, including unknown tracks. */
    fun isTrackLoved(
        artist: String,
        title: String,
        username: String,
        apiKey: String,
    ): Boolean {
        val params = linkedMapOf(
            "method" to "track.getInfo",
            "api_key" to apiKey,
            "artist" to artist,
            "track" to title,
            "username" to username,
            "format" to "json",
        )
        val url = URL(BASE_URL + "?" + formUrlEncode(params))
        return try {
            val conn = (url.openConnection() as HttpURLConnection).apply {
                requestMethod = "GET"
                connectTimeout = 10_000
                readTimeout = 10_000
            }
            val code = conn.responseCode
            if (code !in 200..299) {
                Log.w(TAG, "track.getInfo http=$code")
                conn.disconnect()
                return false
            }
            val body = conn.inputStream.bufferedReader(Charsets.UTF_8).use { it.readText() }
            conn.disconnect()
            val json = JSONObject(body)
            val track = json.optJSONObject("track") ?: return false
            track.optString("userloved") == "1"
        } catch (t: Throwable) {
            Log.w(TAG, "track.getInfo failed: ${t.message}")
            false
        }
    }

    /**
     * Generic signed POST. Accepts a method-specific param map; adds
     * api_key + sk, computes api_sig from the sorted concatenation, and
     * sends the whole thing as application/x-www-form-urlencoded.
     * Every signed Last.fm write endpoint (love/unlove/scrobble/
     * updateNowPlaying) uses this path.
     */
    private fun signedPost(
        methodParams: LinkedHashMap<String, String>,
        creds: Creds,
    ): Boolean {
        val methodName = methodParams["method"] ?: "unknown"
        val signParams = LinkedHashMap<String, String>(methodParams).apply {
            put("api_key", creds.apiKey)
            put("sk", creds.sessionKey)
        }
        val signature = signLastfm(signParams, creds.apiSecret)
        val body = linkedMapOf<String, String>()
        body.putAll(signParams)
        body["api_sig"] = signature
        body["format"] = "json"

        return try {
            val conn = (URL(BASE_URL).openConnection() as HttpURLConnection).apply {
                requestMethod = "POST"
                doOutput = true
                setRequestProperty("Content-Type", "application/x-www-form-urlencoded")
                connectTimeout = 10_000
                readTimeout = 10_000
            }
            val payload = formUrlEncode(body)
            conn.outputStream.use { it.write(payload.toByteArray(Charsets.UTF_8)) }
            val code = conn.responseCode
            // Last.fm returns 200 even for API errors — parse the body.
            val stream = if (code in 200..299) conn.inputStream else conn.errorStream
            val response = stream?.bufferedReader(Charsets.UTF_8)?.use { it.readText() } ?: ""
            conn.disconnect()
            if (code !in 200..299) {
                Log.w(TAG, "$methodName http=$code body=$response")
                return false
            }
            val json = try { JSONObject(response) } catch (_: Throwable) { null }
            val apiError = json?.optInt("error", 0) ?: 0
            if (apiError != 0) {
                Log.w(TAG, "$methodName api_error=$apiError body=$response")
                return false
            }
            true
        } catch (t: Throwable) {
            Log.w(TAG, "$methodName failed: ${t.message}")
            false
        }
    }

    private fun signLastfm(params: Map<String, String>, secret: String): String {
        val sorted = params.toSortedMap()
        val sb = StringBuilder()
        for ((k, v) in sorted) {
            sb.append(k).append(v)
        }
        sb.append(secret)
        val bytes = MessageDigest.getInstance("MD5")
            .digest(sb.toString().toByteArray(Charsets.UTF_8))
        return bytes.joinToString("") { "%02x".format(it) }
    }

    private fun formUrlEncode(params: Map<String, String>): String {
        val sb = StringBuilder()
        var first = true
        for ((k, v) in params) {
            if (!first) sb.append('&')
            first = false
            sb.append(URLEncoder.encode(k, "UTF-8"))
            sb.append('=')
            sb.append(URLEncoder.encode(v, "UTF-8"))
        }
        return sb.toString()
    }

}
