import '../models/level.dart';
import '../progress/progress_store.dart';
import 'level_definitions.dart';

/// Total number of built, playable levels:
/// World 1 (1–15) + World 2 (16–25) + World 3 (26–40).
const int kLevelCount = 40;

/// The level number at which World 2 (Static Destroyers) begins.
const int kWorld2Start = 16;

/// The level number at which World 3 (Shields & Explosions) begins.
const int kWorld3Start = 26;

/// Hardcoded menu level list — World 1 (1–15), World 2 (16–25), World 3 (26–40).
///
/// Progression is gated: level 1 is the completed baseline, and completing a
/// level unlocks the next one (persisted via [ProgressStore]).
List<Level> buildInitialLevels() {
  // Level 1 is always considered complete (the "press Play" intro).
  final completed = {1, ...ProgressStore.completed()};

  Difficulty difficultyFor(int number) {
    // World 1.
    if (number <= 4) return Difficulty.easy;
    if (number <= 7) return Difficulty.medium;
    if (number <= 15) return Difficulty.hard; // 8–15 (incl. exams 11–15)
    // World 2 (16–25).
    if (number <= 18) return Difficulty.easy; // learn (16–18)
    if (number <= 22) return Difficulty.medium; // combine (19–22)
    if (number <= 25) return Difficulty.hard; // challenge (23–25)
    // World 3 (26–40).
    if (number <= 28) return Difficulty.easy; // learn shields (26–28)
    if (number <= 32) return Difficulty.medium; // path clearing (29–32)
    return Difficulty.hard; // challenge + exams (33–40)
  }

  LevelStatus statusFor(int number) {
    if (completed.contains(number)) return LevelStatus.completed;
    // Testing: every level is unlocked (no progression gating for now).
    return LevelStatus.unlocked;
  }

  return List<Level>.generate(kLevelCount, (i) {
    final number = i + 1;
    final title = levelDataFor(number)?.title ?? 'Level $number';
    return Level(
      id: number,
      number: number,
      title: title,
      difficulty: difficultyFor(number),
      status: statusFor(number),
    );
  });
}
