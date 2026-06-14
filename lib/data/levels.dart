import '../models/level.dart';
import '../progress/progress_store.dart';

/// Hardcoded menu level list — World 1 (levels 1–15), all built and playable.
///
/// Progression is gated: level 1 is the completed baseline, and completing a
/// level unlocks the next one (persisted via [ProgressStore]). The 11–15 exam
/// levels stay locked until level 10 is completed.
List<Level> buildInitialLevels() {
  // Level 1 is always considered complete (the "press Play" intro).
  final completed = {1, ...ProgressStore.completed()};
  // Titles for World 1 match lib/data/level_definitions.dart.
  const world1Titles = <String>[
    'First Steps', // 1
    'One Turn', // 2
    'New Heading', // 3
    'Two Turns', // 4
    'Around the Wall', // 5
    'The Long Way', // 6
    'Pinned Arrow', // 7
    'Detour', // 8
    'Zig Zag', // 9
    'Grand Tour', // 10
    'Crossroads', // 11 (exam)
    'The Maze', // 12 (exam)
    'Guided Path', // 13 (exam)
    'Tight Squeeze', // 14 (exam)
    'Final Exam', // 15 (exam)
  ];

  Difficulty difficultyFor(int number) {
    if (number <= 4) return Difficulty.easy;
    if (number <= 7) return Difficulty.medium;
    return Difficulty.hard; // 8–15 (incl. the 11–15 exam levels)
  }

  LevelStatus statusFor(int number) {
    if (completed.contains(number)) return LevelStatus.completed;
    // Testing: every level is unlocked (no progression gating for now).
    return LevelStatus.unlocked;
  }

  // World 1 has 15 levels.
  return List<Level>.generate(15, (i) {
    final number = i + 1;
    final title =
        number <= world1Titles.length ? world1Titles[i] : 'Level $number';
    return Level(
      id: number,
      number: number,
      title: title,
      difficulty: difficultyFor(number),
      status: statusFor(number),
    );
  });
}
