import '../models/level.dart';

/// Hardcoded menu level list. World 1 (levels 1–10) is built and playable; the
/// rest are locked placeholders shown further up the path.
///
/// Progress: level 1 completed, levels 2–10 unlocked, 11+ locked.
List<Level> buildInitialLevels() {
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
    if (number == 1) return LevelStatus.completed;
    if (number <= 10) return LevelStatus.unlocked;
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
