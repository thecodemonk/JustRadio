import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/app_theme.dart';
import '../../providers/lastfm_provider.dart';
import '../../providers/unsplash_provider.dart';
import 'lastfm_settings.dart';
import 'unsplash_settings.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lastfmState = ref.watch(lastfmStateProvider);
    final unsplashKey = ref.watch(unsplashKeyProvider);
    final unsplashConfigured = unsplashKey != null && unsplashKey.isNotEmpty;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 140),
          children: [
            Text('PREFERENCES',
                style: AppTypography.label(10, letterSpacing: 2)),
            const SizedBox(height: 6),
            Text('Settings', style: AppTypography.display(38)),
            const SizedBox(height: 28),
            _SettingsSection(
              title: 'Connections',
              children: [
                _SettingRow(
                  icon: Icons.music_note,
                  title: 'Last.fm Scrobbling',
                  subtitle: lastfmState.isAuthenticated
                      ? 'Connected as ${lastfmState.username}'
                      : 'Tap to connect your account',
                  trailing: lastfmState.isAuthenticated
                      ? Icon(Icons.check_circle,
                          size: 18, color: AppColors.accent)
                      : Icon(Icons.chevron_right,
                          size: 18, color: AppColors.onBgMuted(0.4)),
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (context) => const LastfmSettingsScreen(),
                      ),
                    );
                  },
                ),
                _SettingRow(
                  icon: Icons.image_outlined,
                  title: 'Unsplash backdrops',
                  subtitle: unsplashConfigured
                      ? 'Genre tiles fetch photos from Unsplash'
                      : 'Add a key to enable photo backdrops',
                  trailing: unsplashConfigured
                      ? Icon(Icons.check_circle,
                          size: 18, color: AppColors.accent)
                      : Icon(Icons.chevron_right,
                          size: 18, color: AppColors.onBgMuted(0.4)),
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (context) => const UnsplashSettingsScreen(),
                      ),
                    );
                  },
                ),
              ],
            ),
            const SizedBox(height: 24),
            _SettingsSection(
              title: 'About',
              children: [
                _SettingRow(
                  icon: Icons.info_outline,
                  title: 'About JustRadio',
                  subtitle: 'Version 1.0.0',
                  onTap: () {
                    showAboutDialog(
                      context: context,
                      applicationName: 'JustRadio',
                      applicationVersion: '1.0.0',
                      applicationLegalese: '© 2026',
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
                _SettingRow(
                  icon: Icons.public,
                  title: 'Powered by Radio Browser',
                  subtitle: 'Community radio station database',
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SettingsSection extends StatelessWidget {
  final String title;
  final List<Widget> children;
  const _SettingsSection({required this.title, required this.children});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 10),
          child: Text(
            title.toUpperCase(),
            style: AppTypography.mono(10,
                color: AppColors.onBgMuted(0.45), letterSpacing: 1.8),
          ),
        ),
        Container(
          decoration: BoxDecoration(
            color: AppColors.surface(0.03),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.border(0.06)),
          ),
          child: Column(children: children),
        ),
      ],
    );
  }
}

class _SettingRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;

  const _SettingRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.trailing,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(color: AppColors.border(0.04)),
            ),
          ),
          child: Row(
            children: [
              Icon(icon, size: 18, color: AppColors.accent),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: AppTypography.body(14,
                            color: AppColors.onBgStrong)),
                    const SizedBox(height: 2),
                    Text(subtitle,
                        style: AppTypography.body(12,
                            color: AppColors.onBgMuted(0.55))),
                  ],
                ),
              ),
              if (trailing != null) trailing!,
            ],
          ),
        ),
      ),
    );
  }
}
