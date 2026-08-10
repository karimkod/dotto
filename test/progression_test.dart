// Level unlock progression: level 1 is open from the start, finishing a level
// opens the next, and everything beyond the frontier stays locked.
//
// On the VM these run against the shared_preferences store with no plugin host
// behind it, so writes land in its in-memory cache and go no further — the same
// facade the web build backs with localStorage. What is asserted here is the
// gating logic, not the storage.

import 'package:flutter_test/flutter_test.dart';

import 'package:dotto/data/levels.dart';
import 'package:dotto/models/level.dart';
import 'package:dotto/progress/progress_store.dart';

void main() {
  // The stub store is process-global, so each test states the progress it wants
  // rather than assuming a clean slate.
  Level levelNumber(List<Level> levels, int n) =>
      levels.firstWhere((l) => l.number == n);

  test('a fresh player has only level 1 open', () {
    final levels = buildInitialLevels();
    expect(levels, hasLength(kLevelCount));
    expect(levelNumber(levels, 1).status, LevelStatus.unlocked,
        reason: 'level 1 must be playable with no progress at all');
    expect(levelNumber(levels, 2).isLocked, isTrue);
    expect(levelNumber(levels, kLevelCount).isLocked, isTrue);
    // Nothing is completed until it has actually been won.
    expect(levels.where((l) => l.isCompleted), isEmpty);
  });

  test('finishing a level completes it and opens exactly the next one', () {
    ProgressStore.markCompleted(1);
    final levels = buildInitialLevels();
    expect(levelNumber(levels, 1).status, LevelStatus.completed);
    expect(levelNumber(levels, 2).status, LevelStatus.unlocked);
    expect(levelNumber(levels, 3).isLocked, isTrue,
        reason: 'only the very next level opens, not the whole world');
  });

  test('the frontier advances as levels are won', () {
    for (final n in [2, 3, 4]) {
      ProgressStore.markCompleted(n);
    }
    final levels = buildInitialLevels();
    for (final n in [1, 2, 3, 4]) {
      expect(levelNumber(levels, n).isCompleted, isTrue, reason: 'level $n');
    }
    expect(levelNumber(levels, 5).status, LevelStatus.unlocked);
    expect(levelNumber(levels, 6).isLocked, isTrue);
    // Exactly one open frontier at a time.
    expect(levels.where((l) => l.isUnlocked), hasLength(1));
  });

  test('a gap in progress does not strand the player', () {
    // Progress written out of order — by the designer, or an older build — must
    // still leave the level after it reachable rather than walling it off.
    ProgressStore.markCompleted(40);
    final levels = buildInitialLevels();
    expect(levelNumber(levels, 41).status, LevelStatus.unlocked,
        reason: 'the level after a completed one is always open');
    expect(levelNumber(levels, 39).isLocked, isTrue,
        reason: 'unreached levels stay locked, gap or not');
  });

  test('completed levels stay replayable', () {
    final levels = buildInitialLevels();
    final done = levels.firstWhere((l) => l.isCompleted);
    expect(done.isLocked, isFalse,
        reason: 'replaying a finished level must never be blocked');
  });
}
