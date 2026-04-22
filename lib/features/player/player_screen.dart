import 'dart:async';

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
import '../../providers/lastfm_provider.dart';
import '../../providers/sleep_timer_provider.dart';

class PlayerScreen extends ConsumerStatefulWidget {
  final RadioStation station;

  const PlayerScreen({super.key, required this.station});

  @override
  ConsumerState<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends ConsumerState<PlayerScreen> {
  String? _lovedTrackKey;
  bool _isLoved = false;
  bool _isLoveBusy = false;
  DateTime? _listenStart;

  @override
  void initState() {
    super.initState();
    _listenStart = DateTime.now();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final playerState = ref.read(radioPlayerControllerProvider);
      final current = playerState.currentStation;
      if (current?.stationuuid != widget.station.stationuuid) {
        ref
            .read(radioPlayerControllerProvider.notifier)
            .playStation(widget.station);
      } else {
        // Same station is already playing — sync loved state for whatever
        // track is already on air, since our ref.listen only fires on
        // subsequent changes.
        final isAuthed = ref.read(lastfmStateProvider).isAuthenticated;
        final np = playerState.nowPlaying;
        if (isAuthed && np.artist.isNotEmpty && np.title.isNotEmpty) {
          _syncLovedState(np.artist, np.title);
        }
      }
    });
  }

  String _trackKey(String artist, String title) => '$artist|$title';

  Future<void> _syncLovedState(String artist, String title) async {
    final key = _trackKey(artist, title);
    if (_lovedTrackKey == key) return;

    final lastfmService = ref.read(lastfmAuthServiceProvider);
    final username = ref.read(lastfmStateProvider).username;
    if (!lastfmService.isAuthenticated || username == null) {
      setState(() {
        _lovedTrackKey = key;
        _isLoved = false;
      });
      return;
    }

    setState(() {
      _lovedTrackKey = key;
      _isLoved = false;
    });

    final loved = await lastfmService.repository.isTrackLoved(
      artist: artist,
      track: title,
      username: username,
    );
    if (!mounted || _lovedTrackKey != key) return;
    setState(() => _isLoved = loved);
  }

  Future<void> _toggleLove(String artist, String title) async {
    if (_isLoveBusy) return;
    final lastfmService = ref.read(lastfmAuthServiceProvider);
    if (!lastfmService.isAuthenticated) return;

    final wantLoved = !_isLoved;
    setState(() {
      _isLoveBusy = true;
      _isLoved = wantLoved;
    });

    final success = wantLoved
        ? await lastfmService.repository.loveTrack(
            artist: artist, track: title)
        : await lastfmService.repository.unloveTrack(
            artist: artist, track: title);

    if (!mounted) return;
    setState(() {
      _isLoveBusy = false;
      if (!success) _isLoved = !wantLoved;
    });

    if (!success) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            wantLoved
                ? 'Failed to love track on Last.fm'
                : 'Failed to unlove track on Last.fm',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<RadioPlayerState>(radioPlayerControllerProvider, (prev, next) {
      final isAuthed = ref.read(lastfmStateProvider).isAuthenticated;
      final artist = next.nowPlaying.artist;
      final title = next.nowPlaying.title;
      if (isAuthed && artist.isNotEmpty && title.isNotEmpty) {
        _syncLovedState(artist, title);
      }
    });

    final playerState = ref.watch(radioPlayerControllerProvider);
    final isFavorite = ref.watch(isFavoriteProvider(widget.station.stationuuid));
    final station = widget.station;

    final artist = playerState.nowPlaying.artist;
    final title = playerState.nowPlaying.title;
    final isAuthed = ref.watch(lastfmStateProvider).isAuthenticated;

    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, size: 20),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          'Now Playing',
          style: AppTypography.label(10, letterSpacing: 2).copyWith(
            color: AppColors.onBgMuted(0.6),
          ),
        ),
        actions: [
          _SleepTimerAction(),
          IconButton(
            tooltip: isFavorite ? 'Remove favorite' : 'Add favorite',
            icon: Icon(
              isFavorite ? Icons.favorite : Icons.favorite_border,
              color: isFavorite ? AppColors.accent : AppColors.onBgMuted(0.7),
            ),
            onPressed: () {
              ref.read(favoritesProvider.notifier).toggle(station);
            },
          ),
        ],
      ),
      body: Stack(
        children: [
          Positioned.fill(child: AmbientBg(station: station)),
          SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 140),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _LiveBreadcrumb(station: station),
                  const SizedBox(height: 32),
                  Center(
                    child: NowPlayingArt(
                      station: station,
                      albumArtUrl: playerState.albumArtUrl,
                      size: 260,
                      radius: 8,
                      shadow: BoxShadow(
                        color: Colors.black.withValues(alpha: 0.5),
                        blurRadius: 60,
                        offset: const Offset(0, 20),
                      ),
                    ),
                  ),
                  const SizedBox(height: 36),
                  _TrackMeta(
                    artist: artist,
                    title: title,
                    stationName: station.name,
                    isAuthed: isAuthed,
                    isLoved: _isLoved,
                    isLoveBusy: _isLoveBusy,
                    onToggleLove: artist.isNotEmpty && title.isNotEmpty
                        ? () => _toggleLove(artist, title)
                        : null,
                  ),
                  const SizedBox(height: 32),
                  _LiveWaveformPanel(
                    station: station,
                    playing: playerState.isPlaying,
                    listenStart: _listenStart,
                  ),
                  if (playerState.error != null) ...[
                    const SizedBox(height: 20),
                    _ErrorBanner(message: playerState.error!),
                  ],
                  const SizedBox(height: 28),
                  _PlayerControls(
                    isPlaying: playerState.isPlaying,
                    isLoading: playerState.isLoading,
                    onTogglePlay: () => ref
                        .read(radioPlayerControllerProvider.notifier)
                        .togglePlayPause(),
                    onStop: () {
                      ref.read(radioPlayerControllerProvider.notifier).stop();
                      Navigator.of(context).pop();
                    },
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LiveBreadcrumb extends StatelessWidget {
  final RadioStation station;
  const _LiveBreadcrumb({required this.station});

  @override
  Widget build(BuildContext context) {
    final parts = <String>[
      station.name,
      if (station.country.isNotEmpty) station.country,
      if (station.bitrate > 0) '${station.bitrate} kbps',
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            _PulsingDot(color: AppColors.live),
            const SizedBox(width: 8),
            Text(
              'ON AIR · LIVE',
              style: AppTypography.label(10, letterSpacing: 2).copyWith(
                color: AppColors.onBgMuted(0.5),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          parts.join(' · '),
          style: AppTypography.body(13,
              color: AppColors.onBgMuted(0.7)),
        ),
      ],
    );
  }
}

class _PulsingDot extends StatefulWidget {
  final Color color;
  const _PulsingDot({required this.color});

  @override
  State<_PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<_PulsingDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (_, __) {
        final t = Curves.easeInOut.transform(_c.value);
        return Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(
            color: widget.color,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: widget.color.withValues(alpha: 0.3 + 0.5 * t),
                blurRadius: 8 + 6 * t,
                spreadRadius: 0.5,
              ),
            ],
          ),
        );
      },
    );
  }
}

