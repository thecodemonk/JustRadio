import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../app.dart';
import '../../core/theme/app_theme.dart';
import '../../data/models/radio_station.dart';
import '../../data/services/favorites_io_service.dart';
import '../../providers/audio_player_provider.dart';
import '../../providers/favorites_provider.dart';
import '../search/widgets/station_list_tile.dart';

enum _FavoritesMenuAction { addCustom, import, export, clear }

enum _FavoritesSort { nameAsc, nameDesc, recent }

const int _kMaxTagChips = 12;

class FavoritesScreen extends ConsumerStatefulWidget {
  const FavoritesScreen({super.key});

  @override
  ConsumerState<FavoritesScreen> createState() => _FavoritesScreenState();
}

class _FavoritesScreenState extends ConsumerState<FavoritesScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _query = '';
  final Set<String> _selectedTags = <String>{};
  _FavoritesSort _sort = _FavoritesSort.nameAsc;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  bool get _hasActiveFilter => _query.trim().isNotEmpty || _selectedTags.isNotEmpty;

  void _clearFilters() {
    setState(() {
      _searchController.clear();
      _query = '';
      _selectedTags.clear();
    });
  }

  List<String> _topTags(List<RadioStation> favorites) {
    final counts = <String, int>{};
    for (final s in favorites) {
      for (final t in s.tagList) {
        final key = t.toLowerCase().trim();
        if (key.isEmpty) continue;
        counts[key] = (counts[key] ?? 0) + 1;
      }
    }
    final entries = counts.entries.toList()
      ..sort((a, b) {
        final byCount = b.value.compareTo(a.value);
        return byCount != 0 ? byCount : a.key.compareTo(b.key);
      });
    return entries.take(_kMaxTagChips).map((e) => e.key).toList();
  }

  List<RadioStation> _filterAndSort(List<RadioStation> favorites) {
    final q = _query.trim().toLowerCase();
    final hasQuery = q.isNotEmpty;
    final hasTags = _selectedTags.isNotEmpty;

    final indexed = <(RadioStation, int)>[
      for (var i = 0; i < favorites.length; i++) (favorites[i], i),
    ];

    final filtered = indexed.where((entry) {
      final s = entry.$1;
      if (hasQuery) {
        final hit = s.name.toLowerCase().contains(q) ||
            s.tags.toLowerCase().contains(q) ||
            s.country.toLowerCase().contains(q);
        if (!hit) return false;
      }
      if (hasTags) {
        final stationTags = s.tagList
            .map((t) => t.toLowerCase().trim())
            .where((t) => t.isNotEmpty)
            .toSet();
        if (!_selectedTags.any(stationTags.contains)) return false;
      }
      return true;
    }).toList();

    switch (_sort) {
      case _FavoritesSort.nameAsc:
        filtered.sort((a, b) =>
            a.$1.name.toLowerCase().compareTo(b.$1.name.toLowerCase()));
      case _FavoritesSort.nameDesc:
        filtered.sort((a, b) =>
            b.$1.name.toLowerCase().compareTo(a.$1.name.toLowerCase()));
      case _FavoritesSort.recent:
        filtered.sort((a, b) => b.$2.compareTo(a.$2));
    }

    return filtered.map((e) => e.$1).toList();
  }

  @override
  Widget build(BuildContext context) {
    final favorites = ref.watch(favoritesProvider);
    final isDesktop =
        MediaQuery.of(context).size.width >= kDesktopBreakpoint;
    final displayed = _filterAndSort(favorites);
    final showSearch = favorites.isNotEmpty;
    final showTagChips = isDesktop && favorites.isNotEmpty;
    final tagChips = showTagChips ? _topTags(favorites) : const <String>[];

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
                  PopupMenuButton<_FavoritesMenuAction>(
                    tooltip: 'More',
                    icon: Icon(Icons.more_vert,
                        color: AppColors.onBgMuted(0.6)),
                    onSelected: _handleMenuAction,
                    itemBuilder: (context) => [
                      const PopupMenuItem(
                        value: _FavoritesMenuAction.addCustom,
                        child: ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(Icons.add),
                          title: Text('Add custom stream...'),
                        ),
                      ),
                      const PopupMenuDivider(),
                      const PopupMenuItem(
                        value: _FavoritesMenuAction.import,
                        child: ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(Icons.file_download_outlined),
                          title: Text('Import from file...'),
                        ),
                      ),
                      PopupMenuItem(
                        value: _FavoritesMenuAction.export,
                        enabled: favorites.isNotEmpty,
                        child: const ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(Icons.file_upload_outlined),
                          title: Text('Export to file...'),
                        ),
                      ),
                      if (favorites.isNotEmpty) const PopupMenuDivider(),
                      if (favorites.isNotEmpty)
                        const PopupMenuItem(
                          value: _FavoritesMenuAction.clear,
                          child: ListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            leading: Icon(Icons.delete_outline),
                            title: Text('Clear all'),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
            if (showSearch)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                child: Row(
                  children: [
                    Expanded(child: _buildSearchField()),
                    if (isDesktop) ...[
                      const SizedBox(width: 8),
                      _buildSortButton(),
                    ],
                  ],
                ),
              ),
            if (showTagChips && tagChips.length >= 2)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                child: _buildTagChipRow(tagChips),
              ),
            Expanded(
              child: favorites.isEmpty
                  ? _buildEmptyState()
                  : displayed.isEmpty
                      ? _buildNoMatchesState()
                      : _buildFavoritesList(displayed),
            ),
          ],
        ),
      ),
    );
  }

  // Parent shell uses extendBody:true and inner Scaffold's MediaQuery does
  // not subtract the parent's bottom UI, so we lift content above
  // [system gesture inset] + [NavigationBar] + [MiniPlayer when playing].
  double _bottomShellInset(BuildContext context, WidgetRef ref) {
    const navBarHeight = 80.0;
    const miniPlayerHeight = 72.0;
    const breathingRoom = 12.0;
    final systemBottom = MediaQuery.viewPaddingOf(context).bottom;
    final isPlaying = ref.watch(
      radioPlayerControllerProvider.select((s) => s.currentStation != null),
    );
    return systemBottom +
        navBarHeight +
        (isPlaying ? miniPlayerHeight : 0) +
        breathingRoom;
  }

  Widget _buildSearchField() {
    return TextField(
      controller: _searchController,
      style: AppTypography.body(14, color: AppColors.onBg),
      decoration: InputDecoration(
        hintText: 'Search favorites…',
        prefixIcon: Icon(Icons.search,
            size: 18, color: AppColors.onBgMuted(0.5)),
        suffixIcon: _query.isNotEmpty
            ? IconButton(
                icon: Icon(Icons.clear,
                    size: 18, color: AppColors.onBgMuted(0.5)),
                onPressed: () {
                  _searchController.clear();
                  setState(() => _query = '');
                },
              )
            : null,
      ),
      onChanged: (value) => setState(() => _query = value),
    );
  }

  Widget _buildSortButton() {
    return PopupMenuButton<_FavoritesSort>(
      tooltip: 'Sort',
      initialValue: _sort,
      onSelected: (s) => setState(() => _sort = s),
      icon: Icon(Icons.sort, color: AppColors.onBgMuted(0.7)),
      itemBuilder: (context) => [
        _sortMenuItem(_FavoritesSort.nameAsc, 'Name (A → Z)'),
        _sortMenuItem(_FavoritesSort.nameDesc, 'Name (Z → A)'),
        _sortMenuItem(_FavoritesSort.recent, 'Recently added'),
      ],
    );
  }

  PopupMenuItem<_FavoritesSort> _sortMenuItem(
      _FavoritesSort value, String label) {
    final selected = _sort == value;
    return PopupMenuItem(
      value: value,
      child: Row(
        children: [
          SizedBox(
            width: 24,
            child: selected
                ? Icon(Icons.check, size: 16, color: AppColors.accent)
                : null,
          ),
          Text(label),
        ],
      ),
    );
  }

  Widget _buildTagChipRow(List<String> tags) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final tag in tags)
          _TagChip(
            label: tag,
            selected: _selectedTags.contains(tag),
            onTap: () => setState(() {
              if (!_selectedTags.add(tag)) _selectedTags.remove(tag);
            }),
          ),
        if (_selectedTags.isNotEmpty)
          _TagChip(
            label: 'Clear',
            selected: false,
            isClearAction: true,
            onTap: () => setState(_selectedTags.clear),
          ),
      ],
    );
  }

  Widget _buildEmptyState() {
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

  Widget _buildNoMatchesState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.search_off,
              size: 48, color: AppColors.onBgMuted(0.4)),
          const SizedBox(height: 12),
          Text('No matches', style: AppTypography.display(20)),
          const SizedBox(height: 6),
          Text(
            'No favorites match the current filter.',
            style: AppTypography.body(13, color: AppColors.onBgMuted(0.55)),
            textAlign: TextAlign.center,
          ),
          if (_hasActiveFilter) ...[
            const SizedBox(height: 12),
            TextButton(
              onPressed: _clearFilters,
              child: const Text('Clear filters'),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildFavoritesList(List<RadioStation> stations) {
    final bottomPad = _bottomShellInset(context, ref);
    return ListView.builder(
      padding: EdgeInsets.fromLTRB(12, 0, 12, bottomPad),
      itemCount: stations.length,
      itemBuilder: (context, index) {
        final station = stations[index];
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
            onTap: () => playStationFromList(
              ref: ref,
              context: context,
              station: station,
            ),
          ),
        );
      },
    );
  }

  void _showAddCustomDialog() {
    showDialog(
      context: context,
      builder: (context) => _AddCustomStreamDialog(
        onSubmit: (station) =>
            ref.read(favoritesProvider.notifier).add(station),
      ),
    );
  }

  Future<void> _handleMenuAction(_FavoritesMenuAction action) async {
    switch (action) {
      case _FavoritesMenuAction.addCustom:
        _showAddCustomDialog();
      case _FavoritesMenuAction.import:
        await _importFavorites();
      case _FavoritesMenuAction.export:
        await _exportFavorites();
      case _FavoritesMenuAction.clear:
        _showClearDialog();
    }
  }

  Future<void> _importFavorites() async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final stations = await FavoritesIoService().importFromFile();
      if (stations == null) return;
      if (stations.isEmpty) {
        messenger.showSnackBar(
          const SnackBar(content: Text('No stations found in file')),
        );
        return;
      }
      final result =
          await ref.read(favoritesProvider.notifier).importMerge(stations);
      final parts = <String>[
        if (result.added > 0)
          'Added ${result.added} station${result.added == 1 ? '' : 's'}',
        if (result.skipped > 0)
          'skipped ${result.skipped} duplicate${result.skipped == 1 ? '' : 's'}',
      ];
      messenger.showSnackBar(
        SnackBar(
          content: Text(parts.isEmpty ? 'Nothing to import' : parts.join(', ')),
        ),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('Import failed: $e')),
      );
    }
  }

  Future<void> _exportFavorites() async {
    final messenger = ScaffoldMessenger.of(context);
    final favorites = ref.read(favoritesProvider);
    if (favorites.isEmpty) return;
    try {
      final path = await FavoritesIoService().exportToFile(favorites);
      if (path == null) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text(
              'Exported ${favorites.length} station${favorites.length == 1 ? '' : 's'}'),
        ),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('Export failed: $e')),
      );
    }
  }

  void _showClearDialog() {
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

class _TagChip extends StatelessWidget {
  final String label;
  final bool selected;
  final bool isClearAction;
  final VoidCallback onTap;
  const _TagChip({
    required this.label,
    required this.selected,
    required this.onTap,
    this.isClearAction = false,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      shape: const StadiumBorder(),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
          decoration: ShapeDecoration(
            shape: const StadiumBorder(),
            color: selected
                ? AppColors.accent
                : isClearAction
                    ? AppColors.live.withValues(alpha: 0.18)
                    : AppColors.surface(0.05),
          ),
          child: Text(
            label,
            style: AppTypography.body(12,
                weight: selected ? FontWeight.w500 : FontWeight.w400,
                color: selected
                    ? const Color(0xFF0A0A0A)
                    : isClearAction
                        ? AppColors.live
                        : AppColors.onBgMuted(0.75)),
          ),
        ),
      ),
    );
  }
}

