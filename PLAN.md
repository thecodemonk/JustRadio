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
