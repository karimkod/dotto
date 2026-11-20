// Bouncers: player-placed pieces that turn the dot a quarter-turn, and which
// way depends on the side it comes in from. Nothing about a bouncer changes
// during a run, so the same one can turn the dot two different ways on two
// visits, which is what World 8 is built on.

import 'package:flutter_test/flutter_test.dart';

import 'package:dotto/data/level_definitions.dart';
import 'package:dotto/data/level_hints.dart';
import 'package:dotto/engine/level_solver.dart';
import 'package:dotto/engine/simulator.dart';
import 'package:dotto/engine/solver_isolate.dart';
import 'package:dotto/models/challenge.dart';
import 'package:dotto/models/game_state.dart';
import 'package:dotto/models/grid_cell.dart';
import 'package:dotto/models/level_data.dart';
import 'package:dotto/services/challenge_service.dart';

PlacedElement bouncer(ToolType t) =>
    PlacedElement(type: PlacedType.bouncer, tool: t);

const kinds = [ToolType.bouncerSlash, ToolType.bouncerBackslash];

Direction opposite(Direction d) => switch (d) {
      Direction.up => Direction.down,
      Direction.down => Direction.up,
      Direction.left => Direction.right,
      Direction.right => Direction.left,
    };

void main() {
  group('the tool type', () {
    test('both kinds place as bouncers and carry no heading of their own', () {
      for (final t in kinds) {
        expect(t.placedType, PlacedType.bouncer);
        expect(t.isBouncer, isTrue);
        expect(t.isOneShot, isFalse);
        expect(t.direction, isNull,
            reason: 'where a bouncer sends the dot depends on the dot');
      }
      for (final t in ToolType.values.where((t) => !kinds.contains(t))) {
        expect(t.isBouncer, isFalse, reason: '$t is not a bouncer');
      }
    });

    test('the two kit tiles read apart', () {
      expect(ToolType.bouncerSlash.label,
          isNot(ToolType.bouncerBackslash.label));
      expect(ToolType.bouncerSlash.glyph,
          isNot(ToolType.bouncerBackslash.glyph));
    });
  });

  group('the turn', () {
    test('the slash swaps right with up and left with down', () {
      const t = ToolType.bouncerSlash;
      expect(t.bounce(Direction.right), Direction.up);
      expect(t.bounce(Direction.up), Direction.right);
      expect(t.bounce(Direction.left), Direction.down);
      expect(t.bounce(Direction.down), Direction.left);
    });

    test('the backslash swaps right with down and left with up', () {
      const t = ToolType.bouncerBackslash;
      expect(t.bounce(Direction.right), Direction.down);
      expect(t.bounce(Direction.down), Direction.right);
      expect(t.bounce(Direction.left), Direction.up);
      expect(t.bounce(Direction.up), Direction.left);
    });

    test('is always a quarter-turn, and the two kinds turn opposite ways', () {
      for (final t in kinds) {
        for (final d in Direction.values) {
          expect(t.bounce(d), isNot(d), reason: '$t lets $d run straight on');
          expect(t.bounce(d), isNot(opposite(d)), reason: '$t sends $d back');
        }
      }
      for (final d in Direction.values) {
        expect(ToolType.bouncerSlash.bounce(d),
            opposite(ToolType.bouncerBackslash.bounce(d)));
      }
    });

    test('every other tool leaves the heading alone', () {
      for (final t in ToolType.values.where((t) => !kinds.contains(t))) {
        for (final d in Direction.values) {
          expect(t.bounce(d), d, reason: '$t');
        }
      }
    });
  });

  group('level 112: one bouncer, two jobs', () {
    final level = levelDataFor(112)!;
    final key = 2 * level.size + 2;

    test('the dot meets the bouncer twice and turns a different way each time',
        () {
      final trail = <int>[];
      final res = simulateDetailed(
          level, {key: bouncer(ToolType.bouncerSlash)},
          trail: trail);
      expect(res.outcome, SimOutcome.win);
      expect(trail.where((k) => k == key), hasLength(2));
      expect(trail[trail.indexOf(key) + 1], key - level.size,
          reason: 'in from the west, out to the north');
      expect(trail[trail.lastIndexOf(key) + 1], key + level.size,
          reason: 'in from the east, out to the south');
    });

    test('an arrow in the same cell turns the same way twice and loops', () {
      final res = simulateDetailed(level, {
        key: const PlacedElement(
          type: PlacedType.arrow,
          tool: ToolType.arrowUp,
          direction: Direction.up,
        ),
      });
      expect(res.outcome, SimOutcome.lose);
      expect(res.cause, isNull, reason: 'it circles until the run times out');
    });
  });

  group('the solvers', () {
    String canon(Map<int, PlacedElement> m) {
      final keys = m.keys.toList()..sort();
      return keys.map((k) => '$k:${m[k]!.tool.name}').join(',');
    }

    for (final n in [111, 112, 113]) {
      test('all agree level $n has exactly its recorded solution', () {
        final level = levelDataFor(n)!;
        final recorded = canon({
          for (final (r, c, t) in kSolutionBouncers[n]!)
            r * level.size + c: bouncer(t),
        });
        expect(needsBruteSolver(level), isFalse,
            reason: 'a bouncer never changes, so the fast solver can take it');
        expect(solveAll(level).map(canon).toList(), [recorded],
            reason: 'BruteSearch');
        expect(enumerateSolutions(level).map(canon).toList(), [recorded],
            reason: 'PathSearch');
        expect(pathSolve(level).map(canon).toList(), [recorded],
            reason: 'pathSolve');
        expect(pathMinPieces(level), toolkitTotal(level),
            reason: 'tight: the level needs every piece in its kit');
      });
    }

    // The fast static solver used to leave a cell empty on the first visit
    // and then branch again on a later visit, placing a piece there: a board
    // no run can have. On 112 that found the one solution twice.
    test('a cell left empty stays empty for the rest of the run', () {
      expect(pathSolve(levelDataFor(112)!), hasLength(1));
    });
  });

  group('challenges', () {
    Map<String, dynamic> doc(List<Map<String, Object?>> pieces) => {
          'id': 'week_test',
          'title': 'Bounce',
          'description': 'Glance off the bouncer',
          'startDate': DateTime.utc(2026, 12, 7).millisecondsSinceEpoch,
          'endDate': DateTime.utc(2026, 12, 14).millisecondsSinceEpoch,
          'reward': 'hint',
          'level': {
            'rows': 5,
            'cols': 5,
            'start': [4, 0],
            'goal': [0, 3],
            'pieces': pieces,
          },
        };

    test('a document hands out bouncers by the way they lean', () {
      final c = Challenge.fromMap(doc([
        {'type': 'bouncer', 'direction': 'slash', 'count': 1},
        {'type': 'bouncer', 'direction': 'backslash', 'count': 2},
        {'type': 'bouncer', 'direction': 'sideways', 'count': 1},
      ]))!;
      final kit = {for (final e in c.level.toolkit) e.type: e.count};
      expect(kit, {ToolType.bouncerSlash: 1, ToolType.bouncerBackslash: 2},
          reason: 'an unknown lean is dropped, like any unknown piece');
    });

    test('the offline cache writes them back the same way', () {
      final c = Challenge.fromMap(doc([
        {'type': 'bouncer', 'direction': 'backslash', 'count': 1},
      ]))!;
      final pieces =
          (ChallengeService.encodeLevelForTest(c)['pieces']! as List)
              .cast<Map<String, Object?>>();
      expect(pieces.single, containsPair('type', 'bouncer'));
      expect(pieces.single, containsPair('direction', 'backslash'));
    });

    test('a pinned bouncer survives the document and the cache', () {
      final d = doc(const []);
      (d['level'] as Map<String, dynamic>)['forcedPieces'] = [
        {'type': 'bouncer', 'direction': 'backslash', 'position': [2, 3]},
      ];
      final level = Challenge.fromMap(d)!.level;
      expect(level.forcedBouncerAt(2, 3), ToolType.bouncerBackslash);
      final forced = (ChallengeService.encodeLevelForTest(Challenge.fromMap(d)!)[
              'forcedPieces']! as List)
          .cast<Map<String, Object?>>();
      expect(forced.single, containsPair('type', 'bouncer'));
      expect(forced.single, containsPair('direction', 'backslash'));
    });
  });

  group('a bouncer pinned by the level', () {
    // The dot turns down at the pinned backslash, the only way past the walls,
    // and the one arrow in the kit sends it east at row 3 to the exit.
    const level = LevelData(
      id: -1,
      size: 5,
      title: 'Pinned',
      tip: '',
      start: StartSpec(0, 0, Direction.right),
      exit: Pos(3, 4),
      walls: [Pos(1, 0), Pos(1, 1), Pos(0, 3)],
      forcedBouncers: [ForcedBouncer(0, 2, ToolType.bouncerBackslash)],
      toolkit: [ToolkitEntry(ToolType.arrowRight, 1)],
    );
    String canon(Iterable<Map<int, PlacedElement>> sols) => sols
        .map((m) => (m.keys.toList()..sort())
            .map((k) => '$k:${m[k]!.tool.name}')
            .join(','))
        .join(' | ');

    test('is level layout: fixed in place and never placeable', () {
      expect(level.hasForcedPieceAt(0, 2), isTrue);
      expect(placeableCells(level), isNot(contains(2)));
      expect(buildForcedPieces(level)[2]!.tool, ToolType.bouncerBackslash);
    });

    test('turns the dot like a placed one', () {
      final trail = <int>[];
      simulateDetailed(level, const {}, trail: trail);
      expect(trail.take(4), [1, 2, 7, 12], reason: 'east, then down column 2');
    });

    test('every solver finds the one solution past it', () {
      // Reachability used to treat a pinned piece it did not know as one the
      // dot runs straight through, which would hide row 3 from BruteSearch.
      expect(reachableCells(level), containsAll(<int>[7, 12, 17]));
      expect(canon(solveAll(level)), '17:arrowRight', reason: 'BruteSearch');
      expect(canon(enumerateSolutions(level)), '17:arrowRight',
          reason: 'PathSearch');
      expect(canon(pathSolve(level)), '17:arrowRight', reason: 'pathSolve');
    });

    test('Find Toolkit keeps it, and keeps rotating arrows too', () {
      final copy = levelWithToolkit(
          const LevelData(
            id: -1,
            size: 5,
            title: '',
            tip: '',
            start: StartSpec(0, 0, Direction.right),
            exit: Pos(4, 4),
            rotatingArrows: [RotatingArrow(2, 2, Direction.up)],
            forcedBouncers: [ForcedBouncer(1, 1, ToolType.bouncerSlash)],
            toolkit: [],
          ),
          const {ToolType.arrowUp: 1});
      expect(copy.rotatingArrowAt(2, 2), Direction.up);
      expect(copy.forcedBouncerAt(1, 1), ToolType.bouncerSlash);
    });
  });

  test('Find Toolkit can insist on a bouncer', () {
    // Level 111 with its kit taken away: an up arrow or a slash both solve it.
    final base = levelWithToolkit(levelDataFor(111)!, const {});
    FindToolkitResult find({required bool mustBounce}) =>
        findToolkit(FindToolkitRequest(
          base: base,
          candidates: const [
            {ToolType.arrowUp: 1},
            {ToolType.bouncerSlash: 1},
          ],
          cursor: 0,
          mustShield: false,
          mustPause: false,
          mustBounce: mustBounce,
        ));
    expect(find(mustBounce: false).kit, {ToolType.arrowUp: 1});
    expect(find(mustBounce: true).kit, {ToolType.bouncerSlash: 1});
  });
}