class _AddCustomStreamDialog extends StatefulWidget {
  final void Function(RadioStation) onSubmit;
  const _AddCustomStreamDialog({required this.onSubmit});

  @override
  State<_AddCustomStreamDialog> createState() => _AddCustomStreamDialogState();
}

class _AddCustomStreamDialogState extends State<_AddCustomStreamDialog> {
  final _nameController = TextEditingController();
  final _urlController = TextEditingController();
  String? _urlError;

  @override
  void dispose() {
    _nameController.dispose();
    _urlController.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _nameController.text.trim();
    final url = _urlController.text.trim();
    if (name.isEmpty || url.isEmpty) {
      Navigator.pop(context);
      return;
    }

    final parsed = Uri.tryParse(url);
    final isValid = parsed != null &&
        parsed.hasScheme &&
        (parsed.isScheme('http') || parsed.isScheme('https')) &&
        parsed.host.isNotEmpty;
    if (!isValid) {
      setState(() => _urlError = 'Enter a valid http:// or https:// URL');
      return;
    }

    final station = RadioStation(
      stationuuid: 'custom-${DateTime.now().millisecondsSinceEpoch}',
      name: name,
      url: url,
    );
    widget.onSubmit(station);
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add Custom Stream'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _nameController,
            decoration: const InputDecoration(
              labelText: 'Name',
              hintText: 'My Station',
            ),
            autofocus: true,
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _urlController,
            decoration: InputDecoration(
              labelText: 'Stream URL',
              hintText: 'https://example.com/stream',
              errorText: _urlError,
            ),
            keyboardType: TextInputType.url,
            textInputAction: TextInputAction.done,
            onChanged: (_) {
              if (_urlError != null) setState(() => _urlError = null);
            },
            onSubmitted: (_) => _submit(),
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
          onPressed: _submit,
          child: const Text('Add'),
        ),
      ],
    );
  }
}
