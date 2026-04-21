# JustRadio - Claude Context

## Overview
JustRadio is a cross-platform streaming radio app built with Flutter. It allows users to browse, search, and play internet radio stations.

## Tech Stack
- **Framework**: Flutter (Dart)
- **State Management**: Riverpod
- **Audio Playback**: media_kit (uses mpv under the hood for better ICY metadata/streaming support)
- **Local Storage**: Hive (favorites, recent plays, genre photo cache)
- **Secure Storage**: flutter_secure_storage (Last.fm session key, username, Unsplash access key) — keyed via `SecureSecretsService`. Migrated out of Hive on first launch; requires the `keychain-access-groups` entitlement on macOS.
- **HTTP Client**: Dio
- **Window Management**: window_manager (desktop platforms)

## Key Architecture Decisions

### Audio Player
- Uses `media_kit` instead of `just_audio` for better ICY metadata support from streaming radio
- The `AudioPlayerService` handles playback and metadata extraction from streams
- Volume control uses a **logarithmic curve** (`log(1 + linear * 9) / log(10)`) for perceptually linear volume - this compensates for human hearing perception

### Desktop Window
- Minimum window size: 1000x700 (above the 960 desktop breakpoint, so desktop shell always renders on desktop platforms)
- Default window size: 1280x820 (matches design spec)
- Configured via `window_manager` in `main.dart` for cross-platform support
- Compact/portrait layout is phone-only; desktop always gets the sidebar shell

### State Management
- Uses Riverpod providers throughout
- `radioPlayerControllerProvider` - main playback state
- `volumeProvider` - volume control (stores linear 0-1 value, converted to logarithmic in service)
- `favoritesProvider` - favorite stations persistence

## Project Structure
```
lib/
  app.dart                 # App widget and theme
  main.dart                # Entry point, initialization
  data/
    models/                # Data models (RadioStation, NowPlaying)
    services/              # Services (AudioPlayerService, API clients)
  features/
    player/                # Player screen UI
    ...                    # Other feature screens
  providers/               # Riverpod providers
```

## Running
```bash
flutter pub get
flutter run -d macos    # or windows/linux
```
