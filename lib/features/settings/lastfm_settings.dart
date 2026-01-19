import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/lastfm_provider.dart';

class LastfmSettingsScreen extends ConsumerWidget {
  const LastfmSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(lastfmStateProvider);
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Last.fm Scrobbling'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Status card
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Icon(
                    state.isAuthenticated
                        ? Icons.check_circle
                        : Icons.radio_button_unchecked,
                    color: state.isAuthenticated
                        ? colorScheme.primary
                        : colorScheme.onSurfaceVariant,
                    size: 32,
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          state.isAuthenticated ? 'Connected' : 'Not Connected',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        if (state.isAuthenticated && state.username != null)
                          Text(
                            'Signed in as ${state.username}',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                      ],
                    ),
                  ),
                  if (state.isAuthenticated)
                    TextButton(
                      onPressed: () {
                        ref.read(lastfmStateProvider.notifier).logout();
                      },
                      child: const Text('Disconnect'),
                    ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 24),

          // Connect button or pending state
          if (!state.isAuthenticated && !state.hasPendingToken) ...[
            Text(
              'Connect your Last.fm account to scrobble tracks as you listen.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: state.isLoading
                  ? null
                  : () => ref.read(lastfmStateProvider.notifier).startAuth(),
              icon: state.isLoading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.link),
              label: const Text('Connect to Last.fm'),
            ),
          ],

          // Pending authorization
          if (state.hasPendingToken && !state.isAuthenticated) ...[
            Card(
              color: colorScheme.primaryContainer,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.open_in_browser,
                          color: colorScheme.onPrimaryContainer,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Authorization Pending',
                          style:
                              Theme.of(context).textTheme.titleMedium?.copyWith(
                                    color: colorScheme.onPrimaryContainer,
                                  ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'A browser window should have opened. Please authorize JustRadio on Last.fm, then return here and tap "Complete Authorization".',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: colorScheme.onPrimaryContainer,
                          ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: FilledButton(
                            onPressed: state.isLoading
                                ? null
                                : () => ref
                                    .read(lastfmStateProvider.notifier)
                                    .completeAuth(),
                            child: state.isLoading
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child:
                                        CircularProgressIndicator(strokeWidth: 2),
                                  )
                                : const Text('Complete Authorization'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        TextButton(
                          onPressed: () => ref
                              .read(lastfmStateProvider.notifier)
                              .cancelAuth(),
                          child: const Text('Cancel'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],

          // Error message
          if (state.error != null) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: colorScheme.errorContainer,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                state.error!,
                style: TextStyle(color: colorScheme.onErrorContainer),
              ),
            ),
          ],

          // Scrobbling info when connected
          if (state.isAuthenticated) ...[
            const SizedBox(height: 32),
            const Divider(),
            const SizedBox(height: 16),
            Text(
              'How Scrobbling Works',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              'Tracks will be scrobbled to your Last.fm profile when:\n'
              '• The track plays for at least 30 seconds\n'
              '• Either 50% of the track has played OR 4 minutes have elapsed\n\n'
              'Note: Not all radio streams provide track metadata. '
              'Scrobbling only works when the station broadcasts artist and title information.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
            ),
          ],
        ],
      ),
    );
  }
}
