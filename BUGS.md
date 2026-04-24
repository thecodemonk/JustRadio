# JustRadio — Open Bugs

Snapshot before context compact. All Phase 2–5 work is committed; these are follow-ups discovered during Android Auto DHU testing.

## 1. Heart icon on Now Playing is station-scoped, should be track-scoped

**Symptom:** On the desktop Now Playing and the PlayerScreen, the main heart icon reflects whether the current *station* is favorited. Every song looks "favorited" if the station is.

**Intent:** On the Now Playing surfaces, the heart should be the Last.fm "love this track" toggle (per-song). Station-favorite (heart-add-to-favorites) stays available elsewhere — sidebar pinned list, station list tiles, etc.

**Files likely:**
- `lib/features/player/player_screen.dart` — AppBar actions: currently `isFavorite` + `favoritesProvider.toggle(station)`. Switch to love-track via `lastfmAuthServiceProvider.repository.loveTrack / unloveTrack` + `isTrackLoved` for initial state.
- `lib/features/shell/desktop_shell.dart` — `_DesktopPlayerBar` has the same heart IconButton wired to `favoritesProvider.toggle`. Same fix.
- `lib/features/player/mini_player.dart` — check if it has a heart; if so, same treatment.

PlayerScreen already has `_toggleLove` + `_syncLovedState` for the **secondary** "Love" label under track info. Hoist that logic into the top-right heart button. Keep the station-favorite icon somewhere non-primary (maybe in the sidebar right panel? Or the breadcrumb area?).

---

## 2. Mobile Now Playing overflows viewport — controls below the fold

**Symptom:** On phones, you have to scroll down to reach play/pause. Should auto-fit.

**Files:**
- `lib/features/player/player_screen.dart` — body is a `Stack` → `SafeArea` → `SingleChildScrollView`. The scroll view lets content be arbitrarily tall. On small phones, the 260pt `NowPlayingArt` + breadcrumb + track meta + waveform panel + controls = overflow.

**Fix approach:** replace `SingleChildScrollView` with `LayoutBuilder`-driven sizing: shrink art (maybe 200pt on short screens, 260pt otherwise), use `Expanded`/flex to push controls to a fixed bottom region. Controls and volume should be anchored; the art + metadata gets remaining space and shrinks if needed.

---

## 3. Flutter state doesn't sync when PlaybackService is already playing

**Symptom:** Android Auto starts a station. User later opens JustRadio on the phone. App shows no playing state — no `currentStation`, no `nowPlaying`, mini-player hidden.

**Cause:** Dart's `RadioPlayerController` populates state from stream events (plugin event channel). When the plugin attaches but the session already has a current media item, no fresh events fire — only future changes are observed. So Dart never learns what's already playing.

**Fix approach (Android):** in `AudioPlayerPlugin.kt`, in the `MediaController` connect listener, check `controller.currentMediaItem`. If non-null AND `mediaId` starts with `STATION_PREFIX`, look up the full station JSON from SharedPreferences (same keys `PlaybackService` reads for AA browse — `justradio_library/favorites_json`, `recent_json`, `genre_stations.*`) and emit a `"syncState"` event with the station + current `title`/`artist`/`albumUri` + `isPlaying`. Also emit a playback-state event so `isPlaying` flips immediately.

**Dart side:** `NativeAudioPlayerService._handleEvent` gets a new `case "syncState":` that builds a `RadioStation` and pushes it through `_stationController`, plus pushes `NowPlaying` through `_nowPlayingController`.

**iOS equivalent:** less urgent — CarPlay is dormant so the "Dart opens while something else started playback" path isn't exercised yet. Same fix pattern will apply when CarPlay activates.

---

## 4. Album art misses fall through both Last.fm and iTunes

**Symptom:** Many tracks have no album art even though image exists on other services. User says "we were supposed to get it definitively from somewhere."

**Current state:** `lib/data/services/album_art_service.dart` tries `_lookupLastfm` → `_lookupItunes`. Both have diagnostic prints (`[albumart/lastfm] …`, `[albumart/itunes] …`) gated on `kDebugMode`.

**Investigate first:** verify iTunes fallback is actually firing on misses. Look for `[albumart/itunes] hit url=…` vs `[albumart/itunes] no results for …` in debug console when a Last.fm-miss track plays.

