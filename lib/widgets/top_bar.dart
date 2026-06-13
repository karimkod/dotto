import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'bouncy_button.dart';

/// A rounded-square tile with a thick dark outline, matching the level cards.
class BorderedTile extends StatelessWidget {
  const BorderedTile({
    super.key,
    required this.child,
    this.onTap,
    this.background,
    this.height = 46,
    this.width,
    this.padding,
  });

  final Widget child;
  final VoidCallback? onTap;
  final Color? background;
  final double height;
  final double? width;
  final EdgeInsets? padding;

  @override
  Widget build(BuildContext context) {
    final dark = background == AppColors.ink;
    return BouncyButton(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      rippleColor: dark ? Colors.white : AppColors.coral,
      child: Container(
        height: height,
        width: width,
        padding: padding,
        decoration: BoxDecoration(
          color: background ?? AppColors.card,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.ink, width: 3),
        ),
        child: Center(child: child),
      ),
    );
  }
}

/// Top bar: profile (warm tint), crown hint counter (dark), settings (dark) —
/// all with thick rounded outlines.
class TopBar extends StatelessWidget {
  const TopBar({
    super.key,
    required this.hintCount,
    this.onProfile,
    this.onHints,
    this.onSettings,
  });

  final int hintCount;
  final VoidCallback? onProfile;
  final VoidCallback? onHints;
  final VoidCallback? onSettings;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        // Profile — orange tint, dark person silhouette.
        BorderedTile(
          background: AppColors.accent.withValues(alpha: 0.30),
          width: 46,
          onTap: onProfile,
          child: const Icon(Icons.person_rounded, color: AppColors.ink, size: 24),
        ),
        const SizedBox(width: 10),
        // Crown + count — dark background.
        BorderedTile(
          background: AppColors.ink,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          onTap: onHints,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('👑', style: TextStyle(fontSize: 18)),
              const SizedBox(width: 6),
              Text(
                'x$hintCount',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
        const Spacer(),
        // Settings — dark background, white gear.
        BorderedTile(
          background: AppColors.ink,
          width: 46,
          onTap: onSettings,
          child: const Icon(Icons.settings_rounded, color: Colors.white, size: 22),
        ),
      ],
    );
  }
}
