import '../models/level.dart';
import '../progress/progress_store.dart';
import 'level_definitions.dart';

/// Total number of built, playable levels:
/// World 1 (1–15) + World 2 (16–20) + World 3 (21–30) + World 4 (31–46).
const int kLevelCount = 46;

/// The level number at which World 2 (Static Destroyers) begins.
const int kWorld2Start = 16;

/// The level number at which World 3 (Shields & Explosions) begins.
const int kWorld3Start = 21;

/// The level number at which World 4 (Moving Destroyers + Pause) begins.
const int kWorld4Start = 31;

/// Hardcoded menu level list — World 1 (1–15), World 2 (16–20), World 3 (21–30),
/// World 4 (31–46).
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
    if (number <= 30) return Difficulty.hard; // challenge + finale (28–30)
    // World 4 (31–46).
    if (number <= 34) return Difficulty.easy; // moving destroyers intro (31–34)
    if (number <= 42) return Difficulty.medium; // shield chains + timing/pause (35–42)
    return Difficulty.hard; // 43–45 harder pause, 46 finale
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
