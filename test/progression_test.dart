// Level unlock progression: the first level is open from the start, finishing
// a level opens the next, and everything beyond the frontier stays locked.
//
// On the VM these run against the shared_preferences store with no plugin host
// behind it, so writes land in its in-memory cache and go no further — the same
// facade the web build backs with localStorage. What is asserted here is the
// gating logic, not the storage.

import 'package:flutter_test/flutter_test.dart';

import 'package:dotto/data/level_definitions.dart';
import 'package:dotto/data/levels.dart';
import 'package:dotto/models/level.dart';
import 'package:dotto/progress/progress_store.dart';

/// Levels taken out of the game. Their ids stay unused so that old saves keep
/// pointing at the same boards.
const retired = {3, 9, 10, 12, 13, 18, 19};

void main() {
  // The stub store is process-global, so each test states the progress it wants
  // rather than assuming a clean slate.
  setUp(ProgressStore.clear);

  // Progress is stored by id, so the tests look levels up by id too.
  Level byId(List<Level> levels, int id) =>
      levels.firstWhere((l) => l.id == id);

  test('a fresh player has only the first level open', () {
    final levels = buildInitialLevels();
    expect(levels, hasLength(kLevelCount));
    expect(byId(levels, 1).status, LevelStatus.unlocked,
        reason: 'level 1 must be playable with no progress at all');
    expect(byId(levels, 2).isLocked, isTrue);
    expect(byId(levels, levelIds.last).isLocked, isTrue);
    // Nothing is completed until it has actually been won.
    expect(levels.where((l) => l.isCompleted), isEmpty);
  });

  test('finishing a level completes it and opens exactly the next one', () {
    ProgressStore.markCompleted(1);
    final levels = buildInitialLevels();
    expect(byId(levels, 1).status, LevelStatus.completed);
    expect(byId(levels, 2).status, LevelStatus.unlocked);
    expect(byId(levels, 4).isLocked, isTrue,
        reason: 'only the very next level opens, not the whole world');
  });

  test('the frontier advances as levels are won', () {
    final firstFour = levelIds.take(4).toList();
    for (final id in firstFour) {
      ProgressStore.markCompleted(id);
    }
    final levels = buildInitialLevels();
    for (final id in firstFour) {
      expect(byId(levels, id).isCompleted, isTrue, reason: 'level $id');
    }
    expect(byId(levels, levelIds[4]).status, LevelStatus.unlocked);
    expect(byId(levels, levelIds[5]).isLocked, isTrue);
    // Exactly one open frontier at a time.
    expect(levels.where((l) => l.isUnlocked), hasLength(1));
  });

  test('a gap in progress does not strand the player', () {
    // Progress written out of order — by the designer, or an older build — must
    // still leave the level after it reachable rather than walling it off.
    ProgressStore.markCompleted(40);
    final levels = buildInitialLevels();
    expect(byId(levels, 41).status, LevelStatus.unlocked,
        reason: 'the level after a completed one is always open');
    expect(byId(levels, 39).isLocked, isTrue,
        reason: 'unreached levels stay locked, gap or not');
  });

  test('completed levels stay replayable', () {
    ProgressStore.markCompleted(1);
    final levels = buildInitialLevels();
    final done = levels.firstWhere((l) => l.isCompleted);
    expect(done.isLocked, isFalse,
        reason: 'replaying a finished level must never be blocked');
  });

  group('retired levels', () {
    test('are gone from the game, and the numbers close up around them', () {
      final levels = buildInitialLevels();
      for (final id in retired) {
        expect(levelDataFor(id), isNull, reason: 'level $id is retired');
        expect(levels.where((l) => l.id == id), isEmpty);
      }
      expect(levels.map((l) => l.id), levelIds);
      expect(levels.map((l) => l.number),
          [for (var n = 1; n <= kLevelCount; n++) n],
          reason: 'players see 1, 2, 3… with no holes where levels were');
      // Level 4 is now the third level players meet, level 11 the eighth.
      expect(byId(levels, 4).number, 3);
      expect(byId(levels, 11).number, 8);
      expect(levelNumberOf(4), 3);
    });

    test('finishing the level before one opens the level after it', () {
      for (final (before, after) in [(2, 4), (8, 11), (11, 14), (17, 20)]) {
        ProgressStore.clear();
        ProgressStore.markCompleted(before);
        final levels = buildInitialLevels();
        expect(byId(levels, after).status, LevelStatus.unlocked,
            reason: 'finishing $before must open $after across the gap');
        expect(nextLevelId(before), after);
      }
    });

    test('a player who stopped on a retired level carries on past it', () {
      // Someone who had won 1–9 was about to play 10. After the update they
      // land on 11, the next level still in the game.
      for (var id = 1; id <= 9; id++) {
        ProgressStore.markCompleted(id);
      }
      final levels = buildInitialLevels();
      expect(levels.where((l) => l.isUnlocked).map((l) => l.id), [11]);
    });

    test('a save naming them never counts toward the totals', () {
      expect(completedCount({1, 2, 3, 9}), 2);
      expect(completedCount({...levelIds, ...retired}), kLevelCount,
          reason: 'finishing everything, old levels included, is still '
              'exactly all of them');
    });

    test('the Next button runs straight past them', () {
      expect(nextLevelId(2), 4);
      expect(nextLevelId(8), 11);
      expect(nextLevelId(11), 14);
      expect(nextLevelId(17), 20);
      expect(nextLevelId(levelIds.last), isNull);
    });
  });
}
