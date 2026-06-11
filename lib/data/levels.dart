import '../models/level.dart';

/// Hardcoded level list. The first five mirror the HTML prototype's tutorial
/// levels; the rest are placeholders for the winding path.
///
/// Progress for now: level 1 completed, level 2 unlocked (current), rest locked.
List<Level> buildInitialLevels() {
  // Titles for the first five come straight from the prototype.
  const seededTitles = <String>[
    'First Steps', // 1 — teach arrows
    'Around the Wall', // 2 — teach walls
    'Danger Zone', // 3 — teach destroyers
    'Perfect Timing', // 4 — teach pause
    'Through the Void', // 5 — teach teleporters
  ];

  Difficulty difficultyFor(int number) {
    if (number <= 2) return Difficulty.easy;
    if (number <= 4) return Difficulty.medium;
    return Difficulty.hard;
  }

  LevelStatus statusFor(int number) {
    if (number == 1) return LevelStatus.completed;
    if (number == 2) return LevelStatus.unlocked;
    return LevelStatus.locked;
  }

  return List<Level>.generate(20, (i) {
    final number = i + 1;
    final title =
        number <= seededTitles.length ? seededTitles[i] : 'Level $number';
    return Level(
      id: number,
      number: number,
      title: title,
      difficulty: difficultyFor(number),
      status: statusFor(number),
    );
  });
}
