import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// A rounded-square icon container with a soft shadow, used across the top bar.
class IconButtonTile extends StatelessWidget {
  const IconButtonTile({
    super.key,
    required this.icon,
    this.onTap,
    this.tint,
    this.iconColor,
    this.badgeCount,
    this.size = 46,
  });

  final IconData icon;
  final VoidCallback? onTap;

  /// Background tint. Defaults to white.
  final Color? tint;
  final Color? iconColor;

  /// Optional count badge (e.g. hint count). Null hides it.
  final int? badgeCount;
  final double size;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              color: tint ?? AppColors.card,
              borderRadius: BorderRadius.circular(14),
              boxShadow: AppTheme.softShadow(y: 3, blur: 8),
            ),
            child: Icon(
              icon,
              size: size * 0.5,
              color: iconColor ?? AppColors.text,
            ),
          ),
          if (badgeCount != null)
            Positioned(
              right: -4,
              top: -4,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                constraints: const BoxConstraints(minWidth: 20),
                decoration: BoxDecoration(
                  color: AppColors.coral,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '$badgeCount',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Top bar: profile (left), hint counter (center-left), settings (right).
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
        IconButtonTile(
          icon: Icons.person_rounded,
          tint: AppColors.accent.withValues(alpha: 0.18),
          iconColor: AppColors.accent,
          onTap: onProfile,
        ),
        const SizedBox(width: 10),
        IconButtonTile(
          icon: Icons.lightbulb_rounded,
          iconColor: AppColors.accent,
          badgeCount: hintCount,
          onTap: onHints,
        ),
        const Spacer(),
        IconButtonTile(
          icon: Icons.settings_rounded,
          iconColor: AppColors.textSoft,
          onTap: onSettings,
        ),
      ],
    );
  }
}
