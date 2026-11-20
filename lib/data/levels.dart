import '../models/level.dart';
import '../progress/progress_store.dart';
import 'level_definitions.dart';

/// Every level in the game, by id, in the order they are played.
///
/// A level's id is permanent: saved progress, recorded hints and analytics all
/// key on it. So when a level is taken out of the game its id is left unused,
/// rather than every later level moving down one — a save that says level 40
/// is done keeps meaning the same board. The number a player sees is the
/// level's place in this list instead ([levelNumberOf]).
///
/// Ids 3, 9, 10, 12, 13, 18 and 19 are retired that way.
final List<int> levelIds =
    List.unmodifiable(levelDefinitions.keys.toList()..sort());

/// Total number of built, playable levels:
/// World 1 (10, ids 1–15) + World 2 (3, ids 16–20) + World 3 (21–30)
/// + World 4 (31–50) + World 5 (51–60) + Master Trials (61–70)
/// + World 6 (71–91) + World 7 (92–110) + World 8 (111–113).
const int kLevelCount = 106;

/// The level id at which World 2 (Static Destroyers) begins.
const int kWorld2Start = 16;

/// The level id at which World 3 (Shields & Explosions) begins.
const int kWorld3Start = 21;

/// The level id at which World 4 (Moving Destroyers + Pause) begins.
const int kWorld4Start = 31;

/// The level id at which World 5 (Teleporters) begins.
const int kWorld5Start = 51;

/// The level id at which World 6 (Rotating Arrows) begins — the Master
/// Trials (61–70) sit between the two as a no-new-pieces interlude.
const int kWorld6Start = 71;

/// The level id at which World 7 (One-Shot Arrows) begins.
const int kWorld7Start = 92;

/// The level id at which World 8 (Bouncers) begins.
const int kWorld8Start = 111;

/// Which world a level belongs to, 1–8.
///
/// The Master Trials (61–70) are an interlude rather than a world of their own,
/// and count as World 5 — the world whose pieces they revisit. The equivalent
/// helper in the test suite splits them out separately, so the two do not agree
/// on 61–70 by design: one is labelling analytics, the other is grouping test
/// output.
int worldOf(int level) {
  if (level >= kWorld8Start) return 8;
  if (level >= kWorld7Start) return 7;
  if (level >= kWorld6Start) return 6;
  if (level >= kWorld5Start) return 5;
  if (level >= kWorld4Start) return 4;
  if (level >= kWorld3Start) return 3;
  if (level >= kWorld2Start) return 2;
  return 1;
}

/// The number players see for level [id]: its place in play order, from 1.
int levelNumberOf(int id) => levelIds.indexOf(id) + 1;

/// The level after [id] in play order, or null after the last one.
int? nextLevelId(int id) {
  final i = levelIds.indexOf(id);
  if (i < 0 || i + 1 >= levelIds.length) return null;
  return levelIds[i + 1];
}

/// The first level of [world] in play order — the one its banner sits under.
int firstLevelOfWorld(int world) =>
    levelIds.firstWhere((id) => worldOf(id) == world);

/// Every level id belonging to [world], in play order.
Iterable<int> levelsInWorld(int world) =>
    levelIds.where((id) => worldOf(id) == world);

/// Whether [completed] contains every level of [world].
bool isWorldComplete(int world, Set<int> completed) =>
    levelsInWorld(world).every(completed.contains);

/// How many of the levels in [completed] are still in the game. A save can
/// hold a retired id, and that must not count toward totals or achievements.
int completedCount(Set<int> completed) =>
    levelIds.where(completed.contains).length;

/// Hardcoded menu level list, in play order.
///
/// Progression is gated: the first level is the completed baseline, and
/// completing a level unlocks the next one (persisted via [ProgressStore]).
List<Level> buildInitialLevels() {
  final completed = ProgressStore.completed();

  Difficulty difficultyFor(int id) {
    // World 1.
    if (id <= 4) return Difficulty.easy; // 1, 2, 4
    if (id <= 9) return Difficulty.medium; // 5–8 (8 is a gentle detour)
    if (id <= 15) return Difficulty.hard; // the exams: 11, 14, 15
    // World 2 (16, 17, 20).
    if (id <= 16) return Difficulty.easy;
    if (id <= 17) return Difficulty.medium;
    if (id <= 20) return Difficulty.hard;
    // World 3 (21–30).
    if (id <= 22) return Difficulty.easy; // learn shields (21–22)
    if (id <= 27) return Difficulty.medium; // shield puzzles + clearing (23–27)
    if (id <= 30) return Difficulty.hard; // challenge + finale (28–30)
    // World 4 (31–50).
    if (id <= 33) return Difficulty.easy; // moving destroyers intro (31–33)
    if (id <= 44) return Difficulty.medium; // chains + timing (34–44)
    if (id <= 50) return Difficulty.hard; // 45–46 timing, 47–50 exams
    // World 5 (51–60): teleporters, ramping again from the start.
    if (id <= 52) return Difficulty.easy; // learn the portal (51–52)
    if (id <= 56) return Difficulty.medium; // combine mechanics (53–56)
    if (id <= 60) return Difficulty.hard; // 57–60 the hard teleporter exams
    // Master Trials (61–70): every level is a remix exam.
    if (id <= 63) return Difficulty.medium; // gentler re-entry (61–63)
    if (id <= 70) return Difficulty.hard; // 64–70 the trials proper
    // World 6 (71–91): rotating arrows, teaching the new piece from scratch.
    // 73 breaks the run: patrols, mines and a portal on top of the dial, so it
    // is flagged medium even though the levels either side of it stay easy.
    if (id == 73) return Difficulty.medium;
    if (id <= 74) return Difficulty.easy; // learn the dial (71–72, 74)
    if (id <= 82) return Difficulty.medium; // combine mechanics (75–82)
    if (id <= 91) return Difficulty.hard; // 83–91 the clockwork exams
    // World 7 (92–110): one-shot arrows, teaching the new piece from scratch.
    if (id <= 95) return Difficulty.easy; // learn the burn (92–95)
    if (id <= 103) return Difficulty.medium; // combine mechanics (96–103)
    if (id <= 110) return Difficulty.hard; // 104–110 the burning exams
    // World 8 (111–): bouncers, teaching the new piece from scratch.
    return Difficulty.easy; // learn the bounce (111–113)
  }

  /// The climb: the first level is open from the start, and finishing a level
  /// opens the one after it in play order — straight past any retired id in
  /// between. Anything further ahead stays locked.
  ///
  /// Gaps in [completed] are treated forgivingly — a level is open if the one
  /// before it is done, whether or not everything earlier is — so progress
  /// written out of order (by the designer, or by an older build) can never
  /// strand a player behind a level they cannot reach.
  LevelStatus statusFor(int index) {
    if (completed.contains(levelIds[index])) return LevelStatus.completed;
    if (index == 0 || completed.contains(levelIds[index - 1])) {
      return LevelStatus.unlocked;
    }
    return LevelStatus.locked;
  }

  return [
    for (var i = 0; i < levelIds.length; i++)
      Level(
        id: levelIds[i],
        number: i + 1,
        title: levelDataFor(levelIds[i])!.title,
        difficulty: difficultyFor(levelIds[i]),
        status: statusFor(i),
      ),
  ];
}
