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

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Acknowledgments

- [Radio Browser](https://www.radio-browser.info/) for the comprehensive radio station database
- [Last.fm](https://www.last.fm/) for the scrobbling API
- [media_kit](https://github.com/media-kit/media-kit) for robust audio playback
