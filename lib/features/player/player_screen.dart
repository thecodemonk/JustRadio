import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/models/radio_station.dart';
import '../../providers/audio_player_provider.dart';
import '../../providers/favorites_provider.dart';
import '../../providers/lastfm_provider.dart';

class PlayerScreen extends ConsumerStatefulWidget {
  final RadioStation station;

  const PlayerScreen({
    super.key,
    required this.station,
  });

  @override
  ConsumerState<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends ConsumerState<PlayerScreen> {
  String? _lovedTrackKey;
  bool _isLoved = false;
  bool _isLoveBusy = false;

  @override
  void initState() {
    super.initState();
    // Start playing the station
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(radioPlayerControllerProvider.notifier).playStation(widget.station);
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
        ? await lastfmService.repository.loveTrack(artist: artist, track: title)
        : await lastfmService.repository.unloveTrack(artist: artist, track: title);

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
    final playerState = ref.watch(radioPlayerControllerProvider);
    final isFavorite = ref.watch(isFavoriteProvider(widget.station.stationuuid));
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Now Playing'),
        actions: [
          IconButton(
            icon: Icon(
              isFavorite ? Icons.favorite : Icons.favorite_border,
              color: isFavorite ? colorScheme.primary : null,
            ),
            onPressed: () {
              ref.read(favoritesProvider.notifier).toggle(widget.station);
            },
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            children: [
              const SizedBox(height: 16),

              // Station artwork
              _buildArtwork(context),
              const SizedBox(height: 24),

              // Station name
              Text(
                widget.station.name,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 8),

              // Now playing info
              _buildNowPlayingInfo(context, playerState),
              const SizedBox(height: 8),

              // Station details
              _buildStationDetails(context),

              const SizedBox(height: 32),

              // Error message
              if (playerState.error != null)
                Container(
                  padding: const EdgeInsets.all(12),
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: colorScheme.errorContainer,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    playerState.error!,
                    style: TextStyle(color: colorScheme.onErrorContainer),
                    textAlign: TextAlign.center,
                  ),
                ),

              // Player controls
              _buildPlayerControls(context, playerState),

              const SizedBox(height: 24),

              // Volume control
              _buildVolumeControl(context),

              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildVolumeControl(BuildContext context) {
    final volume = ref.watch(volumeProvider);
    final colorScheme = Theme.of(context).colorScheme;

    return Row(
      children: [
        Icon(
          volume == 0 ? Icons.volume_off : Icons.volume_down,
          color: colorScheme.onSurfaceVariant,
          size: 20,
        ),
        Expanded(
          child: Slider(
            value: volume,
            onChanged: (value) {
              ref.read(volumeProvider.notifier).setVolume(value);
            },
          ),
        ),
        Icon(
          Icons.volume_up,
          color: colorScheme.onSurfaceVariant,
          size: 20,
        ),
      ],
    );
  }

  Widget _buildArtwork(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      width: 250,
      height: 250,
      decoration: BoxDecoration(
        color: colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: colorScheme.shadow.withAlpha(51),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: widget.station.favicon.isNotEmpty
          ? ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: Image.network(
                widget.station.favicon,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) {
                  return _buildDefaultArtwork(context);
                },
              ),
            )
          : _buildDefaultArtwork(context),
    );
  }

  Widget _buildDefaultArtwork(BuildContext context) {
    return Icon(
      Icons.radio,
      size: 100,
      color: Theme.of(context).colorScheme.onPrimaryContainer,
    );
  }

  Widget _buildNowPlayingInfo(BuildContext context, RadioPlayerState state) {
    if (state.nowPlaying.isEmpty) {
      return Text(
        'Waiting for stream info...',
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
      );
    }

    final artist = state.nowPlaying.artist;
    final title = state.nowPlaying.title;
    final isAuthed = ref.watch(lastfmStateProvider).isAuthenticated;

    if (artist.isNotEmpty && title.isNotEmpty && isAuthed) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _syncLovedState(artist, title);
      });
    }

    return Column(
      children: [
        if (artist.isNotEmpty)
          Text(
            artist,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: Theme.of(context).colorScheme.primary,
                ),
            textAlign: TextAlign.center,
          ),
        if (title.isNotEmpty)
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Flexible(
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.bodyLarge,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (isAuthed && artist.isNotEmpty) ...[
                const SizedBox(width: 8),
                IconButton(
                  iconSize: 20,
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  tooltip: _isLoved ? 'Unlove on Last.fm' : 'Love on Last.fm',
                  onPressed: _isLoveBusy ? null : () => _toggleLove(artist, title),
                  icon: Icon(
                    _isLoved ? Icons.favorite : Icons.favorite_border,
                    color: _isLoved
                        ? Theme.of(context).colorScheme.primary
                        : Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ],
          ),
      ],
    );
  }

  Widget _buildStationDetails(BuildContext context) {
    final station = widget.station;
    final parts = <String>[];

    if (station.country.isNotEmpty) {
      parts.add(station.country);
    }
    if (station.tagList.isNotEmpty) {
      parts.add(station.tagList.take(2).join(', '));
    }
    if (station.bitrate > 0) {
      parts.add('${station.bitrate} kbps');
    }

    if (parts.isEmpty) return const SizedBox.shrink();

    return Text(
      parts.join(' • '),
      style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
      textAlign: TextAlign.center,
    );
  }

  Widget _buildPlayerControls(BuildContext context, RadioPlayerState state) {
    final colorScheme = Theme.of(context).colorScheme;

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // Stop button
        IconButton.filled(
          onPressed: () {
            ref.read(radioPlayerControllerProvider.notifier).stop();
            Navigator.of(context).pop();
          },
          icon: const Icon(Icons.stop),
          iconSize: 32,
          style: IconButton.styleFrom(
            backgroundColor: colorScheme.surfaceContainerHighest,
            foregroundColor: colorScheme.onSurface,
          ),
        ),
        const SizedBox(width: 24),

        // Play/Pause button
        SizedBox(
          width: 80,
          height: 80,
          child: state.isLoading
              ? Container(
                  decoration: BoxDecoration(
                    color: colorScheme.primaryContainer,
                    shape: BoxShape.circle,
                  ),
                  child: const Center(
                    child: CircularProgressIndicator(),
                  ),
                )
              : IconButton.filled(
                  onPressed: () {
                    ref
                        .read(radioPlayerControllerProvider.notifier)
                        .togglePlayPause();
                  },
                  icon: Icon(
                    state.isPlaying ? Icons.pause : Icons.play_arrow,
                  ),
                  iconSize: 48,
                  style: IconButton.styleFrom(
                    backgroundColor: colorScheme.primaryContainer,
                    foregroundColor: colorScheme.onPrimaryContainer,
                  ),
                ),
        ),
        const SizedBox(width: 24),

        // Placeholder for symmetry
        const SizedBox(width: 48),
      ],
    );
  }
}
