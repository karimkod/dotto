import '../models/level.dart';
import '../progress/progress_store.dart';

/// Hardcoded menu level list. World 1 (levels 1–10) is built and playable; the
/// rest are locked placeholders shown further up the path.
///
/// Progression is gated: level 1 is the completed baseline, and completing a
/// level unlocks the next one (persisted via [ProgressStore]).
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
  ];

  Difficulty difficultyFor(int number) {
    if (number <= 4) return Difficulty.easy;
    if (number <= 7) return Difficulty.medium;
    return Difficulty.hard;
  }

  LevelStatus statusFor(int number) {
    if (completed.contains(number)) return LevelStatus.completed;
    // Unlocked if it's the first level or the previous one is completed.
    if (number == 1 || completed.contains(number - 1)) {
      return LevelStatus.unlocked;
    }
    return LevelStatus.locked;
  }

  return List<Level>.generate(20, (i) {
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
