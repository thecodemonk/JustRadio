import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/theme/app_theme.dart';
import 'core/widgets/ambient_bg.dart';
import 'features/home/home_screen.dart';
import 'features/search/search_screen.dart';
import 'features/favorites/favorites_screen.dart';
import 'features/settings/settings_screen.dart';
import 'features/player/mini_player.dart';
import 'features/shell/desktop_shell.dart';
import 'providers/audio_player_provider.dart';

final navigationIndexProvider = StateProvider<int>((ref) => 0);

const double kDesktopBreakpoint = 960;

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
      home: const MainNavigationScreen(),
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
