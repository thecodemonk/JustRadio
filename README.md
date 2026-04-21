# JustRadio

A cross-platform streaming radio app built with Flutter. Browse thousands of internet radio stations, save your favorites, and scrobble to Last.fm.

![Platforms](https://img.shields.io/badge/platforms-macOS%20%7C%20Windows%20%7C%20Linux%20%7C%20iOS%20%7C%20Android-blue)
![Flutter](https://img.shields.io/badge/Flutter-3.9+-02569B?logo=flutter)
![License](https://img.shields.io/badge/license-MIT-green)

## Features

### Station Discovery
- **Search** - Find stations by name with instant results
- **Filter by Country** - Browse stations from any country
- **Filter by Genre** - Jazz, Rock, Classical, News, and hundreds more
- **Popular Stations** - Top stations ranked by listener clicks
- **Trending Stations** - Discover what's getting votes

### Playback
- **High-quality streaming** - Powered by media_kit/mpv for reliable playback
- **Now Playing metadata** - See the current artist and track from ICY stream data
- **Volume control** - Logarithmic curve for natural volume perception
- **Mini player** - Persistent controls while browsing

### Favorites
- **Save stations** - Quick access to your preferred stations
- **Offline storage** - Favorites persist locally via Hive

### Last.fm Integration
- **Scrobbling** - Automatically track what you listen to
- **Now Playing** - Show friends what you're tuned into
- **Smart scrobbling** - Only scrobbles after 30 seconds or 50% of track duration

## Screenshots

*Coming soon*

## Getting Started

### Prerequisites
- Flutter SDK 3.9 or higher
- For macOS: Xcode and CocoaPods
- For Windows: Visual Studio with C++ build tools
- For Linux: Required system libraries for media_kit

### Installation

1. Clone the repository:
   ```bash
   git clone https://github.com/thecodemonk/JustRadio.git
   cd JustRadio
   ```

2. Install dependencies:
   ```bash
   flutter pub get
   ```

3. Run the app:
   ```bash
   # macOS
   flutter run -d macos

   # Windows
   flutter run -d windows

   # Linux
   flutter run -d linux

   # iOS
   flutter run -d ios

   # Android
   flutter run -d android
   ```

### macOS signing (one-time setup)

The app stores Last.fm session keys in the Keychain via `flutter_secure_storage`, which requires the `keychain-access-groups` entitlement. That entitlement requires a real development certificate — ad-hoc signing (`CODE_SIGN_IDENTITY = "-"`, the Flutter default) will fail with:

```
error: "Runner" has entitlements that require signing with a development certificate.
```

To fix, open `macos/Runner.xcworkspace` in Xcode, select the **Runner** target → **Signing & Capabilities**, check **Automatically manage signing**, and pick your team (a free "Personal Team" from your Apple ID works). Do this once; subsequent `flutter run` / `flutter build macos` calls will succeed. The change is stored in user-local Xcode preferences and won't leak into version control.

### Linux secure storage

On Linux, `flutter_secure_storage` uses libsecret. At runtime it needs:
- `libsecret-1-0`
- A running keyring daemon (`gnome-keyring-daemon` on GNOME, `kwalletd` on KDE)

Most desktop installs have this by default. Headless environments do not.

### Building for Release

```bash
# macOS
flutter build macos

# Windows
flutter build windows

# Linux
flutter build linux
```

## Architecture

### Tech Stack
- **Framework**: Flutter/Dart
- **State Management**: Riverpod
- **Audio**: media_kit (mpv-based for ICY metadata support)
- **Storage**: Hive (local NoSQL database)
- **HTTP**: Dio
- **Desktop Windows**: window_manager

### Project Structure
```
lib/
├── core/           # Constants, theme, utilities
├── data/
│   ├── models/     # RadioStation, NowPlaying
│   ├── repositories/   # Data access layer
│   └── services/   # Audio player, Last.fm auth
├── features/       # UI screens
│   ├── home/       # Popular & Trending tabs
│   ├── search/     # Search with filters
│   ├── favorites/  # Saved stations
│   ├── settings/   # App settings
│   └── player/     # Player & mini player
└── providers/      # Riverpod state management
```

## Data Sources

### Radio Browser API
Station data provided by [Radio Browser](https://www.radio-browser.info/), a community-driven database of internet radio stations.

### Last.fm
Scrobbling powered by [Last.fm API](https://www.last.fm/api).

## Security notes

### Last.fm shared secret

JustRadio ships with a Last.fm API key and shared secret compiled into the app (`lib/core/constants/lastfm_config.dart`, gitignored). Last.fm's documentation states the shared secret "should not be shared with anyone," but any client-side Flutter binary can be decompiled and the string extracted. For a personal/self-hosted build this is an accepted trade-off; for a distributed release you should proxy signed requests through a small server you control and remove the secret from the client.

### Credential storage

Last.fm session keys and the user-supplied Unsplash access key are stored in the OS-native secure store via `flutter_secure_storage`:

- **macOS / iOS**: Keychain (macOS requires the `keychain-access-groups` entitlement — already configured in this repo)
- **Windows**: DPAPI
- **Linux**: libsecret (requires `gnome-keyring` / `kwallet` at runtime)
- **Android**: EncryptedSharedPreferences backed by the Android Keystore

Earlier builds stored these values in a plaintext Hive box. The app migrates those values to secure storage automatically on first launch and scrubs the Hive keys.

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Acknowledgments

- [Radio Browser](https://www.radio-browser.info/) for the comprehensive radio station database
- [Last.fm](https://www.last.fm/) for the scrobbling API
- [media_kit](https://github.com/media-kit/media-kit) for robust audio playback
