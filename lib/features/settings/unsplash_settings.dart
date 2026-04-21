import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/theme/app_theme.dart';
import '../../providers/unsplash_provider.dart';
import 'photo_credits_screen.dart';

class UnsplashSettingsScreen extends ConsumerStatefulWidget {
  const UnsplashSettingsScreen({super.key});

  @override
  ConsumerState<UnsplashSettingsScreen> createState() =>
      _UnsplashSettingsScreenState();
}

class _UnsplashSettingsScreenState
    extends ConsumerState<UnsplashSettingsScreen> {
  late final TextEditingController _controller;
  bool _obscure = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(
      text: ref.read(unsplashKeyProvider) ?? '',
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final value = _controller.text.trim();
    if (value.isEmpty) return;
    setState(() => _saving = true);
    await ref.read(unsplashKeyProvider.notifier).save(value);
    if (!mounted) return;
    setState(() => _saving = false);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Unsplash access key saved')),
    );
  }

  Future<void> _clear() async {
    await ref.read(unsplashKeyProvider.notifier).clear();
    _controller.clear();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Unsplash access key cleared')),
    );
  }

  Future<void> _openDeveloperPortal() async {
    await launchUrl(
      Uri.parse('https://unsplash.com/developers'),
      mode: LaunchMode.externalApplication,
    );
  }

  @override
  Widget build(BuildContext context) {
    final currentKey = ref.watch(unsplashKeyProvider);
    final isConfigured = currentKey != null && currentKey.isNotEmpty;

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, size: 20),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title:
            Text('Unsplash', style: AppTypography.body(15, color: AppColors.onBg)),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 4, 24, 32),
          children: [
            Text('IMAGE BACKDROPS',
                style: AppTypography.label(10, letterSpacing: 2)),
            const SizedBox(height: 6),
            Text('Unsplash key', style: AppTypography.display(32)),
            const SizedBox(height: 18),
            Text(
              'Genre tiles can show a photo backdrop fetched from Unsplash. '
              'To enable, paste a free Access Key from your own Unsplash '
              'developer account. JustRadio caches each image locally so '
              'you only fetch each genre once.',
              style: AppTypography.body(13, color: AppColors.onBgMuted(0.7)),
            ),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.surface(0.03),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.border(0.06)),
              ),
              child: Row(
                children: [
                  Icon(
                    isConfigured
                        ? Icons.check_circle
                        : Icons.radio_button_unchecked,
                    size: 18,
                    color: isConfigured
                        ? AppColors.accent
                        : AppColors.onBgMuted(0.5),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      isConfigured
                          ? 'Configured — tiles will fetch from Unsplash'
                          : 'Not configured — tiles use a gradient fallback',
                      style: AppTypography.body(13,
                          color: AppColors.onBgStrong),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: _controller,
              obscureText: _obscure,
              decoration: InputDecoration(
                labelText: 'Access Key',
                hintText: 'Paste your Unsplash Access Key',
                suffixIcon: IconButton(
                  icon: Icon(
                    _obscure ? Icons.visibility : Icons.visibility_off,
                    size: 18,
                    color: AppColors.onBgMuted(0.55),
                  ),
                  onPressed: () => setState(() => _obscure = !_obscure),
                ),
              ),
              style: AppTypography.mono(13, color: AppColors.onBg,
                  letterSpacing: 0.5),
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _save(),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: FilledButton(
                    onPressed: _saving ? null : _save,
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.accent,
                      foregroundColor: const Color(0xFF0A0A0A),
                      padding:
                          const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: _saving
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor:
                                  AlwaysStoppedAnimation(Color(0xFF0A0A0A)),
                            ),
                          )
                        : const Text('Save'),
                  ),
                ),
                const SizedBox(width: 10),
                if (isConfigured)
                  TextButton(
                    onPressed: _clear,
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 14),
                      foregroundColor: AppColors.live,
                    ),
                    child: const Text('Clear'),
                  ),
              ],
            ),
            const SizedBox(height: 22),
            Material(
              color: Colors.transparent,
              borderRadius: BorderRadius.circular(10),
              child: InkWell(
                onTap: _openDeveloperPortal,
                borderRadius: BorderRadius.circular(10),
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppColors.surface(0.03),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppColors.border(0.06)),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.open_in_new,
                          size: 16, color: AppColors.accent),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Get a free Access Key',
                                style: AppTypography.body(13,
                                    color: AppColors.onBgStrong)),
                            const SizedBox(height: 2),
                            Text(
                              'Register at unsplash.com/developers — takes ~2 min',
                              style: AppTypography.body(11,
                                  color: AppColors.onBgMuted(0.55)),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 10),
            Material(
              color: Colors.transparent,
              borderRadius: BorderRadius.circular(10),
              child: InkWell(
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const PhotoCreditsScreen(),
                    ),
                  );
                },
                borderRadius: BorderRadius.circular(10),
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppColors.surface(0.03),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppColors.border(0.06)),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.photo_library_outlined,
                          size: 16, color: AppColors.accent),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text('Photo credits',
                            style: AppTypography.body(13,
                                color: AppColors.onBgStrong)),
                      ),
                      Icon(Icons.chevron_right,
                          size: 18, color: AppColors.onBgMuted(0.4)),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 32),
            Text(
              'Images are attributed to their photographers per Unsplash\'s '
              'licensing terms. Your key is stored locally on this device.',
              style: AppTypography.body(11,
                  color: AppColors.onBgMuted(0.45)),
            ),
          ],
        ),
      ),
    );
  }
}
