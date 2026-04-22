import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/models/genre_photo.dart';
import '../../../data/repositories/radio_browser_repository.dart';
import '../../../data/services/unsplash_service.dart';
import '../../../providers/audio_player_provider.dart';
import '../../../providers/unsplash_provider.dart';
import '../../search/search_provider.dart';
import 'procedural_genre_art.dart';
import 'stations_by_tag_screen.dart';

class GenresTab extends ConsumerWidget {
  const GenresTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tagsAsync = ref.watch(tagsProvider);

    // Mirror the genre list into the native library store so Android Auto /
    // CarPlay can browse genres cold. Fires once per successful load.
    ref.listen(tagsProvider, (_, next) {
      next.whenData((list) {
        ref
            .read(audioPlayerServiceProvider)
            .syncGenres(list.map((t) => t.name).toList());
      });
    });

    return tagsAsync.when(
      data: (tags) {
        if (tags.isEmpty) {
          return Center(
            child: Text(
              'No genres available',
              style: AppTypography.body(14, color: AppColors.onBgMuted(0.6)),
            ),
          );
        }
        return RefreshIndicator(
          color: AppColors.accent,
          backgroundColor: AppColors.bgElevated,
          onRefresh: () async => ref.invalidate(tagsProvider),
          child: GridView.builder(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 140),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              crossAxisSpacing: 10,
              mainAxisSpacing: 10,
              childAspectRatio: 2.0,
            ),
            itemCount: tags.length,
            itemBuilder: (context, index) {
              return _GenreTile(tag: tags[index]);
            },
          ),
        );
      },
      loading: () => const Center(
        child: SizedBox(
          width: 28,
          height: 28,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            valueColor: AlwaysStoppedAnimation(AppColors.accent),
          ),
        ),
      ),
      error: (e, s) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline,
                  size: 40, color: AppColors.onBgMuted(0.6)),
              const SizedBox(height: 12),
              Text(
                'Failed to load genres',
                style: AppTypography.display(22),
              ),
              const SizedBox(height: 8),
              Text(
                e.toString(),
                style: AppTypography.body(12,
                    color: AppColors.onBgMuted(0.55)),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.accent,
                  foregroundColor: const Color(0xFF0A0A0A),
                ),
                onPressed: () => ref.invalidate(tagsProvider),
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GenreTile extends ConsumerWidget {
  final Tag tag;
  const _GenreTile({required this.tag});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final photoAsync = ref.watch(genrePhotoProvider(tag.name));

    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => StationsByTagScreen(tag: tag),
            ),
          );
        },
        child: ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: Stack(
            children: [
              // Base: rich procedural art — layered blobs, icon silhouette,
              // grain. Renders instantly, stands on its own without photo.
              Positioned.fill(
                child: ProceduralGenreArt(tagName: tag.name),
              ),
              // Photo backdrop: fades in once resolved (only when Unsplash key set)
              if (photoAsync.hasValue && photoAsync.value != null)
                Positioned.fill(
                  child: _PhotoBackdrop(photo: photoAsync.value!),
                ),
              // Text + credit overlay
              Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.transparent,
                      Color(0xAA000000),
                    ],
                    stops: [0.35, 1.0],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Text(
                      _capitalize(tag.name),
                      style: AppTypography.display(24),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${tag.stationCount} stations',
                      style: AppTypography.mono(10,
                          color: Colors.white.withValues(alpha: 0.7),
                          letterSpacing: 0.5),
                    ),
                  ],
                ),
              ),
              if (photoAsync.hasValue && photoAsync.value != null)
                Positioned(
                  right: 8,
                  top: 8,
                  child: _PhotoCredit(photo: photoAsync.value!),
                ),
            ],
          ),
        ),
      ),
    );
  }

  String _capitalize(String s) {
    if (s.isEmpty) return s;
    return s[0].toUpperCase() + s.substring(1);
  }
}

class _PhotoBackdrop extends StatelessWidget {
  final GenrePhoto photo;
  const _PhotoBackdrop({required this.photo});

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.0, end: 1.0),
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeOut,
      builder: (_, t, child) => Opacity(opacity: t, child: child),
      child: Stack(
        fit: StackFit.expand,
        children: [
          CachedNetworkImage(
            imageUrl: photo.imageUrl,
            fit: BoxFit.cover,
            fadeInDuration: Duration.zero,
            placeholder: (_, __) => const SizedBox.shrink(),
            errorWidget: (_, __, ___) => const SizedBox.shrink(),
          ),
          // Darken + desaturate-ish overlay so the genre type stays legible
          DecoratedBox(
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.32),
            ),
          ),
        ],
      ),
    );
  }
}

class _PhotoCredit extends StatelessWidget {
  final GenrePhoto photo;
  const _PhotoCredit({required this.photo});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      shape: const StadiumBorder(),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: photo.photographerUrl.isEmpty
            ? null
            : () {
                launchUrl(
                  Uri.parse(
                      UnsplashService.attributedLink(photo.photographerUrl)),
                  mode: LaunchMode.externalApplication,
                );
              },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
          decoration: ShapeDecoration(
            shape: const StadiumBorder(),
            color: Colors.black.withValues(alpha: 0.45),
          ),
          child: Text(
            'by ${photo.photographerName}',
            style: AppTypography.mono(8,
                color: Colors.white.withValues(alpha: 0.75),
                letterSpacing: 0.3),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ),
    );
  }
}