class _TrackMeta extends StatelessWidget {
  final String artist;
  final String title;
  final String stationName;
  final bool isAuthed;
  final bool isLoved;
  final bool isLoveBusy;
  final VoidCallback? onToggleLove;

  const _TrackMeta({
    required this.artist,
    required this.title,
    required this.stationName,
    required this.isAuthed,
    required this.isLoved,
    required this.isLoveBusy,
    required this.onToggleLove,
  });

  @override
  Widget build(BuildContext context) {
    final hasTrack = artist.isNotEmpty || title.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'NOW PLAYING',
          style: AppTypography.label(10, letterSpacing: 2)
              .copyWith(color: AppColors.accent, fontWeight: FontWeight.w500),
        ),
        const SizedBox(height: 10),
        if (!hasTrack)
          Text(
            stationName,
            style: AppTypography.display(40),
          )
        else ...[
          Text(
            title.isEmpty ? stationName : title,
            style: AppTypography.display(42),
          ),
          if (artist.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              artist,
              style: AppTypography.body(18,
                  color: AppColors.onBgMuted(0.85), weight: FontWeight.w300),
            ),
          ],
        ],
        if (isAuthed) ...[
          const SizedBox(height: 18),
          Row(
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.scrobble.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(3),
                  border: Border.all(
                    color: AppColors.scrobble.withValues(alpha: 0.3),
                  ),
                ),
                child: Text(
                  '● SCROBBLING TO LAST.FM',
                  style: AppTypography.mono(9,
                      color: AppColors.scrobble, letterSpacing: 1),
                ),
              ),
              const Spacer(),
              if (onToggleLove != null)
                InkWell(
                  onTap: isLoveBusy ? null : onToggleLove,
                  borderRadius: BorderRadius.circular(6),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 4),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          isLoved ? Icons.favorite : Icons.favorite_border,
                          size: 14,
                          color: isLoved
                              ? AppColors.accent
                              : AppColors.onBgMuted(0.55),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          isLoved ? 'Loved' : 'Love',
                          style: AppTypography.body(11,
                              color: isLoved
                                  ? AppColors.accent
                                  : AppColors.onBgMuted(0.55)),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ],
      ],
    );
  }
}