**Extend chain:**
1. Add **Deezer Search** (`https://api.deezer.com/search?q=<artist> <title>`, no auth). Field: `album.cover_xl` or `cover_big`. Permissive CORS, fast.
2. Add **MusicBrainz + Cover Art Archive**:
   - MusicBrainz lookup: `https://musicbrainz.org/ws/2/recording/?query=artist:<artist> AND recording:<title>&fmt=json&limit=1`
   - Grab `releases[0].id` (release MBID).
   - Cover Art Archive: `https://coverartarchive.org/release/<mbid>/front-500` (redirects to image URL).
   - Rate limit: 1 req/sec, so this should be last in the chain.
   - Set `User-Agent: JustRadio/1.0 ( contact@somewhere )` — CAA requires it.

**Source ordering:** Last.fm (has auth, good hit rate) → iTunes (fast, high hit rate) → Deezer (fast, moderate hit rate) → MusicBrainz+CAA (slow, comprehensive).

**Files:**
- `lib/data/services/album_art_service.dart` — add `_lookupDeezer` and `_lookupMusicBrainz`, chain in `lookup()`.

---

## 5. Android Auto album art requires Flutter to be running

**Symptom:** User tested Android Auto. Album art only appears if JustRadio is also open on the phone. Once closed, album art stops updating (but title/artist still work because those come from ExoPlayer's `onMetadata` path in Kotlin).

**Cause:** Album art lookup lives in Dart (`RadioPlayerController._runAlbumArtLookup`). When AA starts the `PlaybackService` directly (no Flutter activity), no Dart code runs.

**Fix:** Port the lookup chain to Kotlin in `PlaybackService.kt`. On each track change (from `applyIcyStreamTitleToMediaItem` / `updateMediaItemTrackInfo`), kick off a coroutine or background thread that hits Last.fm → iTunes → Deezer → CAA. On success, apply via `updateMediaItemTrackInfo` (extend it with an `artworkUri` param) or a separate `applyAlbumArt` helper.

**Coordination with Dart:** when Flutter *is* running and Dart also fires its lookup, both reach the same API. Minor duplicate HTTP. Acceptable; both eventually call `replaceMediaItem` with the same URL (idempotent write — the no-change guard short-circuits).

**API key:** Last.fm needs an API key. Currently only in Dart (`LastfmConfig.apiKey`). Option (a): hardcode it in Kotlin too (ugly). Option (b): Dart writes it to SharedPreferences on startup and Kotlin reads from there. Go with (b) — it's cleaner and the key ships with the APK regardless.

**Files:**
- `android/app/src/main/kotlin/com/justradio/just_radio/PlaybackService.kt` — new `AlbumArtLookup.kt` or inline helper
- Maybe `lib/main.dart` — add `syncLastfmApiKey` push at startup

---

## Status of things NOT in this list (accepted / done)

- Phases 2–5 shipped (commit `270a8db`).
- macOS native engine migration (`bc64169`).
- Volume persistence, cube taper, `⌘⇧R` reassemble, desktop nav unification (`9bde142`).
- Rename `NativeMobileAudioPlayerService` → `NativeAudioPlayerService` (`e5f4b7c`).
- `media_kit_libs_{macos,ios,android}_video` dropped from pubspec (`d025631`).
- Android Auto metadata (ICY + HLS ID3) now syncs to MediaSession via `updateMediaItemTrackInfo` (uncommitted — will commit with bug #5 fix).
- Android Auto audio focus / YouTube Music pauses correctly (uncommitted — will commit with bug #5 fix).
- CarPlay dormant pending entitlement; Android Auto DHU test-passed for metadata + audio focus; needs test pass for album art after #5.

## Uncommitted state at time of writing

The recent Android metadata fixes (`applyIcyStreamTitleToMediaItem`, `updateMediaItemTrackInfo`, audio-focus attributes, `setAlbumArt` logging) are NOT yet committed. Debug `Log.d` statements in `PlaybackService.kt` and `AudioPlayerPlugin.kt` can be removed or gated before commit. Same for the `[albumart/lastfm]` / `[albumart/itunes]` prints in `album_art_service.dart` — if we want to keep them, gate behind a `verboseLogging` constant like the iOS proxy does.
