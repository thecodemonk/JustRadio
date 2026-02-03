import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:window_manager/window_manager.dart';
import 'data/models/radio_station.dart';
import 'data/services/audio_player_service.dart';
import 'providers/favorites_provider.dart';
import 'providers/lastfm_provider.dart';
import 'app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize window manager for desktop platforms
  if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
    await windowManager.ensureInitialized();
    const windowOptions = WindowOptions(
      minimumSize: Size(400, 700),
      size: Size(450, 800),
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

  // Initialize audio service
  await AudioPlayerService.init();

  // Create container and initialize services
  final container = ProviderContainer();

  // Initialize favorites
  final favoritesRepo = container.read(favoritesRepositoryProvider);
  await favoritesRepo.init();

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
