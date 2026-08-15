// Challenges arrive as hand-written Firestore documents, so the parser is the
// app's only defence against a typo in a console. Everything it rejects would
// otherwise be a board that crashes when the dot reaches it — and the streak
// arithmetic is the other half, because a streak that resets wrongly is the
// thing players notice and resent.

import 'package:flutter_test/flutter_test.dart';

import 'package:dotto/models/challenge.dart';
import 'package:dotto/models/grid_cell.dart';
import 'package:dotto/services/challenge_service.dart';
import 'package:dotto/services/free_hint_service.dart';

void main() {
  final start = DateTime.utc(2026, 8, 10);
  final end = DateTime.utc(2026, 8, 17);

  Map<String, dynamic> doc({
    Map<String, dynamic>? level,
    Object? startDate,
    Object? endDate,
    String? id = 'week_2026_33',
    String reward = 'hint',
  }) =>
      {
        'id': ?id,
        'title': 'Teleport Maze',
        'description': 'Navigate through portals',
        'startDate': startDate ?? start.millisecondsSinceEpoch,
        'endDate': endDate ?? end.millisecondsSinceEpoch,
        'reward': reward,
        'level': level ??
            {
              'rows': 5,
              'cols': 5,
              'start': [0, 0],
              'goal': [4, 4],
              'walls': [
                [1, 1],
                [2, 2]
              ],
              'destroyers': [
                [3, 1]
              ],
              'pieces': [
                {'type': 'arrow', 'direction': 'right', 'count': 2},
                {'type': 'shield', 'count': 1},
              ],
              'forcedPieces': [
                {'type': 'arrow', 'direction': 'down', 'position': [0, 2]},
              ],
            },
      };

  group('parsing a well-formed document', () {
    test('reads the board and the toolkit', () {
      final c = Challenge.fromMap(doc());
      expect(c, isNotNull);
      expect(c!.id, 'week_2026_33');
      expect(c.title, 'Teleport Maze');
      expect(c.reward, ChallengeReward.hint);
      expect(c.level.size, 5);
      expect(c.level.exit.r, 4);
      expect(c.level.walls, hasLength(2));
      expect(c.level.destroyers, hasLength(1));
      expect(c.level.forcedArrows, hasLength(1));
      // Two entries: two right arrows and a shield.
      expect(c.level.toolkit, hasLength(2));
      expect(c.level.toolkit.first.type, ToolType.arrowRight);
      expect(c.level.toolkit.first.count, 2);
    });

    test('never claims a campaign level number', () {
      // A challenge that reported a real id could be written into progress and
      // unlock a level the player never played.
      expect(Challenge.fromMap(doc())!.level.id, lessThan(0));
    });

    test('defaults the start heading rather than refusing', () {
      expect(Challenge.fromMap(doc())!.level.start.dir, Direction.right);
    });

    test('honours an explicit start heading', () {
      final level = (doc()['level'] as Map<String, dynamic>)
        ..['startDir'] = 'down';
      expect(Challenge.fromMap(doc(level: level))!.level.start.dir,
          Direction.down);
    });

    test('falls back to the document id', () {
      final c = Challenge.fromMap(doc(id: null), docId: 'from_doc');
      expect(c?.id, 'from_doc');
    });

    test('accepts dates as millis or ISO strings', () {
      final iso = Challenge.fromMap(doc(
        startDate: start.toIso8601String(),
        endDate: end.toIso8601String(),
      ));
      expect(iso, isNotNull);
      expect(iso!.startDate.toUtc(), start);
    });
  });

  group('a malformed document is dropped, not half-built', () {
    void rejects(String why, Map<String, dynamic> d) =>
        test(why, () => expect(Challenge.fromMap(d), isNull));

    rejects('no id at all', doc(id: null));
    rejects('no dates', {'id': 'x', 'level': doc()['level']});
    rejects('a window that ends before it starts',
        doc(startDate: end.millisecondsSinceEpoch,
            endDate: start.millisecondsSinceEpoch));
    rejects('no level', {'id': 'x', 'startDate': 0, 'endDate': 1});
    rejects('a non-square board',
        doc(level: {'rows': 5, 'cols': 6, 'start': [0, 0], 'goal': [1, 1]}));
    rejects('a board too small to play',
        doc(level: {'rows': 1, 'cols': 1, 'start': [0, 0], 'goal': [0, 0]}));
    rejects('a start off the board',
        doc(level: {'rows': 5, 'cols': 5, 'start': [9, 9], 'goal': [1, 1]}));
    rejects('a goal off the board',
        doc(level: {'rows': 5, 'cols': 5, 'start': [0, 0], 'goal': [5, 0]}));
  });

  group('positions written as maps', () {
    // Firestore will not store an array inside an array, so every list of
    // `[row, col]` pairs — walls, gaps, destroyers, teleporters — had to be
    // empty and the static terrain was unavailable. A map inside an array is
    // storable, so the same cell is now also read as `{"r": …, "c": …}`. Both
    // shapes have to keep working: the JSON on disk and the offline cache use
    // one, the published document the other.

    test('walls, gaps and destroyers read as {r, c}', () {
      final level = {
        'rows': 5,
        'cols': 5,
        'start': [0, 0],
        'goal': [4, 4],
        'walls': [
          {'r': 1, 'c': 1},
          {'r': 2, 'c': 2},
        ],
        'gaps': [
          {'r': 3, 'c': 3},
        ],
        'destroyers': [
          {'r': 3, 'c': 1},
        ],
      };
      final c = Challenge.fromMap(doc(level: level));
      expect(c, isNotNull);
      expect(c!.level.walls, hasLength(2));
      expect(c.level.walls.first.r, 1);
      expect(c.level.walls.first.c, 1);
      expect(c.level.gaps, hasLength(1));
      expect(c.level.destroyers, hasLength(1));
    });

    test('row and col are read as well as r and c', () {
      // The document is written by hand; both spellings are the obvious one.
      final level = {
        'rows': 5,
        'cols': 5,
        'start': [0, 0],
        'goal': [4, 4],
        'walls': [
          {'row': 1, 'col': 2},
        ],
      };
      final walls = Challenge.fromMap(doc(level: level))!.level.walls;
      expect(walls, hasLength(1));
      expect(walls.first.r, 1);
      expect(walls.first.c, 2);
    });

    test('the two shapes mix inside one list', () {
      final level = {
        'rows': 5,
        'cols': 5,
        'start': [0, 0],
        'goal': [4, 4],
        'walls': [
          [1, 1],
          {'r': 2, 'c': 2},
        ],
      };
      expect(Challenge.fromMap(doc(level: level))!.level.walls, hasLength(2));
    });

    test('a map position off the board is dropped like a pair would be', () {
      final level = {
        'rows': 5,
        'cols': 5,
        'start': [0, 0],
        'goal': [4, 4],
        'walls': [
          {'r': 1, 'c': 1},
          {'r': 99, 'c': 0},
          {'r': 2}, // half a coordinate is no coordinate
          {'r': 'two', 'c': 'two'},
        ],
      };
      expect(Challenge.fromMap(doc(level: level))!.level.walls, hasLength(1));
    });

    test('a teleporter pair reads as {a, b} as well as [[r,c],[r,c]]', () {
      // Doubly nested, so the pair needs a map of its own around it too.
      final level = {
        'rows': 5,
        'cols': 5,
        'start': [0, 0],
        'goal': [4, 4],
        'teleporters': [
          {
            'a': {'r': 0, 'c': 4},
            'b': {'r': 4, 'c': 0},
          },
          [
            [1, 0],
            [1, 4]
          ],
        ],
      };
      final pairs = Challenge.fromMap(doc(level: level))!.level.teleporters;
      expect(pairs, hasLength(2));
      expect(pairs.first.a.r, 0);
      expect(pairs.first.a.c, 4);
      expect(pairs.first.b.r, 4);
      expect(pairs.first.b.c, 0);
    });

    test('half a teleporter pair is no teleporter', () {
      final level = {
        'rows': 5,
        'cols': 5,
        'start': [0, 0],
        'goal': [4, 4],
        'teleporters': [
          {
            'a': {'r': 0, 'c': 4},
          },
        ],
      };
      expect(Challenge.fromMap(doc(level: level))!.level.teleporters, isEmpty);
    });
  });

  group('bad entries are skipped without losing the good ones', () {
    test('a wall off the board does not take the level with it', () {
      final level = {
        'rows': 5,
        'cols': 5,
        'start': [0, 0],
        'goal': [4, 4],
        'walls': [
          [1, 1],
          [99, 99], // nonsense
          [2, 2],
        ],
      };
      final c = Challenge.fromMap(doc(level: level));
      expect(c, isNotNull);
      expect(c!.level.walls, hasLength(2),
          reason: 'the two valid walls survive, the impossible one is dropped');
    });

    test('an unknown direction drops just that piece', () {
      final level = {
        'rows': 5,
        'cols': 5,
        'start': [0, 0],
        'goal': [4, 4],
        'pieces': [
          {'type': 'arrow', 'direction': 'sideways', 'count': 1},
          {'type': 'shield', 'count': 1},
        ],
      };
      final c = Challenge.fromMap(doc(level: level));
      expect(c!.level.toolkit, hasLength(1));
      expect(c.level.toolkit.first.type, ToolType.shield);
    });
  });

  group('the challenge window', () {
    final c = Challenge.fromMap(doc())!;

    test('is active between its dates', () {
      expect(c.isActiveAt(DateTime.utc(2026, 8, 12)), isTrue);
      expect(c.isActiveAt(DateTime.utc(2026, 8, 9)), isFalse);
      expect(c.isActiveAt(end), isFalse, reason: 'the end is exclusive');
    });

    test('counts days remaining, never below zero', () {
      expect(c.daysRemainingAt(DateTime.utc(2026, 8, 15)), 2);
      expect(c.daysRemainingAt(DateTime.utc(2026, 9, 1)), 0);
    });

    test('knows it has not started yet', () {
      expect(c.hasNotStartedAt(DateTime.utc(2026, 8, 9)), isTrue);
      expect(c.hasNotStartedAt(start), isFalse, reason: 'the start is inclusive');
      expect(c.hasNotStartedAt(DateTime.utc(2026, 8, 12)), isFalse);
    });

    test('counts the days until it opens by the calendar', () {
      // "tomorrow" is a date, not 24 hours: a window opening at midnight on the
      // 10th is tomorrow all through the 9th, however late in the day it is.
      expect(c.daysUntilAt(DateTime.utc(2026, 8, 9, 23)), 1);
      expect(c.daysUntilAt(DateTime.utc(2026, 8, 8, 1)), 2);
      expect(c.daysUntilAt(DateTime.utc(2026, 8, 10, 0, 1)), 0);
      expect(c.daysUntilAt(DateTime.utc(2026, 9, 1)), 0,
          reason: 'never negative once it has been and gone');
    });
  });

  group('a published week that has not arrived', () {
    // The bug this exists for: weeks are authored and published in batches, so
    // most of the collection is normally scheduled rather than live. The screen
    // had only "this week" and "past", so ten of eleven real documents rendered
    // as nothing at all and the publish looked like it had failed.
    Challenge week(String id, int offsetDays) => Challenge(
          id: id,
          title: id,
          description: '',
          startDate: DateTime.utc(2026, 8, 17).add(Duration(days: offsetDays)),
          endDate: DateTime.utc(2026, 8, 24).add(Duration(days: offsetDays)),
          reward: ChallengeReward.none,
          level: Challenge.fromMap(doc())!.level,
        );

    // Newest first, as the service holds them.
    final scheduled = [week('w36', 14), week('w35', 7), week('w34', 0)];
    final now = DateTime.utc(2026, 8, 15);

    test('is listed as upcoming, soonest first', () {
      ChallengeService.resetForTest(challenges: scheduled);
      expect(ChallengeService.upcomingAt(now).map((c) => c.id),
          ['w34', 'w35', 'w36']);
    });

    test('is neither live nor past', () {
      ChallengeService.resetForTest(challenges: scheduled);
      expect(ChallengeService.currentAt(now), isNull);
      expect(ChallengeService.pastAt(now), isEmpty);
    });

    test('drops out of the list the moment its week opens', () {
      ChallengeService.resetForTest(challenges: scheduled);
      final opened = DateTime.utc(2026, 8, 17);
      expect(ChallengeService.upcomingAt(opened).map((c) => c.id),
          ['w35', 'w36']);
      expect(ChallengeService.currentAt(opened)?.id, 'w34');
    });

    test('does not count toward the streak', () {
      // Nothing scheduled has been playable, so completing nothing is not a
      // broken run.
      ChallengeService.resetForTest(challenges: scheduled);
      expect(ChallengeService.streakAt(now), 0);
    });
  });

  group('streaks', () {
    Challenge at(String id, int week) => Challenge(
          id: id,
          title: id,
          description: '',
          startDate: DateTime.utc(2026, 1, 1).add(Duration(days: 7 * week)),
          endDate: DateTime.utc(2026, 1, 8).add(Duration(days: 7 * week)),
          reward: ChallengeReward.none,
          level: Challenge.fromMap(doc())!.level,
        );

    // Newest first, as the service holds them.
    final past = [at('w3', 2), at('w2', 1), at('w1', 0)];
    final now = DateTime.utc(2026, 2, 1); // all three have ended

    test('counts consecutive completions back from the newest', () {
      ChallengeService.resetForTest(
        challenges: past,
        completed: {'w3', 'w2', 'w1'},
      );
      expect(ChallengeService.streakAt(now), 3);
    });

    test('breaks at the first gap', () {
      // Missed the newest: the run behind it does not count.
      ChallengeService.resetForTest(
        challenges: past,
        completed: {'w2', 'w1'},
      );
      expect(ChallengeService.streakAt(now), 0);
    });

    test('stops at a gap further back', () {
      ChallengeService.resetForTest(
        challenges: past,
        completed: {'w3', 'w1'},
      );
      expect(ChallengeService.streakAt(now), 1);
    });

    test('an unplayed live challenge does not break the run', () {
      // The case this is designed around: a new week starts, and the streak
      // must not read zero until the player has had a chance to play it.
      final live = Challenge(
        id: 'live',
        title: 'live',
        description: '',
        startDate: now.subtract(const Duration(days: 1)),
        endDate: now.add(const Duration(days: 6)),
        reward: ChallengeReward.none,
        level: Challenge.fromMap(doc())!.level,
      );
      ChallengeService.resetForTest(
        challenges: [live, ...past],
        completed: {'w3', 'w2', 'w1'},
      );
      expect(ChallengeService.streakAt(now), 3);
    });

    test('a completed live challenge extends it', () {
      final live = Challenge(
        id: 'live',
        title: 'live',
        description: '',
        startDate: now.subtract(const Duration(days: 1)),
        endDate: now.add(const Duration(days: 6)),
        reward: ChallengeReward.none,
        level: Challenge.fromMap(doc())!.level,
      );
      ChallengeService.resetForTest(
        challenges: [live, ...past],
        completed: {'live', 'w3', 'w2', 'w1'},
      );
      expect(ChallengeService.streakAt(now), 4);
    });
  });

  group('rewards', () {
    test('a hint challenge pays once, not twice', () {
      final c = Challenge.fromMap(doc())!;
      ChallengeService.resetForTest();
      expect(ChallengeService.complete(c), ChallengeReward.hint);
      expect(ChallengeService.bonusHints, 1);

      expect(ChallengeService.complete(c), ChallengeReward.none,
          reason: 'replaying a finished challenge must not farm hints');
      expect(ChallengeService.bonusHints, 1);
    });

    test('a no-reward challenge pays nothing', () {
      final c = Challenge.fromMap(doc(reward: 'none'))!;
      ChallengeService.resetForTest();
      expect(ChallengeService.complete(c), ChallengeReward.none);
      expect(ChallengeService.bonusHints, 0);
    });

    test('a bonus hint can be spent exactly once', () {
      ChallengeService.resetForTest(bonusHints: 1);
      expect(ChallengeService.spendBonusHint(), isTrue);
      expect(ChallengeService.bonusHints, 0);
      expect(ChallengeService.spendBonusHint(), isFalse);
    });
  });

  group('the hint cap', () {
    // The daily hint is available in all of these: resetForTest leaves
    // FreeHintService untouched and an unspent one is the default state. So
    // two bonus hints is already a full hand of three.
    setUp(FreeHintService.resetForTest);

    test('holds the hand at three', () {
      ChallengeService.resetForTest(bonusHints: 2);
      expect(ChallengeService.hintsInHand, ChallengeService.maxHints);
    });

    test('stops a challenge paying out a fourth hint', () {
      final c = Challenge.fromMap(doc())!;
      ChallengeService.resetForTest(bonusHints: 2);
      expect(ChallengeService.complete(c), ChallengeReward.none,
          reason: 'the screen must not promise a hint that was not added');
      expect(ChallengeService.bonusHints, 2);
      expect(ChallengeService.isCompleted(c.id), isTrue,
          reason: 'a full hand still counts as having played the week');
    });

    test('pays out again once there is room', () {
      final c = Challenge.fromMap(doc())!;
      ChallengeService.resetForTest(bonusHints: 1);
      expect(ChallengeService.complete(c), ChallengeReward.hint);
      expect(ChallengeService.bonusHints, 2);
    });

    test('drops the daily hint from the hand once bonuses fill it', () {
      ChallengeService.resetForTest(bonusHints: ChallengeService.maxHints);
      expect(ChallengeService.freeHintCounts, isFalse,
          reason: 'spending it here would cost the one that comes back');
      expect(ChallengeService.hintsInHand, ChallengeService.maxHints);
    });

    test('shows an old oversized save as three, and spends it down', () {
      ChallengeService.resetForTest(bonusHints: 5);
      expect(ChallengeService.hintsInHand, ChallengeService.maxHints);
      expect(ChallengeService.spendBonusHint(), isTrue);
      expect(ChallengeService.bonusHints, 4);
    });
  });

  test('no challenges is a normal state, not an error', () {
    ChallengeService.resetForTest();
    final now = DateTime.now();
    expect(ChallengeService.challenges, isEmpty);
    expect(ChallengeService.currentAt(now), isNull);
    expect(ChallengeService.pastAt(now), isEmpty);
    expect(ChallengeService.streakAt(now), 0);
  });
}
