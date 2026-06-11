import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Unlock/progress state of a single level.
enum LevelStatus { locked, unlocked, completed }

/// How hard a level is — drives the badge above the play button.
enum Difficulty { easy, medium, hard }

extension DifficultyLabel on Difficulty {
  String get label {
    switch (this) {
      case Difficulty.easy:
        return 'Easy';
      case Difficulty.medium:
        return 'Medium';
      case Difficulty.hard:
        return 'Hard';
    }
  }

  Color get color {
    switch (this) {
      case Difficulty.easy:
        return const Color(0xFF81C784); // green (prototype --start)
      case Difficulty.medium:
        return AppColors.accent;
      case Difficulty.hard:
        return AppColors.coral;
    }
  }
}

/// A single playable level in the path.
class Level {
  const Level({
    required this.id,
    required this.number,
    required this.title,
    required this.difficulty,
    this.status = LevelStatus.locked,
  });

  final int id;
  final int number;
  final String title;
  final Difficulty difficulty;
  final LevelStatus status;

  bool get isLocked => status == LevelStatus.locked;
  bool get isCompleted => status == LevelStatus.completed;
  bool get isUnlocked => status == LevelStatus.unlocked;

  Level copyWith({LevelStatus? status}) => Level(
        id: id,
        number: number,
        title: title,
        difficulty: difficulty,
        status: status ?? this.status,
      );
}
