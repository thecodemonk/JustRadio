# JustRadio — Roadmap (post-Phase 1)

Phase 1 (native audio bridge on iOS + Android with unified ICY and HLS metadata) is complete. The following phases are the mobile-auto integrations and a bandwidth refinement.

## Phase 2 — Android Auto

**Goal:** the user plugs their phone into a car or starts Android Auto on a head unit, sees JustRadio in the app launcher, can browse favorites/recent/genres and play stations without touching their phone.

**Scope:**

1. Convert `AudioPlayerPlugin.kt` from a method-channel-only plugin into something that drives a `MediaSessionCompat`. The ExoPlayer instance we already have feeds the session's `PlaybackStateCompat` and `MediaMetadataCompat`. Android Auto reads both.
2. Add a `MediaBrowserServiceCompat` subclass (we already have the manifest entry from the `audio_service` leftover — `<service android:name="com.ryanheise.audioservice.AudioService" ...>`). Replace that with our own service. Implement:
   - `onGetRoot(...)` — return a root media ID.
   - `onLoadChildren(parentMediaId, result)` — return browsable/playable MediaItems:
     - Root → three children: "Favorites", "Recently Played", "Browse by Genre"
     - "Favorites" → list of favorited stations as playable items
     - "Recently Played" → list of recent plays
     - "Browse by Genre" → list of genres, each expanding into stations
3. Wire `onPlayFromMediaId` on the session to trigger playStation via our existing plugin path.
4. Update `NowPlaying` events from the native side to also update `MediaMetadataCompat.METADATA_KEY_TITLE / ARTIST / ART_URI` so the car dashboard shows track info.
5. Required manifest changes:
   - Replace the audio_service entries with our own service declaration.
   - Add `automotive_app_desc.xml` and the `com.google.android.gms.car.application` meta-data entry so Android Auto lists the app.
6. Test matrix: Android Auto Desktop Head Unit (DHU) via USB debugging, then physical Android Auto head unit if available.

**Files touched (new + modified):**
- `android/app/src/main/kotlin/com/justradio/just_radio/AudioPlayerPlugin.kt` — attach MediaSession
- `android/app/src/main/kotlin/com/justradio/just_radio/MediaBrowserService.kt` — new
- `android/app/src/main/res/xml/automotive_app_desc.xml` — new
- `android/app/src/main/AndroidManifest.xml` — service + meta-data
- `android/app/build.gradle.kts` — add `androidx.media3:media3-session:1.10.0`

**Estimate:** 2–3 days.

**Risks:** Browsable hierarchy state (favorites/recent) lives in Hive, read from Dart. Easiest pattern is to expose those via method channels that the Kotlin MediaBrowserService calls *back* into Dart to fetch. Alternative: mirror the data natively via a small Room DB or shared prefs. Start with the callback approach.

## Phase 3 — CarPlay screens (scaffolding only)

**Goal:** build out the CarPlay UI in code so it's ready to ship once an entitlement + dev account are obtained. No entitlement submission, no on-device testing with a CarPlay unit yet. Desktop and phone iOS builds must continue working with the CarPlay code present but dormant.

**Scope:**

1. Add a `CarPlaySceneDelegate.swift` that conforms to `CPTemplateApplicationSceneDelegate`. Wire it in `Info.plist` under `UIApplicationSceneManifest` as an additional scene configuration guarded on `carplay-audio` session role.
2. Build the template tree:
   - `CPListTemplate` for "Favorites", "Recently Played", "Browse by Genre" as root tabs (`CPTabBarTemplate`).
   - `CPListTemplate` for genre drill-down.
   - `CPNowPlayingTemplate` pushed when a station is selected, with custom buttons for favorite toggle.
3. Connect templates to the existing `AudioPlayerPlugin` — the same AVPlayer instance that plays for the phone UI also plays for CarPlay. No double playback.
4. Hook `MPNowPlayingInfoCenter` + `MPRemoteCommandCenter` for lock-screen / control-center / CarPlay playback metadata, which is valuable even outside CarPlay.
5. Read favorites/recent/genres from the Flutter/Dart side via a method channel call (symmetric to the Android Auto approach).
6. **Skip for now:** the `com.apple.developer.playable-content` entitlement, Apple's CarPlay Audio entitlement request, on-device CarPlay testing. Once the user has an Apple Dev account and requests the entitlement (weeks of lead time), the scaffolding can be wired up without further code.

**Files touched (new + modified):**
- `ios/Runner/CarPlaySceneDelegate.swift` — new
- `ios/Runner/Info.plist` — `UIApplicationSceneManifest` entry
- `ios/Runner/AudioPlayerPlugin.swift` — expose hooks for the scene delegate
- New Swift files for list + now-playing template builders
- `ios/Runner.xcodeproj/project.pbxproj` — register new Swift files

**Estimate:** 3–5 days of code.

**Note on signing:** without the `com.apple.developer.playable-content` entitlement, the CarPlay session will not attach at runtime, but the code will still compile and the phone app will run normally. Safe to land in main.

## Phase 4 — Bandwidth optimization for the iOS ICY side-channel reader

