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

/// Top bar: profile (warm tint) and settings (dark), with thick rounded
/// outlines.
///
/// It used to carry a crown counter between the two. Hints are per-level and
/// granted on the level itself, so a number on the menu had nothing to count —
/// it showed a fixed 3 to everyone and did nothing when tapped.
class TopBar extends StatelessWidget {
  const TopBar({
    super.key,
    this.onProfile,
    this.onSettings,
  });

  final VoidCallback? onProfile;
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
