import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/theme/app_theme.dart';
import 'core/widgets/ambient_bg.dart';
import 'data/models/radio_station.dart';
import 'features/home/home_screen.dart';
import 'features/search/search_screen.dart';
import 'features/favorites/favorites_screen.dart';
import 'features/settings/settings_screen.dart';
import 'features/player/mini_player.dart';
import 'features/player/player_screen.dart';
import 'features/shell/desktop_shell.dart';
import 'providers/audio_player_provider.dart';

final navigationIndexProvider = StateProvider<int>((ref) => 0);

const double kDesktopBreakpoint = 960;

/// Play a station and route to the appropriate now-playing UI.
///
/// - Desktop layout (width >= kDesktopBreakpoint): switches the sidebar
///   tab to Now Playing. The persistent player bar stays visible and the
///   user never leaves the shell.
/// - Mobile layout: pushes the full-screen PlayerScreen route.
///
/// Every station-tap in a list should go through this function — bypassing
/// it with a raw Navigator.push results in a modal-feeling PlayerScreen on
/// top of the desktop shell, which feels wrong (you'd have to dismiss it
/// to get back to the sidebar, even though the player bar is there too).
void playStationFromList({
  required WidgetRef ref,
  required BuildContext context,
  required RadioStation station,
}) {
  ref.read(radioPlayerControllerProvider.notifier).playStation(station);
  final isDesktopLayout =
      MediaQuery.of(context).size.width >= kDesktopBreakpoint;
  if (isDesktopLayout) {
    ref.read(desktopNavProvider.notifier).state = DesktopNav.nowPlaying;
  } else {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => PlayerScreen(station: station)),
    );
  }
}

class JustRadioApp extends StatelessWidget {
  const JustRadioApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'JustRadio',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark(),
      darkTheme: AppTheme.dark(),
      themeMode: ThemeMode.dark,
      home: CallbackShortcuts(
        // Diagnostic keybinding: ⌘⇧R forces a full widget reassemble.
        // Use this when the UI becomes un-clickable without a window resize —
        // if this fixes it, the bug is a Flutter hit-test invalidation (a
        // known class of issues on macOS); if it doesn't, something deeper
        // in the engine or platform view is wrong. Ships in all builds
        // because the issue has only been seen in release so far.
        bindings: {
          const SingleActivator(
            LogicalKeyboardKey.keyR,
            meta: true,
            shift: true,
          ): () {
            // ignore: avoid_print
            if (kDebugMode) print('[justradio] force-reassemble triggered');
            WidgetsBinding.instance.reassembleApplication();
          },
        },
        child: const Focus(
          autofocus: true,
          skipTraversal: true,
          canRequestFocus: true,
          descendantsAreFocusable: true,
          child: MainNavigationScreen(),
        ),
      ),
    );
  }
}

class MainNavigationScreen extends ConsumerWidget {
  const MainNavigationScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= kDesktopBreakpoint) {
          return const DesktopShell();
        }
        return const _MobileShell();
      },
    );
  }
}

class _MobileShell extends ConsumerWidget {
  const _MobileShell();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentIndex = ref.watch(navigationIndexProvider);
    final currentStation = ref.watch(
      radioPlayerControllerProvider.select((s) => s.currentStation),
    );

    return Scaffold(
      extendBody: true,
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          Positioned.fill(
            child: AmbientBg(station: currentStation),
          ),
          IndexedStack(
            index: currentIndex,
            children: const [
              HomeScreen(),
              SearchScreen(),
              FavoritesScreen(),
              SettingsScreen(),
            ],
          ),
        ],
      ),
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (currentStation != null) const MiniPlayer(),
          ClipRect(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.6),
                  border: Border(
                    top: BorderSide(color: AppColors.border(0.08)),
                  ),
                ),
                child: NavigationBar(
                  backgroundColor: Colors.transparent,
                  surfaceTintColor: Colors.transparent,
                  selectedIndex: currentIndex,
                  onDestinationSelected: (index) {
                    ref.read(navigationIndexProvider.notifier).state = index;
                  },
                  destinations: const [
                    NavigationDestination(
                      icon: Icon(Icons.home_outlined),
                      selectedIcon: Icon(Icons.home),
                      label: 'Home',
                    ),
                    NavigationDestination(
                      icon: Icon(Icons.search_outlined),
                      selectedIcon: Icon(Icons.search),
                      label: 'Search',
                    ),
                    NavigationDestination(
                      icon: Icon(Icons.favorite_outline),
                      selectedIcon: Icon(Icons.favorite),
                      label: 'Favorites',
                    ),
                    NavigationDestination(
                      icon: Icon(Icons.settings_outlined),
                      selectedIcon: Icon(Icons.settings),
                      label: 'Settings',
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
