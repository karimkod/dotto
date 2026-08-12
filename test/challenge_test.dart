// Challenges arrive as hand-written Firestore documents, so the parser is the
// app's only defence against a typo in a console. Everything it rejects would
// otherwise be a board that crashes when the dot reaches it — and the streak
// arithmetic is the other half, because a streak that resets wrongly is the
// thing players notice and resent.

import 'package:flutter_test/flutter_test.dart';

import 'package:dotto/models/challenge.dart';
import 'package:dotto/models/grid_cell.dart';
import 'package:dotto/services/challenge_service.dart';

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
        if (id != null) 'id': id,
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

  test('no challenges is a normal state, not an error', () {
    ChallengeService.resetForTest();
    final now = DateTime.now();
    expect(ChallengeService.challenges, isEmpty);
    expect(ChallengeService.currentAt(now), isNull);
    expect(ChallengeService.pastAt(now), isEmpty);
    expect(ChallengeService.streakAt(now), 0);
  });
}
