import 'package:flutter/material.dart';

import '../models/level.dart';
import '../theme/app_theme.dart';

/// The fixed bottom call-to-action: a difficulty tag sitting on top of a big
/// coral pill that launches the current level. Boardgame-styled with thick
/// dark outlines.
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
    return GestureDetector(
      onTap: onPlay,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.topCenter,
        children: [
          // Big coral pill.
          Container(
            margin: const EdgeInsets.only(top: 14),
            height: 62,
            width: double.infinity,
            decoration: BoxDecoration(
              color: AppColors.coral,
              borderRadius: BorderRadius.circular(31),
              border: Border.all(color: AppColors.ink, width: 3),
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
          // Difficulty tag straddling the top edge of the pill.
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
            decoration: BoxDecoration(
              color: level.difficulty.color,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.ink, width: 2.5),
            ),
            child: Text(
              level.difficulty.label,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
                fontSize: 13,
                letterSpacing: 0.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
