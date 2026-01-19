import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/lastfm_provider.dart';

class LastfmSettingsScreen extends ConsumerStatefulWidget {
  const LastfmSettingsScreen({super.key});

  @override
  ConsumerState<LastfmSettingsScreen> createState() =>
      _LastfmSettingsScreenState();
}

class _LastfmSettingsScreenState extends ConsumerState<LastfmSettingsScreen> {
  final _apiKeyController = TextEditingController();
  final _apiSecretController = TextEditingController();
  final _tokenController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadExistingCredentials();
  }

  void _loadExistingCredentials() {
    final service = ref.read(lastfmAuthServiceProvider);
    _apiKeyController.text = service.apiKey ?? '';
    _apiSecretController.text = service.apiSecret ?? '';
  }

  @override
  void dispose() {
    _apiKeyController.dispose();
    _apiSecretController.dispose();
    _tokenController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(lastfmStateProvider);
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Last.fm Settings'),
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
                          state.isAuthenticated
                              ? 'Connected'
                              : 'Not Connected',
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
                      child: const Text('Logout'),
                    ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 24),

          // API Credentials section
          Text(
            'API Credentials',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Text(
            'Get your API key and secret from last.fm/api/account/create',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: 16),

          TextField(
            controller: _apiKeyController,
            decoration: const InputDecoration(
              labelText: 'API Key',
              hintText: 'Enter your Last.fm API key',
            ),
            enabled: !state.isAuthenticated,
          ),
          const SizedBox(height: 12),

          TextField(
            controller: _apiSecretController,
            decoration: const InputDecoration(
              labelText: 'API Secret',
              hintText: 'Enter your Last.fm API secret',
            ),
            obscureText: true,
            enabled: !state.isAuthenticated,
          ),
          const SizedBox(height: 16),

          if (!state.isAuthenticated)
            FilledButton(
              onPressed: state.isLoading ? null : _saveCredentials,
              child: state.isLoading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Save Credentials'),
            ),

          if (state.hasCredentials && !state.isAuthenticated) ...[
            const SizedBox(height: 32),
            const Divider(),
            const SizedBox(height: 16),

            Text(
              'Authentication',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              'After clicking "Authorize", you will be redirected to Last.fm. '
              'After authorizing, copy the token from the URL and paste it below.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
            ),
            const SizedBox(height: 16),

            OutlinedButton.icon(
              onPressed: state.isLoading
                  ? null
                  : () {
                      ref.read(lastfmStateProvider.notifier).startAuth();
                    },
              icon: const Icon(Icons.open_in_new),
              label: const Text('Authorize with Last.fm'),
            ),
            const SizedBox(height: 16),

            TextField(
              controller: _tokenController,
              decoration: const InputDecoration(
                labelText: 'Token',
                hintText: 'Paste the token from the URL',
              ),
            ),
            const SizedBox(height: 16),

            FilledButton(
              onPressed: state.isLoading ? null : _completeAuth,
              child: state.isLoading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Complete Authentication'),
            ),
          ],

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

          if (state.isAuthenticated) ...[
            const SizedBox(height: 32),
            const Divider(),
            const SizedBox(height: 16),

            Text(
              'Scrobbling Info',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              'Tracks will be scrobbled when:\n'
              '• The track plays for at least 30 seconds\n'
              '• AND either 50% of the track duration has passed OR 4 minutes have elapsed',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
            ),

            const SizedBox(height: 24),

            OutlinedButton(
              onPressed: () {
                ref.read(lastfmStateProvider.notifier).clearAll();
                _apiKeyController.clear();
                _apiSecretController.clear();
                _tokenController.clear();
              },
              style: OutlinedButton.styleFrom(
                foregroundColor: colorScheme.error,
              ),
              child: const Text('Clear All Settings'),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _saveCredentials() async {
    final apiKey = _apiKeyController.text.trim();
    final apiSecret = _apiSecretController.text.trim();

    if (apiKey.isEmpty || apiSecret.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter both API key and secret'),
        ),
      );
      return;
    }

    await ref.read(lastfmStateProvider.notifier).saveCredentials(
          apiKey: apiKey,
          apiSecret: apiSecret,
        );

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Credentials saved')),
      );
    }
  }

  Future<void> _completeAuth() async {
    final token = _tokenController.text.trim();

    if (token.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter the token')),
      );
      return;
    }

    final success =
        await ref.read(lastfmStateProvider.notifier).completeAuth(token);

    if (mounted) {
      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Successfully authenticated!')),
        );
        _tokenController.clear();
      }
    }
  }
}