**Goal:** stop doubling cellular data for ICY streams on iOS. Current behavior: `IcyMetadataReader` holds its own HTTP connection open for the duration of playback, reading the same bytes AVPlayer is reading.

**Approach:**

1. After a StreamTitle has been stable for N seconds (30? 60?) — close the reader's connection.
2. Reopen periodically (every ~60s? Or time-based: every 3 minutes to catch new tracks) to pick up the next track change.
3. Tune the interval to balance "user sees the new track promptly" against "extra bytes transferred."

**Alternative (more work, one-connection-only solution):** rewrite the reader as an `AVAssetResourceLoaderDelegate` that proxies the single HTTP connection AVPlayer uses — strips ICY metadata blocks before handing audio bytes to AVPlayer. Cleaner bandwidth but non-trivial to get buffering/backpressure right. Would also fully replace the side-channel pattern. Defer unless the periodic reopen approach proves insufficient.

**Files touched:**
- `ios/Runner/IcyMetadataReader.swift` — add a `close-after-stable-N-seconds` mode
- `ios/Runner/AudioPlayerPlugin.swift` — poll restart

**Estimate:** half a day for the periodic approach, ~2 days for the resource-loader rewrite.

## Phase 5 — Album art retrieval and display

**Goal:** once we have `(artist, title)` for the currently playing track, fetch album art and show it in place of / alongside the station logo on the player screen, the mini-player, and CarPlay / Android Auto now-playing surfaces.

**Investigation first** — the right source isn't obvious; start by picking one:

- **Last.fm `track.getInfo`** — already authenticated (we have an API key + session key for scrobbling). Returns `track.album.image` in small/medium/large/extralarge/mega sizes. Free, no extra auth. Preferred — we're already Last.fm-flavored.
- **iTunes Search API** (`itunes.apple.com/search?term=...`) — no auth, no rate-limit in practice, very high hit rate. Good fallback.
- **MusicBrainz + Cover Art Archive** — free but slow, rate-limited to 1 req/sec, stricter user-agent requirement.
- **Deezer Public API** — no auth, good catalog, permissive CORS.

Last.fm first, iTunes as a fallback when Last.fm returns no image (common for obscure tracks).

**Scope:**

1. New `AlbumArtService` in `lib/data/services/` with `Future<AlbumArt?> lookup(artist, title)`. Tries Last.fm, falls back to iTunes, returns the largest available image URL + a credit string.
2. New Hive-backed `AlbumArtRepository` mirroring the existing `genre_photos_repository.dart` pattern. Cache by `(artist, title)` → `AlbumArt`. TTL: practically forever — tracks don't change art often, and we want offline robustness. Invalidate only on user-triggered refresh.
3. Riverpod provider `albumArtProvider.family((artist, title))` returning `AsyncValue<AlbumArt?>`. Uses repo-first, service-on-miss pattern (same shape as `genrePhotoProvider`).
4. Wire into `RadioPlayerController` — whenever a new `NowPlaying` arrives with non-empty artist + title, trigger the lookup; store the resulting URL on the state.
5. UI surfaces:
   - `player_screen.dart` — swap `StationArt` for album art when available, fade in; show station logo as the fallback.
   - `mini_player.dart` — same, smaller.
   - iOS `MPNowPlayingInfoCenter` (part of Phase 3 groundwork) reads `state.albumArtUrl` and downloads + sets `MPMediaItemPropertyArtwork`.
   - Android MediaSession metadata (`ART_URI` from Phase 2) gets populated from the same source — Android Auto picks it up automatically.
6. Throttle to avoid hammering Last.fm: only one in-flight lookup per `(artist, title)` key; debounce 500ms after a metadata change to coalesce rapid updates.

**Edge cases worth thinking about:**
- Station IDs (e.g., `SomaFM: Groove Salad` from the TRSN frame) arriving as artist — filter these out before lookup.
- Radio shows / DJ sets where "artist - title" doesn't map to a real track. Service should degrade silently; UI falls back to station logo.
- Copyright / attribution — Last.fm requires linking back to their page for images; iTunes requires the badge. Add a small credits section to the existing settings screen.
- HLS streams already give us `WXXX` URLs that point to the station's logo — **not** album art, but a second fallback for stations we can't look up.

**Files touched (new + modified):**
- `lib/data/services/album_art_service.dart` — new
- `lib/data/repositories/album_art_repository.dart` — new
- `lib/data/models/album_art.dart` — new
- `lib/providers/album_art_provider.dart` — new (or fold into an existing provider file)
- `lib/providers/audio_player_provider.dart` — trigger lookup on track change
- `lib/features/player/player_screen.dart` — render album art over station art
- `lib/features/player/mini_player.dart` — same
- `ios/Runner/AudioPlayerPlugin.swift` — `MPNowPlayingInfoCenter` artwork (ties into Phase 3)
- `android/...MediaBrowserService.kt` — `METADATA_KEY_ART_URI` (ties into Phase 2)

**Estimate:** 1 day for Last.fm-only with caching + UI. Add half a day for iTunes fallback and one more half-day for the Now-Playing-Center integrations.
