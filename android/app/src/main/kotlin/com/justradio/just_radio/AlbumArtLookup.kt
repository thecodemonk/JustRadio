package com.justradio.just_radio

import android.util.Log
import java.net.HttpURLConnection
import java.net.URL
import java.net.URLEncoder
import java.util.regex.Pattern
import org.json.JSONArray
import org.json.JSONObject

/**
 * Native album-art lookup. Mirrors lib/data/services/album_art_service.dart
 * so Android Auto gets covers even when Flutter isn't running (AA can
 * start the service cold, with no Dart engine attached).
 *
 * Chain: iTunes (US → GB → DE → ZA) → Deezer → MusicBrainz + CAA.
 *
 * No authentication — none of these endpoints require it. MB does
 * require a User-Agent + has a 1/sec hard rate limit; we reuse the same
 * UA string the Dart side uses and gate calls with a mutex + monotonic
 * delay.
 *
 * All methods block the calling thread on I/O. Callers dispatch to a
 * background executor.
 */
internal object AlbumArtLookup {
    private const val TAG = "AlbumArtLookup"

    private const val ITUNES_BASE = "https://itunes.apple.com"
    private const val DEEZER_BASE = "https://api.deezer.com"
    private const val MB_BASE = "https://musicbrainz.org"
    private const val CAA_BASE = "https://coverartarchive.org"
    private const val USER_AGENT =
        "JustRadio/1.0 ( https://github.com/thecodemonk/JustRadio )"

    private val itunesCountries = listOf("us", "gb", "de", "za")

    // MusicBrainz 1 req/sec gate. Serialized through a monitor + last-
    // call timestamp. This executor is invoked only when both iTunes and
    // Deezer have already missed, so contention is rare.
    private val mbLock = Any()
    private var mbLastCallMs: Long = 0

    /** Returns a resolved album-art URL, or null if nothing matched. */
    fun fetch(artist: String, title: String): String? {
        if (artist.isBlank() || title.isBlank()) return null
        val started = System.currentTimeMillis()

        itunesLookup(artist, title)?.let {
            Log.d(TAG, "resolved via=itunes in ${elapsed(started)}ms \"$artist - $title\"")
            return it
        }
        deezerLookup(artist, title)?.let {
            Log.d(TAG, "resolved via=deezer in ${elapsed(started)}ms \"$artist - $title\"")
            return it
        }
        musicBrainzLookup(artist, title)?.let {
            Log.d(TAG, "resolved via=musicbrainz in ${elapsed(started)}ms \"$artist - $title\"")
            return it
        }

        Log.d(TAG, "miss in ${elapsed(started)}ms \"$artist - $title\"")
        return null
    }

    private fun elapsed(from: Long): Long = System.currentTimeMillis() - from

    // ------------------------------------------------------------------
    // iTunes
    // ------------------------------------------------------------------

    private fun itunesLookup(artist: String, title: String): String? {
        for (cc in itunesCountries) {
            val url = itunesLookupIn(artist, title, cc)
            if (url != null) return url
        }
        return null
    }

    private fun itunesLookupIn(artist: String, title: String, country: String): String? {
        val term = urlEncode("$artist $title")
        val url = "$ITUNES_BASE/search?term=$term&media=music&entity=song&country=$country&limit=3"
        val body = httpGetString(url) ?: return null
        val results = try {
            JSONObject(body).optJSONArray("results") ?: return null
        } catch (_: Throwable) {
            return null
        }
        for (i in 0 until results.length()) {
            val entry = results.optJSONObject(i) ?: continue
            val candArtist = entry.optString("artistName")
            val candTitle = entry.optString("trackName")
            if (!matchesQuery(candArtist, candTitle, artist, title)) continue
            // Skip DJ-mix / various-artists compilations. iTunes signals
            // these by setting collectionArtistName to someone other
            // than the track's artistName. On the artist's own album
            // that field is absent.
            val collArtist = entry.optString("collectionArtistName")
            if (collArtist.isNotEmpty() &&
                normalize(collArtist) != normalize(candArtist)
            ) {
                Log.d(
                    TAG,
                    "itunes:$country skip compilation: collectionArtist=$collArtist vs trackArtist=$candArtist"
                )
                continue
            }
            val raw = entry.optString("artworkUrl100")
            if (raw.isEmpty()) continue
            return raw.replace(Regex("/\\d+x\\d+bb\\.(jpg|jpeg|png)$"), "/600x600bb.jpg")
        }
        return null
    }

    // ------------------------------------------------------------------
    // Deezer
    // ------------------------------------------------------------------

