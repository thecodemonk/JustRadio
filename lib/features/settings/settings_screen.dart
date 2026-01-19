import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/lastfm_provider.dart';
import 'lastfm_settings.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lastfmState = ref.watch(lastfmStateProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
      ),
      body: ListView(
        children: [
          // Last.fm Section
          _buildSectionHeader(context, 'Last.fm'),
          ListTile(
            leading: const Icon(Icons.music_note),
            title: const Text('Last.fm Scrobbling'),
            subtitle: Text(
              lastfmState.isAuthenticated
                  ? 'Connected as ${lastfmState.username}'
                  : lastfmState.hasCredentials
                      ? 'Not connected'
                      : 'Configure API credentials',
            ),
            trailing: lastfmState.isAuthenticated
                ? Icon(
                    Icons.check_circle,
                    color: Theme.of(context).colorScheme.primary,
                  )
                : const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (context) => const LastfmSettingsScreen(),
                ),
              );
            },
          ),

          const Divider(),

          // About Section
          _buildSectionHeader(context, 'About'),
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: const Text('About JustRadio'),
            subtitle: const Text('Version 1.0.0'),
            onTap: () {
              showAboutDialog(
                context: context,
                applicationName: 'JustRadio',
                applicationVersion: '1.0.0',
                applicationLegalese: '© 2024',
                children: [
                  const SizedBox(height: 16),
                  const Text(
                    'A cross-platform streaming radio app with '
                    'Radio Browser integration and Last.fm scrobbling.',
                  ),
                ],
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.api),
            title: const Text('Powered by Radio Browser'),
            subtitle: const Text('Community radio station database'),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(BuildContext context, String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Text(
        title,
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: Theme.of(context).colorScheme.primary,
            ),
      ),
    );
  }
}
