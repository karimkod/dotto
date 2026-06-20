import '../models/level.dart';
import '../progress/progress_store.dart';
import 'level_definitions.dart';

/// Total number of built, playable levels:
/// World 1 (1–15) + World 2 (16–20) + World 3 (21–30).
const int kLevelCount = 30;

/// The level number at which World 2 (Static Destroyers) begins.
const int kWorld2Start = 16;

/// The level number at which World 3 (Shields & Explosions) begins.
const int kWorld3Start = 21;

/// Hardcoded menu level list — World 1 (1–15), World 2 (16–20), World 3 (21–30).
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
    // World 2 (16–20).
    if (number <= 16) return Difficulty.easy;
    if (number <= 17) return Difficulty.medium;
    if (number <= 20) return Difficulty.hard;
    // World 3 (21–30).
    if (number <= 23) return Difficulty.easy; // learn shields (21–23)
    if (number <= 27) return Difficulty.medium; // path clearing (24–27)
    return Difficulty.hard; // challenge + finale (28–30)
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