class _LiveWaveformPanel extends ConsumerStatefulWidget {
  final RadioStation station;
  final bool playing;
  final DateTime? listenStart;

  const _LiveWaveformPanel({
    required this.station,
    required this.playing,
    required this.listenStart,
  });

  @override
  ConsumerState<_LiveWaveformPanel> createState() => _LiveWaveformPanelState();
}

class _LiveWaveformPanelState extends ConsumerState<_LiveWaveformPanel> {
  late final Stream<DateTime> _ticker = Stream.periodic(
    const Duration(seconds: 1),
    (_) => DateTime.now(),
  );

  String _elapsed() {
    if (widget.listenStart == null) return '00:00:00';
    final d = DateTime.now().difference(widget.listenStart!);
    final h = d.inHours.toString().padLeft(2, '0');
    final m = (d.inMinutes % 60).toString().padLeft(2, '0');
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$h:$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.station;
    // Prefer runtime codec + bitrate from the native player over the Radio
    // Browser DB values, which for HLS commonly give "MP4" / bitrate=0 even
    // when the actual audio is something like FLAC at a meaningful rate.
    final debug = ref.watch(icyDebugStreamProvider).valueOrNull;
    final runtimeCodec = debug?.codec;
    final runtimeBitrate = debug?.bitrate ?? 0;
    final codec = (runtimeCodec != null && runtimeCodec.isNotEmpty)
        ? runtimeCodec.toUpperCase()
        : (s.codec.isEmpty ? 'MP3' : s.codec.toUpperCase());
    final effectiveBitrate = runtimeBitrate > 0 ? runtimeBitrate : s.bitrate;
    final bitrate = effectiveBitrate > 0 ? '$effectiveBitrate KBPS' : '—';

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.surface(0.04),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border(0.06)),
      ),
      child: Column(
        children: [
          SizedBox(
            height: 48,
            child: Waveform(
              seedKey: s.stationuuid.isEmpty ? s.name : s.stationuuid,
              bars: 90,
              height: 48,
              color: AppColors.accent,
              progress: widget.playing ? 1.0 : 0.0,
              animate: widget.playing,
            ),
          ),
          const SizedBox(height: 14),
          StreamBuilder<DateTime>(
            stream: _ticker,
            builder: (ctx, _) => Row(
              children: [
                Expanded(
                  child: Text(
                    'LISTENING · ${_elapsed()}',
                    style: AppTypography.mono(10,
                        color: AppColors.onBgMuted(0.55)),
                  ),
                ),
                Text(
                  '$bitrate · $codec',
                  style: AppTypography.mono(10,
                      color: AppColors.accent, letterSpacing: 1.2),
                ),
                const SizedBox(width: 10),
                Text(
                  '● LIVE',
                  style: AppTypography.mono(10,
                      color: AppColors.live, letterSpacing: 1.2),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PlayerControls extends StatelessWidget {
  final bool isPlaying;
  final bool isLoading;
  final VoidCallback onTogglePlay;
  final VoidCallback onStop;

  const _PlayerControls({
    required this.isPlaying,
    required this.isLoading,
    required this.onTogglePlay,
    required this.onStop,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _SecondaryButton(icon: Icons.stop_rounded, onTap: onStop),
        const SizedBox(width: 28),
        GestureDetector(
          onTap: isLoading ? null : onTogglePlay,
          child: Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: AppColors.accentGlow(0.45),
                  blurRadius: 32,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: isLoading
                ? const Padding(
                    padding: EdgeInsets.all(22),
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      valueColor:
                          AlwaysStoppedAnimation(Color(0xFF0A0A0A)),
                    ),
                  )
                : Icon(
                    isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                    size: 36,
                    color: const Color(0xFF0A0A0A),
                  ),
          ),
        ),
        const SizedBox(width: 28),
        const _VolumePopoverButton(),
      ],
    );
  }
}

/// Volume control — shows a speaker button; click it to reveal a vertical
/// slider in a popover. Slider auto-hides after a short idle window. Matches
/// the Netflix / Plex volume-control pattern.
class _VolumePopoverButton extends ConsumerStatefulWidget {
  const _VolumePopoverButton();

  @override
  ConsumerState<_VolumePopoverButton> createState() =>
      _VolumePopoverButtonState();
}

class _VolumePopoverButtonState extends ConsumerState<_VolumePopoverButton> {
  final _overlayController = OverlayPortalController();
  final _layerLink = LayerLink();
  Timer? _hideTimer;

  /// How long the popover stays visible after the user last touched it.
  static const _idleHide = Duration(milliseconds: 2500);

  @override
  void dispose() {
    _hideTimer?.cancel();
    super.dispose();
  }

  void _toggle() {
    if (_overlayController.isShowing) {
      _hide();
    } else {
      _overlayController.show();
      _armHideTimer();
    }
  }

  void _armHideTimer() {
    _hideTimer?.cancel();
    _hideTimer = Timer(_idleHide, _hide);
  }

  void _hide() {
    _hideTimer?.cancel();
    if (_overlayController.isShowing) _overlayController.hide();
  }

  @override
  Widget build(BuildContext context) {
    final volume = ref.watch(volumeProvider);
    final icon = volume <= 0
        ? Icons.volume_off
        : volume < 0.5
            ? Icons.volume_down
            : Icons.volume_up;

    return CompositedTransformTarget(
      link: _layerLink,
      child: OverlayPortal(
        controller: _overlayController,
        overlayChildBuilder: (ctx) => _buildOverlay(ctx, volume),
        child: _SecondaryButton(icon: icon, onTap: _toggle),
      ),
    );
  }

  Widget _buildOverlay(BuildContext ctx, double volume) {
    // Full-screen tap catcher so clicks outside the popover dismiss it,
    // same as a native macOS popover.
    return Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTap: _hide,
          ),
        ),
        CompositedTransformFollower(
          link: _layerLink,
          followerAnchor: Alignment.bottomCenter,
          targetAnchor: Alignment.topCenter,
          offset: const Offset(0, -10),
          child: Material(
            color: Colors.transparent,
            child: _VolumeSliderCard(
              value: volume,
              onChanged: (v) {
                ref.read(volumeProvider.notifier).setVolume(v);
                _armHideTimer();
              },
              onInteraction: _armHideTimer,
            ),
          ),
        ),
      ],
    );
  }
}

