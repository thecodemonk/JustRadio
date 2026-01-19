import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../data/models/radio_station.dart';
import '../../../providers/favorites_provider.dart';

class StationListTile extends ConsumerWidget {
  final RadioStation station;
  final VoidCallback onTap;

  const StationListTile({
    super.key,
    required this.station,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isFavorite = ref.watch(isFavoriteProvider(station.stationuuid));
    final colorScheme = Theme.of(context).colorScheme;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        onTap: onTap,
        leading: _buildFavicon(context),
        title: Text(
          station.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: _buildSubtitle(context),
        trailing: IconButton(
          icon: Icon(
            isFavorite ? Icons.favorite : Icons.favorite_border,
            color: isFavorite ? colorScheme.primary : null,
          ),
          onPressed: () {
            ref.read(favoritesProvider.notifier).toggle(station);
          },
        ),
      ),
    );
  }

  Widget _buildFavicon(BuildContext context) {
    if (station.favicon.isEmpty) {
      return Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.primaryContainer,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(
          Icons.radio,
          color: Theme.of(context).colorScheme.onPrimaryContainer,
        ),
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Image.network(
        station.favicon,
        width: 48,
        height: 48,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) {
          return Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              Icons.radio,
              color: Theme.of(context).colorScheme.onPrimaryContainer,
            ),
          );
        },
      ),
    );
  }

  Widget? _buildSubtitle(BuildContext context) {
    final parts = <String>[];

    if (station.country.isNotEmpty) {
      parts.add(station.country);
    }

    if (station.tagList.isNotEmpty) {
      parts.add(station.tagList.first);
    }

    if (station.bitrate > 0) {
      parts.add('${station.bitrate} kbps');
    }

    if (parts.isEmpty) return null;

    return Text(
      parts.join(' • '),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: Theme.of(context).textTheme.bodySmall,
    );
  }
}
