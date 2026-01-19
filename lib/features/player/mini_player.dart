import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/audio_player_provider.dart';
import 'player_screen.dart';

class MiniPlayer extends ConsumerWidget {
  const MiniPlayer({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playerState = ref.watch(radioPlayerControllerProvider);
    final station = playerState.currentStation;

    if (station == null) {
      return const SizedBox.shrink();
    }

    final colorScheme = Theme.of(context).colorScheme;

    return GestureDetector(
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) => PlayerScreen(station: station),
          ),
        );
      },
      child: Container(
        height: 64,
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerHighest,
          boxShadow: [
            BoxShadow(
              color: colorScheme.shadow.withAlpha(26),
              blurRadius: 8,
              offset: const Offset(0, -2),
            ),
          ],
        ),
        child: Row(
          children: [
            // Artwork
            _buildMiniArtwork(context, station.favicon),

            // Station info
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      station.name,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (playerState.nowPlaying.isNotEmpty)
                      Text(
                        playerState.nowPlaying.displayText,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                            ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                ),
              ),
            ),

            // Controls
            if (playerState.isLoading)
              const Padding(
                padding: EdgeInsets.all(12),
                child: SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
            else
              IconButton(
                icon: Icon(
                  playerState.isPlaying ? Icons.pause : Icons.play_arrow,
                ),
                onPressed: () {
                  ref
                      .read(radioPlayerControllerProvider.notifier)
                      .togglePlayPause();
                },
              ),

            IconButton(
              icon: const Icon(Icons.close),
              onPressed: () {
                ref.read(radioPlayerControllerProvider.notifier).stop();
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMiniArtwork(BuildContext context, String favicon) {
    if (favicon.isEmpty) {
      return Container(
        width: 64,
        height: 64,
        color: Theme.of(context).colorScheme.primaryContainer,
        child: Icon(
          Icons.radio,
          color: Theme.of(context).colorScheme.onPrimaryContainer,
        ),
      );
    }

    return SizedBox(
      width: 64,
      height: 64,
      child: Image.network(
        favicon,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) {
          return Container(
            color: Theme.of(context).colorScheme.primaryContainer,
            child: Icon(
              Icons.radio,
              color: Theme.of(context).colorScheme.onPrimaryContainer,
            ),
          );
        },
      ),
    );
  }
}
