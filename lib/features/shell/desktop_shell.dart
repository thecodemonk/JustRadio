import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/ambient_bg.dart';
import '../../core/widgets/sleep_timer_panel.dart';
import '../../core/widgets/station_art.dart';
import '../../core/widgets/waveform.dart';
import '../../data/models/radio_station.dart';
import '../../providers/audio_player_provider.dart';
import '../../providers/favorites_provider.dart';
import '../favorites/favorites_screen.dart';
import '../home/home_screen.dart';
import '../search/search_screen.dart';
import '../settings/settings_screen.dart';

enum DesktopNav { home, nowPlaying, search, favorites, settings }

final desktopNavProvider =
    StateProvider<DesktopNav>((ref) => DesktopNav.home);

class DesktopShell extends ConsumerWidget {
  const DesktopShell({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final nav = ref.watch(desktopNavProvider);
    final station = ref.watch(
      radioPlayerControllerProvider.select((s) => s.currentStation),
    );
    final showPlayerBar = station != null;
    final showRightPanel = station != null;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          Positioned.fill(child: AmbientBg(station: station)),
          Column(
            children: [
              Expanded(
                child: Row(
                  children: [
                    _Sidebar(bottomPadding: showPlayerBar ? 80 : 0),
                    Expanded(
                      child: _MainContent(
                        nav: nav,
                        bottomPadding: showPlayerBar ? 80 : 0,
                      ),
                    ),
                    if (showRightPanel)
                      _RightPanel(
                        station: station,
                        bottomPadding: showPlayerBar ? 80 : 0,
                      ),
                  ],
                ),
              ),
            ],
          ),
          if (showPlayerBar)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: _DesktopPlayerBar(station: station, ref: ref),
            ),
        ],
      ),
    );
  }
}

class _Sidebar extends ConsumerWidget {
  final double bottomPadding;
  const _Sidebar({this.bottomPadding = 0});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final nav = ref.watch(desktopNavProvider);
    final favorites = ref.watch(favoritesProvider);
    final currentStation = ref.watch(
      radioPlayerControllerProvider.select((s) => s.currentStation),
    );

