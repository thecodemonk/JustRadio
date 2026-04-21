import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/theme/app_theme.dart';
import '../../data/services/unsplash_service.dart';
import '../../providers/unsplash_provider.dart';

class PhotoCreditsScreen extends ConsumerWidget {
  const PhotoCreditsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final photos = ref.watch(cachedGenrePhotosProvider);

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, size: 20),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text('Photo Credits',
            style: AppTypography.body(15, color: AppColors.onBg)),
      ),
      body: SafeArea(
        child: photos.isEmpty
            ? Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.photo_library_outlined,
                        size: 48,
                        color: AppColors.accentGlow(0.5)),
                    const SizedBox(height: 12),
                    Text('No cached photos yet',
                        style: AppTypography.display(22)),
                    const SizedBox(height: 6),
                    Text(
                      'Browse the Genres tab with Unsplash configured\nto populate credits here.',
                      style: AppTypography.body(13,
                          color: AppColors.onBgMuted(0.55)),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              )
            : ListView.builder(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                itemCount: photos.length,
                itemBuilder: (context, index) {
                  final p = photos[index];
                  return Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    decoration: BoxDecoration(
                      color: AppColors.surface(0.03),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: AppColors.border(0.06)),
                    ),
                    child: Material(
                      color: Colors.transparent,
                      borderRadius: BorderRadius.circular(10),
                      child: InkWell(
                        onTap: p.photoPageUrl.isEmpty
                            ? null
                            : () {
                                launchUrl(
                                  Uri.parse(UnsplashService.attributedLink(
                                      p.photoPageUrl)),
                                  mode: LaunchMode.externalApplication,
                                );
                              },
                        borderRadius: BorderRadius.circular(10),
                        child: Padding(
                          padding: const EdgeInsets.all(10),
                          child: Row(
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(6),
                                child: SizedBox(
                                  width: 56,
                                  height: 56,
                                  child: CachedNetworkImage(
                                    imageUrl: p.imageUrl,
                                    fit: BoxFit.cover,
                                    errorWidget: (_, __, ___) => Container(
                                      color: AppColors.surface(0.06),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      _capitalize(p.genre),
                                      style: AppTypography.body(14,
                                          color: AppColors.onBgStrong),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      'Photo by ${p.photographerName} on Unsplash',
                                      style: AppTypography.body(11,
                                          color: AppColors.onBgMuted(0.55)),
                                    ),
                                  ],
                                ),
                              ),
                              if (p.photoPageUrl.isNotEmpty)
                                Icon(Icons.open_in_new,
                                    size: 14,
                                    color: AppColors.onBgMuted(0.4)),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
      ),
    );
  }

  String _capitalize(String s) {
    if (s.isEmpty) return s;
    return s[0].toUpperCase() + s.substring(1);
  }
}
