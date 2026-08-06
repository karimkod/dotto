import '../models/level.dart';
import '../progress/progress_store.dart';
import 'level_definitions.dart';

/// Total number of built, playable levels:
/// World 1 (1–15) + World 2 (16–20) + World 3 (21–30) + World 4 (31–50)
/// + World 5 (51–60) + Master Trials (61–70) + World 6 (71–91)
/// + World 7 (92–).
const int kLevelCount = 92;

/// The level number at which World 2 (Static Destroyers) begins.
const int kWorld2Start = 16;

/// The level number at which World 3 (Shields & Explosions) begins.
const int kWorld3Start = 21;

/// The level number at which World 4 (Moving Destroyers + Pause) begins.
const int kWorld4Start = 31;

/// The level number at which World 5 (Teleporters) begins.
const int kWorld5Start = 51;

/// The level number at which World 6 (Rotating Arrows) begins — the Master
/// Trials (61–70) sit between the two as a no-new-pieces interlude.
const int kWorld6Start = 71;

/// The level number at which World 7 (One-Shot Arrows) begins.
const int kWorld7Start = 92;

/// Hardcoded menu level list — World 1 (1–15), World 2 (16–20), World 3 (21–30),
/// World 4 (31–50).
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
    // World 4 (31–50).
    if (number <= 34) return Difficulty.easy; // moving destroyers intro (31–34)
    if (number <= 44) return Difficulty.medium; // chains + timing (35–44)
    if (number <= 50) return Difficulty.hard; // 45–46 timing, 47–50 exams
    // World 5 (51–60): teleporters, ramping again from the start.
    if (number <= 52) return Difficulty.easy; // learn the portal (51–52)
    if (number <= 56) return Difficulty.medium; // combine mechanics (53–56)
    if (number <= 60) return Difficulty.hard; // 57–60 the hard teleporter exams
    // Master Trials (61–70): every level is a remix exam.
    if (number <= 63) return Difficulty.medium; // gentler re-entry (61–63)
    if (number <= 70) return Difficulty.hard; // 64–70 the trials proper
    // World 6 (71–91): rotating arrows, teaching the new piece from scratch.
    if (number <= 74) return Difficulty.easy; // learn the dial (71–74)
    if (number <= 82) return Difficulty.medium; // combine mechanics (75–82)
    if (number <= 91) return Difficulty.hard; // 83–91 the clockwork exams
    // World 7 (92–): one-shot arrows, teaching the new piece from scratch.
    return Difficulty.easy; // 92 the opener
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