    private fun deezerLookup(artist: String, title: String): String? {
        val q = urlEncode("$artist $title")
        val url = "$DEEZER_BASE/search?q=$q&limit=3"
        val body = httpGetString(url) ?: return null
        val data = try {
            JSONObject(body).optJSONArray("data") ?: return null
        } catch (_: Throwable) {
            return null
        }
        for (i in 0 until data.length()) {
            val entry = data.optJSONObject(i) ?: continue
            val candTitle = entry.optString("title")
            val candArtist = entry.optJSONObject("artist")?.optString("name").orEmpty()
            if (!matchesQuery(candArtist, candTitle, artist, title)) continue
            val album = entry.optJSONObject("album") ?: continue
            for (field in listOf("cover_xl", "cover_big", "cover_medium")) {
                val u = album.optString(field)
                if (u.isNotEmpty()) return u
            }
        }
        return null
    }

    // ------------------------------------------------------------------
    // MusicBrainz + Cover Art Archive
    // ------------------------------------------------------------------

    private fun musicBrainzLookup(artist: String, title: String): String? {
        val result = mbSerialized { musicBrainzLookupUnguarded(artist, title) }
        return result
    }

    private fun musicBrainzLookupUnguarded(artist: String, title: String): String? {
        // Query by recording title only. Filtering by both artist AND
        // recording is brittle: MB's Lucene index is space-sensitive,
        // so "Leggobeast" (ICY one-word form) misses the canonical
        // "Leggo Beast". Let the (space-tolerant) match verifier filter
        // on artist downstream — titles are more stable across
        // catalogs than artist names.
        val query = "recording:\"${lucene(title)}\""
        val url =
            "$MB_BASE/ws/2/recording/?query=${urlEncode(query)}&fmt=json&limit=25"
        val body = httpGetString(url, userAgent = USER_AGENT, accept = "application/json")
            ?: return null
        val recordings = try {
            JSONObject(body).optJSONArray("recordings") ?: return null
        } catch (_: Throwable) {
            return null
        }
        var skippedCompilations = 0
        val limit = minOf(15, recordings.length())
        for (i in 0 until limit) {
            val rec = recordings.optJSONObject(i) ?: continue
            val candTitle = rec.optString("title")
            val candArtist = rec.optJSONArray("artist-credit")
                ?.optJSONObject(0)?.optString("name").orEmpty()
            if (!matchesQuery(candArtist, candTitle, artist, title)) continue
            val releases = rec.optJSONArray("releases") ?: continue
            val relLimit = minOf(3, releases.length())
            for (j in 0 until relLimit) {
                val rel = releases.optJSONObject(j) ?: continue
                if (isCompilation(rel)) {
                    skippedCompilations++
                    continue
                }
                val mbid = rel.optString("id")
                if (mbid.isEmpty()) continue
                val coverUrl = caaFront(mbid)
                if (coverUrl != null) {
                    Log.d(TAG, "mb hit mbid=$mbid release=\"${rel.optString("title")}\"")
                    return coverUrl
                }
            }
        }
        Log.d(TAG, "mb: no non-compilation art, skipped=$skippedCompilations")
        return null
    }

    private fun isCompilation(rel: JSONObject): Boolean {
        val group = rel.optJSONObject("release-group") ?: return false
        val secondary = group.optJSONArray("secondary-types") ?: return false
        for (i in 0 until secondary.length()) {
            if (secondary.optString(i).equals("Compilation", ignoreCase = true)) {
                return true
            }
        }
        return false
    }

    private fun caaFront(mbid: String): String? {
        val path = "/release/$mbid/front-500"
        val url = CAA_BASE + path
        return try {
            val conn = (URL(url).openConnection() as HttpURLConnection).apply {
                requestMethod = "HEAD"
                instanceFollowRedirects = true
                connectTimeout = 10_000
                readTimeout = 10_000
                setRequestProperty("User-Agent", USER_AGENT)
            }
            val code = conn.responseCode
            conn.disconnect()
            if (code in 200..399) url else null
        } catch (_: Throwable) {
            null
        }
    }

    /// Sleeps the calling thread to enforce MB's 1/sec rate limit. We
    /// run on a background executor already, so blocking here is fine.
    /// 1100ms gap is safely under 1/sec even with clock jitter.
    private fun <T> mbSerialized(block: () -> T): T {
        synchronized(mbLock) {
            val now = System.currentTimeMillis()
            val since = now - mbLastCallMs
            if (since in 0 until 1100) {
                try {
                    Thread.sleep(1100 - since)
                } catch (_: InterruptedException) {
                    Thread.currentThread().interrupt()
                }
            }
            try {
                return block()
            } finally {
                mbLastCallMs = System.currentTimeMillis()
            }
        }
    }