class _VolumeSliderCard extends StatelessWidget {
  final double value;
  final ValueChanged<double> onChanged;
  final VoidCallback onInteraction;

  const _VolumeSliderCard({
    required this.value,
    required this.onChanged,
    required this.onInteraction,
  });

  @override
  Widget build(BuildContext context) {
    // Vertical slider via RotatedBox. 140pt tall is big enough to be
    // usable with a trackpad but small enough not to dominate the screen.
    return MouseRegion(
      onEnter: (_) => onInteraction(),
      onHover: (_) => onInteraction(),
      child: Container(
        width: 44,
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
        decoration: BoxDecoration(
          color: AppColors.bgElevated.withValues(alpha: 0.96),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border(0.1)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.4),
              blurRadius: 22,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.volume_up,
                size: 14, color: AppColors.onBgMuted(0.7)),
            SizedBox(
              height: 140,
              child: RotatedBox(
                quarterTurns: 3,
                child: SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: 3,
                    thumbShape: const RoundSliderThumbShape(
                        enabledThumbRadius: 6),
                    overlayShape: const RoundSliderOverlayShape(
                        overlayRadius: 14),
                  ),
                  child: Slider(
                    value: value,
                    onChanged: onChanged,
                    onChangeStart: (_) => onInteraction(),
                    onChangeEnd: (_) => onInteraction(),
                  ),
                ),
              ),
            ),
            Icon(Icons.volume_down,
                size: 14, color: AppColors.onBgMuted(0.7)),
          ],
        ),
      ),
    );
  }
}

class _SecondaryButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _SecondaryButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      shape: const CircleBorder(),
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: AppColors.surface(0.06),
            border: Border.all(color: AppColors.border(0.08)),
          ),
          child: Icon(icon, color: AppColors.onBg, size: 20),
        ),
      ),
    );
  }
}

class _SleepTimerAction extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(sleepTimerProvider);
    return IconButton(
      tooltip:
          state.isActive ? 'Sleep in ${state.formattedRemaining}' : 'Sleep timer',
      icon: Icon(
        state.isActive ? Icons.bedtime : Icons.bedtime_outlined,
        color: state.isActive ? AppColors.accent : AppColors.onBgMuted(0.7),
      ),
      onPressed: () {
        showModalBottomSheet(
          context: context,
          showDragHandle: true,
          builder: (ctx) => const Padding(
            padding: EdgeInsets.fromLTRB(24, 4, 24, 32),
            child: SleepTimerPanel(),
          ),
        );
      },
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  final String message;
  const _ErrorBanner({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.live.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.live.withValues(alpha: 0.3)),
      ),
      child: Text(
        message,
        style: AppTypography.body(12, color: AppColors.live),
        textAlign: TextAlign.center,
      ),
    );
  }
}
