import 'package:flutter/material.dart';

import '../models/level.dart';
import '../theme/app_theme.dart';

/// A rounded-square node on the level path, "boardgame" styled with a thick
/// dark outline (no shadow). Renders differently for locked, unlocked, current
/// and completed states.
class LevelCard extends StatelessWidget {
  const LevelCard({
    super.key,
    required this.level,
    required this.isCurrent,
    this.onTap,
  });

  final Level level;

  /// The next playable level gets a coral outline + slightly larger size.
  final bool isCurrent;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    const baseSize = 76.0;
    final size = isCurrent ? baseSize + 8 : baseSize;

    final Color background;
    final Color borderColor;

    if (level.isLocked) {
      background = const Color(0xFFEDEBE7); // grayed cream
      borderColor = AppColors.locked.withValues(alpha: 0.55);
    } else if (isCurrent) {
      background = AppColors.card;
      borderColor = AppColors.coral;
    } else {
      background = AppColors.card;
      borderColor = AppColors.ink;
    }

    return GestureDetector(
      onTap: level.isLocked ? null : onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: borderColor, width: 3),
        ),
        child: Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.center,
          children: [
            Center(child: _buildContent()),
            // Small check badge in the top-right corner for completed levels —
            // never overlaps the centered number.
            if (level.isCompleted)
              const Positioned(top: -8, right: -8, child: _CheckBadge()),
          ],
        ),
      ),
    );
  }

  Widget _buildContent() {
    if (level.isLocked) {
      return Icon(
        Icons.lock_outline_rounded,
        color: AppColors.locked,
        size: 30,
      );
    }

    return Text(
      '${level.number}',
      style: TextStyle(
        fontSize: 28,
        fontWeight: FontWeight.w800,
        color: isCurrent ? AppColors.coral : AppColors.ink,
      ),
    );
  }
}

/// Small circular green check badge shown on completed level cards.
class _CheckBadge extends StatelessWidget {
  const _CheckBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 24,
      height: 24,
      decoration: BoxDecoration(
        color: AppColors.completed,
        shape: BoxShape.circle,
        border: Border.all(color: AppColors.card, width: 2),
      ),
      child: const Icon(Icons.check_rounded, color: Colors.white, size: 15),
    );
  }
}