    return Container(
      width: 240,
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.45),
        border: Border(
          right: BorderSide(color: AppColors.border(0.06)),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 52),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 28),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(7),
                  child: Image.asset(
                    'assets/icon/icon.png',
                    width: 32,
                    height: 32,
                    filterQuality: FilterQuality.medium,
                  ),
                ),
                const SizedBox(width: 10),
                Text('Just Radio', style: AppTypography.display(24)),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              children: [
                _NavItem(
                  icon: Icons.home_outlined,
                  activeIcon: Icons.home,
                  label: 'Home',
                  active: nav == DesktopNav.home,
                  onTap: () => ref.read(desktopNavProvider.notifier).state =
                      DesktopNav.home,
                ),
                _NavItem(
                  icon: Icons.album_outlined,
                  activeIcon: Icons.album,
                  label: 'Now Playing',
                  active: nav == DesktopNav.nowPlaying,
                  onTap: () => ref.read(desktopNavProvider.notifier).state =
                      DesktopNav.nowPlaying,
                ),
                _NavItem(
                  icon: Icons.search_outlined,
                  activeIcon: Icons.search,
                  label: 'Search',
                  active: nav == DesktopNav.search,
                  onTap: () => ref.read(desktopNavProvider.notifier).state =
                      DesktopNav.search,
                ),
                _NavItem(
                  icon: Icons.favorite_outline,
                  activeIcon: Icons.favorite,
                  label: 'Favorites',
                  active: nav == DesktopNav.favorites,
                  onTap: () => ref.read(desktopNavProvider.notifier).state =
                      DesktopNav.favorites,
                ),
                if (favorites.isNotEmpty) ...[
                  const SizedBox(height: 24),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                    child: Text(
                      'PINNED STATIONS',
                      style: AppTypography.mono(10,
                          color: AppColors.onBgMuted(0.4),
                          letterSpacing: 1.5,
                          weight: FontWeight.w500),
                    ),
                  ),
                  ...favorites.take(8).map((s) => _PinnedStation(
                        station: s,
                        active:
                            currentStation?.stationuuid == s.stationuuid,
                        onTap: () {
                          ref
                              .read(radioPlayerControllerProvider.notifier)
                              .playStation(s);
                          ref.read(desktopNavProvider.notifier).state =
                              DesktopNav.nowPlaying;
                        },
                      )),
                ],
              ],
            ),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(12, 0, 12, 24 + bottomPadding),
            child: _NavItem(
              icon: Icons.settings_outlined,
              activeIcon: Icons.settings,
              label: 'Settings',
              active: nav == DesktopNav.settings,
              onTap: () => ref.read(desktopNavProvider.notifier).state =
                  DesktopNav.settings,
            ),
          ),
        ],
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  final IconData icon;
  final IconData activeIcon;
  final String label;
  final bool active;
  final VoidCallback onTap;

  const _NavItem({
    required this.icon,
    required this.activeIcon,
    required this.label,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          margin: const EdgeInsets.only(bottom: 2),
          decoration: BoxDecoration(
            color: active ? AppColors.surface(0.06) : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            border: Border(
              left: BorderSide(
                color: active ? AppColors.accent : Colors.transparent,
                width: 2,
              ),
            ),
          ),
          child: Row(
            children: [
              Icon(
                active ? activeIcon : icon,
                size: 16,
                color:
                    active ? AppColors.onBgStrong : AppColors.onBgMuted(0.65),
              ),
              const SizedBox(width: 12),
              Text(
                label,
                style: AppTypography.body(
                  13,
                  color:
                      active ? AppColors.onBgStrong : AppColors.onBgMuted(0.7),
                  weight: active ? FontWeight.w500 : FontWeight.w400,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PinnedStation extends StatelessWidget {
  final RadioStation station;
  final bool active;
  final VoidCallback onTap;
  const _PinnedStation({
    required this.station,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: active ? AppColors.surface(0.04) : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              StationArt(station: station, size: 22, radius: 4),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  station.name,
                  style: AppTypography.body(12,
                      color: active
                          ? AppColors.onBgStrong
                          : AppColors.onBgMuted(0.65)),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (active)
                Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: AppColors.accent,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.accentGlow(0.6),
                        blurRadius: 8,
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MainContent extends StatelessWidget {
  final DesktopNav nav;
  final double bottomPadding;
  const _MainContent({required this.nav, required this.bottomPadding});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: bottomPadding),
      child: IndexedStack(
        index: nav.index,
        children: const [
          HomeScreen(),
          _NowPlayingMain(),
          SearchScreen(),
          FavoritesScreen(),
          SettingsScreen(),
        ],
      ),
    );
  }
}

class _NowPlayingMain extends ConsumerWidget {
  const _NowPlayingMain();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playerState = ref.watch(radioPlayerControllerProvider);
    final station = playerState.currentStation;

    if (station == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.radio_outlined,
                size: 56, color: AppColors.accentGlow(0.5)),
            const SizedBox(height: 14),
            Text('Nothing on air', style: AppTypography.display(28)),
            const SizedBox(height: 8),
            Text('Pick a station to start listening.',
                style: AppTypography.body(14,
                    color: AppColors.onBgMuted(0.55))),
          ],
        ),
      );
    }

    final np = playerState.nowPlaying;
    return Padding(
      padding: const EdgeInsets.fromLTRB(40, 48, 40, 32),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(
                    color: AppColors.live,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                          color: AppColors.live.withValues(alpha: 0.5),
                          blurRadius: 10),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Text('ON AIR · LIVE',
                    style: AppTypography.label(10, letterSpacing: 2)),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              '${station.name}${station.country.isNotEmpty ? ' · ${station.country}' : ''}${station.bitrate > 0 ? ' · ${station.bitrate} kbps' : ''}',
              style: AppTypography.body(13,
                  color: AppColors.onBgMuted(0.7)),
            ),
            const SizedBox(height: 28),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                StationArt(
                  station: station,
                  size: 220,
                  radius: 4,
                  shadow: BoxShadow(
                    color: Colors.black.withValues(alpha: 0.5),
                    blurRadius: 60,
                    offset: const Offset(0, 20),
                  ),
                ),
                const SizedBox(width: 28),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('NOW PLAYING',
                          style: AppTypography.label(11, letterSpacing: 2)
                              .copyWith(
                            color: AppColors.accent,
                            fontWeight: FontWeight.w500,
                          )),
                      const SizedBox(height: 10),
                      Text(
                        np.title.isNotEmpty ? np.title : station.name,
                        style: AppTypography.display(60, height: 1.0),
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (np.artist.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        Text(np.artist,
                            style: AppTypography.body(20,
                                color: AppColors.onBgMuted(0.85),
                                weight: FontWeight.w300)),
                      ],
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 28),
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: AppColors.surface(0.03),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.border(0.06)),
              ),
              child: Column(
                children: [
                  SizedBox(
                    height: 48,
                    child: Waveform(
                      seedKey: station.stationuuid.isEmpty
                          ? station.name
                          : station.stationuuid,
                      bars: 120,
                      height: 48,
                      color: AppColors.accent,
                      progress: playerState.isPlaying ? 1.0 : 0.0,
                      animate: playerState.isPlaying,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          station.bitrate > 0
                              ? '${station.bitrate} KBPS · ${(station.codec.isEmpty ? 'MP3' : station.codec).toUpperCase()} · STEREO'
                              : (station.codec.isEmpty ? 'MP3' : station.codec)
                                  .toUpperCase(),
                          style: AppTypography.mono(10,
                              color: AppColors.accent,
                              letterSpacing: 1.2),
                        ),
                      ),
                      Text('● LIVE',
                          style: AppTypography.mono(10,
                              color: AppColors.live, letterSpacing: 1.2)),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RightPanel extends ConsumerWidget {
  final RadioStation station;
  final double bottomPadding;
  const _RightPanel({required this.station, required this.bottomPadding});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final np = ref.watch(
      radioPlayerControllerProvider.select((s) => s.nowPlaying),
    );

    return Container(
      width: 340,
      padding: EdgeInsets.only(bottom: bottomPadding),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.45),
        border: Border(
          left: BorderSide(color: AppColors.border(0.06)),
        ),
      ),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(24, 52, 24, 24),
        children: [
          Text('STATION',
              style: AppTypography.mono(10,
                  color: AppColors.onBgMuted(0.4), letterSpacing: 1.8)),
          const SizedBox(height: 8),
          Text(station.name,
              style: AppTypography.display(22), maxLines: 3),
          if (station.tagList.isNotEmpty) ...[
            const SizedBox(height: 14),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: station.tagList.take(6).map((t) {
                return Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppColors.surface(0.06),
                    borderRadius: BorderRadius.circular(3),
                  ),
                  child: Text(
                    t.toUpperCase(),
                    style: AppTypography.mono(9,
                        color: AppColors.onBgMuted(0.75),
                        letterSpacing: 1),
                  ),
                );
              }).toList(),
            ),
          ],
          const SizedBox(height: 18),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.surface(0.03),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.border(0.06)),
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: _Stat(
                        label: 'Bitrate',
                        value: station.bitrate > 0
                            ? '${station.bitrate}'
                            : '—',
                        suffix: 'kbps',
                      ),
                    ),
                    Expanded(
                      child: _Stat(
                        label: 'Codec',
                        value: station.codec.isEmpty
                            ? 'MP3'
                            : station.codec.toUpperCase(),
                        suffix: 'stereo',
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: _Stat(
                        label: 'Votes',
                        value: station.votes.toString(),
                        suffix: 'on RB',
                      ),
                    ),
                    Expanded(
                      child: _Stat(
                        label: 'Country',
                        value: station.countryCode.isEmpty
                            ? '—'
                            : station.countryCode,
                        suffix: station.country.isEmpty
                            ? ''
                            : station.country.split(' ').first,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Text('ICY STREAM',
              style: AppTypography.mono(10,
                  color: AppColors.onBgMuted(0.4), letterSpacing: 1.8)),
          const SizedBox(height: 8),
          if (np.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(
                'Waiting for metadata…',
                style: AppTypography.body(12,
                    color: AppColors.onBgMuted(0.5)),
              ),
            )
          else
            Container(
              padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(
                border: Border(
                    bottom: BorderSide(color: AppColors.border(0.05))),
              ),
              child: Row(
                children: [
                  SizedBox(
                    width: 24,
                    child: Text('▶',
                        style: AppTypography.mono(10,
                            color: AppColors.accent)),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(np.title.isNotEmpty ? np.title : '—',
                            style: AppTypography.body(12,
                                color: AppColors.onBgStrong),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis),
                        Text(np.artist,
                            style: AppTypography.body(11,
                                color: AppColors.onBgMuted(0.5)),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 24),
          const SleepTimerPanel(),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  final String label;
  final String value;
  final String suffix;
  const _Stat(
      {required this.label, required this.value, required this.suffix});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label.toUpperCase(),
            style: AppTypography.mono(9,
                color: AppColors.onBgMuted(0.4), letterSpacing: 1)),
        const SizedBox(height: 2),
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Flexible(
              child: Text(value,
                  style: AppTypography.display(22, height: 1.0),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis),
            ),
            if (suffix.isNotEmpty) ...[
              const SizedBox(width: 4),
              Text(suffix,
                  style: AppTypography.mono(10,
                      color: AppColors.onBgMuted(0.45))),
            ],
          ],
        ),
      ],
    );
  }
}

