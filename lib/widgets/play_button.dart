import 'package:flutter/material.dart';

import '../models/level.dart';
import '../theme/app_theme.dart';

/// The fixed bottom call-to-action: a difficulty badge above a big gradient
/// pill that launches the current level.
class PlayButton extends StatelessWidget {
  const PlayButton({
    super.key,
    required this.level,
    this.onPlay,
  });

  final Level level;
  final VoidCallback? onPlay;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Difficulty badge.
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
          decoration: BoxDecoration(
            color: level.difficulty.color.withValues(alpha: 0.16),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            level.difficulty.label,
            style: TextStyle(
              color: level.difficulty.color,
              fontWeight: FontWeight.w800,
              fontSize: 13,
              letterSpacing: 0.5,
            ),
          ),
        ),
        const SizedBox(height: 12),
        // Big gradient pill.
        GestureDetector(
          onTap: onPlay,
          child: Container(
            height: 62,
            width: double.infinity,
            decoration: BoxDecoration(
              gradient: AppColors.playGradient,
              borderRadius: BorderRadius.circular(31),
              boxShadow: [
                BoxShadow(
                  color: AppColors.coral.withValues(alpha: 0.40),
                  offset: const Offset(0, 6),
                  blurRadius: 16,
                ),
              ],
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  'Level ${level.number}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 19,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(width: 8),
                const Icon(Icons.play_arrow_rounded,
                    color: Colors.white, size: 28),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
