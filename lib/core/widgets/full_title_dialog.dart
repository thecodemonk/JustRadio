import 'dart:async';

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Present the full track title in a centered, dimmed-backdrop card
/// that auto-dismisses after 5 seconds or on any tap. Used from both
/// the mobile PlayerScreen and the desktop Now Playing pane when the
/// user taps on a title that was marqueeing because it overflowed.
Future<void> showFullTitle(BuildContext context, String title) {
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Close',
    barrierColor: Colors.black.withValues(alpha: 0.72),
    transitionDuration: const Duration(milliseconds: 260),
    pageBuilder: (ctx, _, __) => _FullTitleDialog(title: title),
    transitionBuilder: (ctx, anim, _, child) {
      return FadeTransition(
        opacity: anim,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.94, end: 1.0).animate(
            CurvedAnimation(parent: anim, curve: Curves.easeOutCubic),
          ),
          child: child,
        ),
      );
    },
  );
}

class _FullTitleDialog extends StatefulWidget {
  final String title;
  const _FullTitleDialog({required this.title});

  @override
  State<_FullTitleDialog> createState() => _FullTitleDialogState();
}

class _FullTitleDialogState extends State<_FullTitleDialog> {
  Timer? _autoDismiss;

  @override
  void initState() {
    super.initState();
    _autoDismiss = Timer(const Duration(seconds: 5), () {
      if (mounted) Navigator.of(context).maybePop();
    });
  }

  @override
  void dispose() {
    _autoDismiss?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // showGeneralDialog doesn't wrap its pageBuilder in Material, so
    // Text widgets would otherwise get the yellow debug underline.
    return Material(
      type: MaterialType.transparency,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => Navigator.of(context).maybePop(),
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Container(
              constraints: const BoxConstraints(maxWidth: 560),
              padding: const EdgeInsets.fromLTRB(28, 28, 28, 28),
              decoration: BoxDecoration(
                color: AppColors.bgElevated.withValues(alpha: 0.96),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: AppColors.border(0.14)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.5),
                    blurRadius: 32,
                    offset: const Offset(0, 12),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'NOW PLAYING',
                    style: AppTypography.label(10, letterSpacing: 2).copyWith(
                      color: AppColors.accent,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    widget.title,
                    style: AppTypography.display(26),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