class _DesktopPlayerBar extends StatelessWidget {
  final RadioStation station;
  final WidgetRef ref;
  const _DesktopPlayerBar({required this.station, required this.ref});

  @override
  Widget build(BuildContext context) {
    final playerState = ref.watch(radioPlayerControllerProvider);
    final volume = ref.watch(volumeProvider);
    final isFavorite = ref.watch(isFavoriteProvider(station.stationuuid));
    final np = playerState.nowPlaying;

    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 28, sigmaY: 28),
        child: Container(
          height: 80,
          padding: const EdgeInsets.symmetric(horizontal: 24),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.75),
            border: Border(
              top: BorderSide(color: AppColors.border(0.1)),
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Row(
                  children: [
                    StationArt(station: station, size: 52, radius: 4),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            np.isNotEmpty ? np.title : station.name,
                            style: AppTypography.body(13,
                                color: AppColors.onBgStrong,
                                weight: FontWeight.w500),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            np.isNotEmpty
                                ? '${np.artist} · ${station.name}'
                                : station.country,
                            style: AppTypography.body(11,
                                color: AppColors.onBgMuted(0.55)),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: isFavorite ? 'Unfavorite' : 'Favorite',
                      icon: Icon(
                        isFavorite ? Icons.favorite : Icons.favorite_border,
                        color: isFavorite
                            ? AppColors.accent
                            : AppColors.onBgMuted(0.5),
                        size: 18,
                      ),
                      onPressed: () => ref
                          .read(favoritesProvider.notifier)
                          .toggle(station),
                    ),
                  ],
                ),
              ),
              SizedBox(
                width: 160,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    GestureDetector(
                      onTap: playerState.isLoading
                          ? null
                          : () => ref
                              .read(radioPlayerControllerProvider.notifier)
                              .togglePlayPause(),
                      child: Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white,
                          boxShadow: [
                            BoxShadow(
                                color: AppColors.accentGlow(0.35),
                                blurRadius: 20),
                          ],
                        ),
                        child: playerState.isLoading
                            ? const Padding(
                                padding: EdgeInsets.all(12),
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor:
                                      AlwaysStoppedAnimation(Color(0xFF0A0A0A)),
                                ),
                              )
                            : Icon(
                                playerState.isPlaying
                                    ? Icons.pause_rounded
                                    : Icons.play_arrow_rounded,
                                size: 22,
                                color: const Color(0xFF0A0A0A),
                              ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    IconButton(
                      tooltip: 'Stop',
                      icon: Icon(Icons.stop_rounded,
                          color: AppColors.onBgMuted(0.6)),
                      onPressed: () => ref
                          .read(radioPlayerControllerProvider.notifier)
                          .stop(),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Icon(
                      volume == 0
                          ? Icons.volume_off
                          : volume < 0.5
                              ? Icons.volume_down
                              : Icons.volume_up,
                      size: 16,
                      color: AppColors.onBgMuted(0.55),
                    ),
                    const SizedBox(width: 8),
                    SizedBox(
                      width: 140,
                      child: SliderTheme(
                        data: SliderTheme.of(context).copyWith(
                          trackHeight: 3,
                          thumbShape: const RoundSliderThumbShape(
                              enabledThumbRadius: 5),
                        ),
                        child: Slider(
                          value: volume,
                          onChanged: (v) => ref
                              .read(volumeProvider.notifier)
                              .setVolume(v),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
