import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:window_manager/window_manager.dart';
import 'data/models/genre_photo.dart';
import 'data/models/radio_station.dart';
import 'data/models/recent_play.dart';
import 'data/services/audio_player_service.dart';
import 'providers/favorites_provider.dart';
import 'providers/lastfm_provider.dart';
import 'providers/recent_plays_provider.dart';
import 'providers/unsplash_provider.dart';
import 'app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize window manager for desktop platforms
  if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
    await windowManager.ensureInitialized();
    const windowOptions = WindowOptions(
      minimumSize: Size(1000, 700),
      size: Size(1280, 820),
      center: true,
      title: 'JustRadio',
    );
    await windowManager.waitUntilReadyToShow(windowOptions, () async {
      await windowManager.show();
      await windowManager.focus();
    });
  }

  // Initialize Hive
  await Hive.initFlutter();
  Hive.registerAdapter(RadioStationAdapter());
  Hive.registerAdapter(RecentPlayAdapter());
  Hive.registerAdapter(GenrePhotoAdapter());

  // Initialize audio service
  await AudioPlayerService.init();

  // Create container and initialize services
  final container = ProviderContainer();

  // Initialize favorites
  final favoritesRepo = container.read(favoritesRepositoryProvider);
  await favoritesRepo.init();

  // Initialize recent plays history
  final recentRepo = container.read(recentPlaysRepositoryProvider);
  await recentRepo.init();

  // Initialize app settings + genre photo cache (Unsplash)
  final appSettingsRepo = container.read(appSettingsRepositoryProvider);
  await appSettingsRepo.init();
  final genrePhotosRepo = container.read(genrePhotosRepositoryProvider);
  await genrePhotosRepo.init();

  // Initialize Last.fm service
  final lastfmService = container.read(lastfmAuthServiceProvider);
  await lastfmService.init();

  runApp(
    UncontrolledProviderScope(
      container: container,
      child: const JustRadioApp(),
    ),
  );
}
