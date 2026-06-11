import 'package:flutter/material.dart';

import '../models/level.dart';
import '../theme/app_theme.dart';

/// Placeholder game screen. The real puzzle board (ported from the prototype)
/// will live here later.
class GameScreen extends StatelessWidget {
  const GameScreen({super.key, required this.level});

  final Level level;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        foregroundColor: AppColors.text,
        title: Text(
          'Level ${level.number}',
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.bubble_chart_rounded,
                size: 88, color: AppColors.accent),
            const SizedBox(height: 20),
            Text(
              'Level ${level.number}',
              style: const TextStyle(
                fontSize: 30,
                fontWeight: FontWeight.w800,
                color: AppColors.text,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              level.title,
              style: const TextStyle(
                fontSize: 16,
                color: AppColors.textSoft,
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'Coming soon',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: AppColors.textSoft,
                letterSpacing: 1,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
