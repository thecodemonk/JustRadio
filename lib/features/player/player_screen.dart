import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/models/radio_station.dart';
import '../../providers/audio_player_provider.dart';
import '../../providers/favorites_provider.dart';

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
  @override
  void initState() {
    super.initState();
    // Start playing the station
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(radioPlayerControllerProvider.notifier).playStation(widget.station);
    });
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
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            children: [
              const Spacer(),

              // Station artwork
              _buildArtwork(context),
              const SizedBox(height: 32),

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

              const Spacer(),

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

              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
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

    return Column(
      children: [
        if (state.nowPlaying.artist.isNotEmpty)
          Text(
            state.nowPlaying.artist,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: Theme.of(context).colorScheme.primary,
                ),
            textAlign: TextAlign.center,
          ),
        if (state.nowPlaying.title.isNotEmpty)
          Text(
            state.nowPlaying.title,
            style: Theme.of(context).textTheme.bodyLarge,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
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
