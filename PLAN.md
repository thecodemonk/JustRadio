# JustRadio — Roadmap

## Completed

- **Phase 1 — Native audio bridge (iOS + Android).** Unified ICY + HLS metadata surfaces via ExoPlayer (Android) and AVPlayer (iOS).
- **Phase 2 — Android Auto.** `PlaybackService` (media3 `MediaLibraryService`) owns ExoPlayer and the session. Browse tree = Favorites / Recently Played / Browse by Genre, populated from SharedPreferences that Dart writes on every state change (chosen over the callback-into-Dart approach because AA can start the service cold without the Flutter activity running). `AudioPlayerPlugin.kt` is a thin `MediaController` client now. Manifest declares the service with both `androidx.media3.session.MediaSessionService` and `android.media.browse.MediaBrowserService` intent filters; `automotive_app_desc.xml` registers the app as a media provider. **Not yet validated against the Android Auto Desktop Head Unit** — code compiles, real-device pass is the remaining step.
- **Phase 3 — CarPlay scaffolding (dormant).** `CarPlaySceneDelegate.swift` builds `CPTabBarTemplate` with Favorites / Recent / Genres tabs, drill-down to `CPListTemplate`, and `CPNowPlayingTemplate` on play. Reads the library from `UserDefaults` (iOS mirror of Android's SharedPreferences layout). `MPNowPlayingInfoCenter` + `MPRemoteCommandCenter` wired. **Activates only once Apple grants `com.apple.developer.carplay-audio`** (weeks-long review). Scaffolding compiles cleanly with the entitlement absent. Note: the plan originally referenced `com.apple.developer.playable-content` — that's the legacy API; the modern template-based CarPlay Audio entitlement is the right one.
- **Phase 4 — iOS / macOS ICY bandwidth optimization.** Final architecture is a **local HTTP proxy** (`IcyLocalHttpProxy.swift`) rather than a side-channel reader. Listens on `127.0.0.1:<auto-port>` via `NWListener`, opens a single HTTPS upstream, strips ICY metadata blocks from the byte stream, and serves clean audio to AVPlayer on a `http://127.0.0.1/…` URL. Earlier attempts at `AVAssetResourceLoaderDelegate` with custom schemes worked on iOS but hit `CoreMediaErrorDomain -1002` on macOS — CoreMedia has internal paths that bypass the delegate and can't resolve non-http(s) schemes. The local-proxy pattern sidesteps that entirely. Single connection to the stream host is preserved; metadata emission is deferred by AVPlayer's buffered-ahead duration so UI changes land with the audio.
- **Phase 5 — Album art retrieval.** `AlbumArtService` tries Last.fm `track.getInfo` first, falls back to iTunes Search. Hive-backed cache (hits only — misses retry next time). `albumArtProvider.family((artist, title))`. `RadioPlayerController` triggers lookup on `NowPlaying` change (500ms debounce, dedupe, station-ID filter). UI: `NowPlayingArt` overlays album art on the station logo via `AnimatedSwitcher` crossfade; wired into player screen, mini player, and both desktop-shell surfaces (Now Playing tab + bottom player bar). Native: `setAlbumArt` method channel updates `MPNowPlayingInfoCenter` artwork (iOS/macOS) and `MediaMetadata.artworkUri` via `MediaController.replaceMediaItem` (Android).

## Also delivered along the way

- **macOS engine migration** — macOS now runs the same native AVPlayer bridge as iOS (shared Swift files referenced from both Xcode projects). Gets HLS ID3 metadata natively, gets the ICY proxy pattern, gets `MPNowPlayingInfoCenter` / `MPRemoteCommandCenter`. mpv/media_kit stays as the engine for Windows and Linux only.
- **macOS signing setup** — `LocalSigning.xcconfig` is gitignored; `.example` template committed with the cert-OU-lookup instructions. Team ID lives local, never hits the repo (see memory).
- **Volume** — cube-ish audio taper (`amplitude = linear^2.5`) for perceptually linear slider response. Persisted across app restarts via `app_settings` Hive box. Android `lastVolume` catches up newly-connected `MediaController`s; Apple's Swift plugin already had equivalent.
- **Player UX** — volume is a compact popover with vertical slider (auto-hide after idle). Desktop station taps switch to the Now Playing tab instead of pushing a full-page player modal.
- **Diagnostic** — `⌘⇧R` force-reassembles the widget tree for when macOS hit-test regions stale.

## Known gaps (accepted)

- **Windows/Linux HLS ID3 metadata** — mpv doesn't parse it (mpv#14756). No immediate fix.
- **Windows/Linux OS media integration** — no lock-screen metadata or media-key handling. SMTC (Windows) and MPRIS (Linux) would each be a separate plugin project.
- **Android Auto real-device validation** — code complete; needs DHU or physical head-unit test pass.
- **CarPlay activation** — waiting on entitlement grant from Apple.

## Open items

- **Drop `media_kit_libs_macos_video`** once the native macOS engine has soaked — saves ~50MB in the app bundle.
- **SMTC / MPRIS** for Windows + Linux lock-screen and media-key integration (pick-up when a user asks).
