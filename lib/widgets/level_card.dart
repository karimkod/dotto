import 'package:flutter/material.dart';

import '../models/level.dart';
import '../theme/app_theme.dart';

/// A rounded-square node on the level path. Renders differently for locked,
/// unlocked, current and completed states.
class LevelCard extends StatelessWidget {
  const LevelCard({
    super.key,
    required this.level,
    required this.isCurrent,
    this.onTap,
  });

  final Level level;

  /// The next playable level gets a glow + slightly larger size.
  final bool isCurrent;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    const baseSize = 80.0;
    final size = isCurrent ? baseSize + 8 : baseSize;

    final Color background;
    final Color borderColor;
    final double borderWidth;

    if (level.isLocked) {
      background = AppColors.locked.withValues(alpha: 0.12);
      borderColor = AppColors.locked.withValues(alpha: 0.35);
      borderWidth = 1.5;
    } else if (isCurrent) {
      background = AppColors.card;
      borderColor = AppColors.coral;
      borderWidth = 3;
    } else {
      background = AppColors.card;
      borderColor = AppColors.border;
      borderWidth = 1.5;
    }

    return GestureDetector(
      onTap: level.isLocked ? null : onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: borderColor, width: borderWidth),
          boxShadow: [
            ...AppTheme.softShadow(y: 4, blur: 12),
            if (isCurrent)
              BoxShadow(
                color: AppColors.coral.withValues(alpha: 0.35),
                blurRadius: 20,
                spreadRadius: 1,
              ),
          ],
        ),
        child: Center(child: _buildContent()),
      ),
    );
  }

  Widget _buildContent() {
    if (level.isLocked) {
      return Icon(
        Icons.lock_rounded,
        color: AppColors.locked,
        size: 30,
      );
    }

    final number = Text(
      '${level.number}',
      style: TextStyle(
        fontSize: 28,
        fontWeight: FontWeight.w800,
        color: isCurrent ? AppColors.coral : AppColors.text,
      ),
    );

    if (level.isCompleted) {
      return Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          number,
          Positioned(
            top: -10,
            right: -10,
            child: Icon(Icons.star_rounded, color: AppColors.star, size: 26),
          ),
        ],
      );
    }

    return number;
  }
}
