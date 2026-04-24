import 'dart:io';
import 'package:flutter/foundation.dart' show debugPrint, kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:window_manager/window_manager.dart';
import 'data/models/album_art.dart';
import 'data/models/genre_photo.dart';
import 'data/models/radio_station.dart';
import 'data/models/recent_play.dart';
import 'core/constants/lastfm_config.dart';
import 'data/services/audio_player_service.dart';
import 'providers/album_art_provider.dart';
import 'providers/audio_player_provider.dart';
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
  Hive.registerAdapter(AlbumArtAdapter());

  // Initialize audio service — media_kit only where the native bridge
  // isn't wired. That's Windows and Linux; Apple platforms and Android all
  // use native bridges. Initializing media_kit where it isn't used wastes
  // memory and (on Android) logs a noisy PathNotFoundException.
  final usesMediaKit = !(Platform.isAndroid ||
      Platform.isIOS ||
      Platform.isMacOS);
  if (usesMediaKit) {
    await AudioPlayerService.init();
  }

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

  // Album art cache — populated by AlbumArtService on (artist, title) lookup.
  final albumArtRepo = container.read(albumArtRepositoryProvider);
  await albumArtRepo.init();

  // One-shot purge of cached Last.fm album art URLs — the art provider
  // chain dropped Last.fm because its coverage is spotty and several
  // image URLs have been deprecated. Entries re-resolve on next play.
  if (!appSettingsRepo.isMigrationDone('album_art_lastfm_purged_v1')) {
    final removed = await albumArtRepo.purgeLastfmEntries();
    await appSettingsRepo.markMigrationDone('album_art_lastfm_purged_v1');
    if (kDebugMode) {
      debugPrint('[albumart] purged $removed lastfm cache entries');
    }
  }

  // One-shot purge of MusicBrainz-sourced entries — early MB+CAA lookups
  // could cache compilation-album covers (e.g. "Rolling Stone Rare Trax
  // Vol X" for an electronic single). The chain now skips compilations;
  // clear so affected entries re-resolve.
  if (!appSettingsRepo
      .isMigrationDone('album_art_musicbrainz_compilation_purge_v1')) {
    final removed = await albumArtRepo.purgeMusicbrainzEntries();
    await appSettingsRepo
        .markMigrationDone('album_art_musicbrainz_compilation_purge_v1');
    if (kDebugMode) {
      debugPrint('[albumart] purged $removed musicbrainz cache entries');
    }
  }

  // One-shot purge of every cached entry — several chain-level fixes
  // have gone in (artist/title swap acceptance, iTunes compilation
  // filter) and we want every track to re-resolve with the latest
  // matcher. Cheap: the Dart Hive cache is the only place; the network
  // round-trip returns on next play.
  if (!appSettingsRepo
      .isMigrationDone('album_art_full_purge_v4_mb_title_only')) {
    final removed = await albumArtRepo.purgeAll();
    await appSettingsRepo
        .markMigrationDone('album_art_full_purge_v4_mb_title_only');
    if (kDebugMode) {
      debugPrint(
          '[albumart] purged $removed cache entries (post compilation-filter upgrade)');
    }
  }

  // Initialize Last.fm service
  final lastfmService = container.read(lastfmAuthServiceProvider);
  await lastfmService.init();

  // Mirror favorites + recent plays into the native media library store so
  // Android Auto / CarPlay can browse them when the Flutter UI isn't
  // running. Fire once on startup and re-sync on every change.
  if (Platform.isAndroid || Platform.isIOS) {
    final audioService = container.read(audioPlayerServiceProvider);
    audioService.syncFavorites(container.read(favoritesProvider));
    audioService.syncRecent(
      container.read(recentPlaysProvider).map((r) => r.station).toList(),
    );
    container.listen<List<RadioStation>>(
      favoritesProvider,
      (_, next) => audioService.syncFavorites(next),
    );
    container.listen<List<RecentPlay>>(
      recentPlaysProvider,
      (_, next) => audioService.syncRecent(next.map((r) => r.station).toList()),
    );

    // Native code (Android Auto custom love button, CarPlay likeCommand)
    // needs the Last.fm credentials to sign its own requests when Flutter
    // isn't running. The API key + secret ship in the app bundle regardless,
    // so pushing them to SharedPreferences/UserDefaults is just the "one
    // place native code reads from" convention. Session key + username are
    // per-user and follow auth state.
    audioService.syncLastfmConfig(
      apiKey: LastfmConfig.apiKey,
      apiSecret: LastfmConfig.sharedSecret,
    );
    audioService.syncLastfmSession(
      sessionKey: lastfmService.sessionKey,
      username: lastfmService.username,
    );
    container.listen(
      lastfmStateProvider,
      (prev, next) {
        if (prev?.isAuthenticated == next.isAuthenticated &&
            prev?.username == next.username) {
          return;
        }
        audioService.syncLastfmSession(
          sessionKey: lastfmService.sessionKey,
          username: lastfmService.username,
        );
      },
    );
  }

  runApp(
    UncontrolledProviderScope(
      container: container,
      child: const JustRadioApp(),
    ),
  );
}