    /// Strip Lucene special chars so a title containing `:` or `"` doesn't
    /// break the MB query.
    private fun lucene(s: String): String =
        s.replace(Regex("[\\\\+\\-!()\\{}\\[\\]^\"~*?:/]"), " ")

    // ------------------------------------------------------------------
    // Match verification (port of lib/data/services/album_art_service.dart)
    // ------------------------------------------------------------------

    private val featRe =
        Pattern.compile("\\s+(feat\\.?|ft\\.?|featuring)\\s.+$", Pattern.CASE_INSENSITIVE)
    private val parenVersionRe =
        Pattern.compile(
            "\\s*\\((remix|live|acoustic|remaster(ed)?|radio edit|edit|version|mix)\\b[^)]*\\)",
            Pattern.CASE_INSENSITIVE
        )
    private val dashVersionRe =
        Pattern.compile(
            "\\s*-\\s*(remix|live|acoustic|remaster(ed)?|radio edit|edit|version|mix)\\b.*$",
            Pattern.CASE_INSENSITIVE
        )
    // Android's java.util.regex.Pattern does NOT support the
    // UNICODE_CHARACTER_CLASS flag (OpenJDK-only). The `\p{L}` / `\p{N}`
    // classes still resolve to Unicode categories via ICU without it,
    // so dropping the flag keeps non-Latin scripts (Cyrillic, CJK, etc.)
    // matched correctly.
    private val punctRe = Pattern.compile("[^\\p{L}\\p{N}\\s]")
    private val wsRe = Pattern.compile("\\s+")

    private fun normalize(s: String): String {
        var out = s.lowercase()
        out = featRe.matcher(out).replaceAll("")
        out = parenVersionRe.matcher(out).replaceAll("")
        out = dashVersionRe.matcher(out).replaceAll("")
        out = punctRe.matcher(out).replaceAll(" ")
        out = wsRe.matcher(out).replaceAll(" ").trim()
        return out
    }

    /**
     * Mirrors the Dart match-verifier. Also accepts the artist/title
     * swap case: some streams announce "Artist - Title" where the music
     * services' catalogs have them the other way around (e.g. SomaFM
     * "Northern Lights - Lux" vs. iTunes "Lux - Northern Lights").
     */
    private fun matchesQuery(
        candArtist: String,
        candTitle: String,
        qArtist: String,
        qTitle: String,
    ): Boolean {
        val a = normalize(candArtist)
        val t = normalize(candTitle)
        val qa = normalize(qArtist)
        val qt = normalize(qTitle)
        if (a.isEmpty() || t.isEmpty() || qa.isEmpty() || qt.isEmpty()) return false
        if (loosely(a, qa) && loosely(t, qt)) return true
        // Swap fallback.
        return loosely(a, qt) && loosely(t, qa)
    }

    /**
     * Loose match that also tolerates whitespace differences between
     * catalog entries and stream ICY metadata ("Freshmoods" vs
     * "Fresh Moods"). Any false positive from the space-stripped path
     * already existed under the contains check, which is itself
     * forgiving.
     */
    private fun loosely(x: String, y: String): Boolean {
        if (x == y || x.contains(y) || y.contains(x)) return true
        val xt = x.replace(" ", "")
        val yt = y.replace(" ", "")
        if (xt.isEmpty() || yt.isEmpty()) return false
        return xt == yt || xt.contains(yt) || yt.contains(xt)
    }

    // ------------------------------------------------------------------
    // HTTP helpers
    // ------------------------------------------------------------------

    private fun httpGetString(
        url: String,
        userAgent: String? = null,
        accept: String? = null,
    ): String? {
        return try {
            val conn = (URL(url).openConnection() as HttpURLConnection).apply {
                requestMethod = "GET"
                connectTimeout = 8_000
                readTimeout = 8_000
                if (userAgent != null) setRequestProperty("User-Agent", userAgent)
                if (accept != null) setRequestProperty("Accept", accept)
            }
            val code = conn.responseCode
            if (code !in 200..299) {
                conn.disconnect()
                return null
            }
            val body = conn.inputStream.bufferedReader(Charsets.UTF_8).use { it.readText() }
            conn.disconnect()
            body
        } catch (t: Throwable) {
            Log.w(TAG, "GET failed url=$url err=${t.message}")
            null
        }
    }

    private fun urlEncode(s: String): String = URLEncoder.encode(s, "UTF-8")
}
