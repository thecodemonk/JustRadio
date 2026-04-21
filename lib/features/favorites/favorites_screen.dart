import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/app_theme.dart';
import '../../data/models/radio_station.dart';
import '../../providers/favorites_provider.dart';
import '../search/widgets/station_list_tile.dart';
import '../player/player_screen.dart';

class FavoritesScreen extends ConsumerWidget {
  const FavoritesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final favorites = ref.watch(favoritesProvider);

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          favorites.isEmpty
                              ? 'NO STATIONS YET'
                              : '${favorites.length} STATION${favorites.length == 1 ? '' : 'S'}',
                          style: AppTypography.label(10, letterSpacing: 2),
                        ),
                        const SizedBox(height: 6),
                        Text('Your favorites',
                            style: AppTypography.display(38)),
                      ],
                    ),
                  ),
                  if (favorites.isNotEmpty)
                    IconButton(
                      tooltip: 'Clear all',
                      icon: Icon(Icons.delete_outline,
                          color: AppColors.onBgMuted(0.6)),
                      onPressed: () => _showClearDialog(context, ref),
                    ),
                ],
              ),
            ),
            Expanded(
              child: favorites.isEmpty
                  ? _buildEmptyState(context)
                  : _buildFavoritesList(context, ref, favorites),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showAddCustomDialog(context, ref),
        icon: const Icon(Icons.add),
        label: const Text('Add stream'),
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.favorite_border,
            size: 56,
            color: AppColors.accentGlow(0.5),
          ),
          const SizedBox(height: 14),
          Text('Nothing pinned yet', style: AppTypography.display(24)),
          const SizedBox(height: 8),
          Text(
            'Tap the heart on a station\nto save it here.',
            style: AppTypography.body(13, color: AppColors.onBgMuted(0.55)),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildFavoritesList(
    BuildContext context,
    WidgetRef ref,
    List<RadioStation> favorites,
  ) {
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 140),
      itemCount: favorites.length,
      itemBuilder: (context, index) {
        final station = favorites[index];
        return Dismissible(
          key: Key(station.stationuuid),
          direction: DismissDirection.endToStart,
          background: Container(
            alignment: Alignment.centerRight,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            margin: const EdgeInsets.symmetric(horizontal: 4),
            decoration: BoxDecoration(
              color: AppColors.live.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(Icons.delete, color: AppColors.live),
          ),
          onDismissed: (direction) {
            ref.read(favoritesProvider.notifier).remove(station.stationuuid);
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('${station.name} removed from favorites'),
                action: SnackBarAction(
                  label: 'Undo',
                  textColor: AppColors.accent,
                  onPressed: () =>
                      ref.read(favoritesProvider.notifier).add(station),
                ),
              ),
            );
          },
          child: StationListTile(
            station: station,
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (context) => PlayerScreen(station: station),
                ),
              );
            },
          ),
        );
      },
    );
  }

  void _showAddCustomDialog(BuildContext context, WidgetRef ref) {
    final nameController = TextEditingController();
    final urlController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add Custom Stream'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              decoration: const InputDecoration(
                labelText: 'Name',
                hintText: 'My Station',
              ),
              autofocus: true,
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: urlController,
              decoration: const InputDecoration(
                labelText: 'Stream URL',
                hintText: 'https://example.com/stream',
              ),
              keyboardType: TextInputType.url,
              textInputAction: TextInputAction.done,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.accent,
              foregroundColor: const Color(0xFF0A0A0A),
            ),
            onPressed: () {
              final name = nameController.text.trim();
              final url = urlController.text.trim();
              if (name.isEmpty || url.isEmpty) {
                Navigator.pop(context);
                return;
              }
              final station = RadioStation(
                stationuuid:
                    'custom-${DateTime.now().millisecondsSinceEpoch}',
                name: name,
                url: url,
              );
              ref.read(favoritesProvider.notifier).add(station);
              Navigator.pop(context);
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }

  void _showClearDialog(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear Favorites'),
        content: const Text(
          'Are you sure you want to remove all stations from your favorites?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.live,
              foregroundColor: Colors.white,
            ),
            onPressed: () {
              ref.read(favoritesProvider.notifier).clear();
              Navigator.pop(context);
            },
            child: const Text('Clear All'),
          ),
        ],
      ),
    );
  }
}
