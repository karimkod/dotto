// Hints used to hand out the recorded solution in the order it was written
// down — so the first hint on most levels was the first turn out of the start,
// the one piece the board had already shown the player. These pin the order
// that replaced it (lib/data/hint_order.dart): the piece a player is least
// likely to find on their own goes first.

import 'package:flutter_test/flutter_test.dart';

import 'package:dotto/data/hint_order.dart';
import 'package:dotto/data/level_definitions.dart';
import 'package:dotto/data/level_hints.dart';
import 'package:dotto/data/levels.dart';
import 'package:dotto/engine/simulator.dart';
import 'package:dotto/models/game_state.dart';
import 'package:dotto/models/grid_cell.dart';
import 'package:dotto/models/level_data.dart';

HintPlacement _arrow(int r, int c, Direction d) => HintPlacement(
    r, c, PlacedElement(type: PlacedType.arrow, tool: d.arrowTool, direction: d));

/// One board with a piece in every tier, laid out on a 5x5:
///
///     .  .  .  ## EX
///     .  .  .  .  .
///     .  .  B> XX C^
///     .  .  .  .  .
///     S> Sh A^ ## D<
///
///  * A, up at (4,2): the dot hits the wall at (4,3) right after it, so
///    pressing Play shows exactly where it goes.
///  * B, right at (2,2): turns the dot early. Without it the dot climbs on to
///    the top edge, two cells further, and the crash points at nothing.
///  * The shield on (4,1) is for the mine at (2,3), and (3,2) would do as
///    well — there is room to get it right without being told.
///  * C, up at (2,4), is the last turn, the one read back from the exit.
///  * D, at (4,4), is never reached: the level is won without it.
const _tiers = LevelData(
  id: 970,
  size: 5,
  title: 'tiers',
  tip: '',
  start: StartSpec(4, 0, Direction.right),
  exit: Pos(0, 4),
  walls: [Pos(4, 3), Pos(0, 3)],
  destroyers: [Pos(2, 3)],
  toolkit: [],
);

final _a = _arrow(4, 2, Direction.up);
final _b = _arrow(2, 2, Direction.right);
final _c = _arrow(2, 4, Direction.up);
final _d = _arrow(4, 4, Direction.left);
const _sh = HintPlacement(
    4, 1, PlacedElement(type: PlacedType.shield, tool: ToolType.shield));

void main() {
  group('the order on a board built to have one piece per tier', () {
    Map<int, PlacedElement> board(List<HintPlacement> ps) =>
        {for (final p in ps) p.r * 5 + p.c: p.element};

    test('the board is what the comments say it is', () {
      final all = [_a, _b, _c, _d, _sh];
      expect(simulate(_tiers, board(all)), SimOutcome.win);
      for (final missing in [_a, _b, _c, _sh]) {
        expect(simulate(_tiers, board([...all]..remove(missing))),
            SimOutcome.lose,
            reason: 'every piece but D is needed');
      }
      expect(simulate(_tiers, board([...all]..remove(_d))), SimOutcome.win);
      // The shield's spare cell, and that it is the only one.
      expect(
          simulate(_tiers, {
            ...board([_a, _b, _c]),
            3 * 5 + 2: _sh.element,
          }),
          SimOutcome.win);
    });

    test('hidden first, then spare room, then what Play shows, then the exit',
        () {
      // Fed in route order — the order the old hints used, which led with A.
      final plan = hintOrder(_tiers, [_sh, _a, _b, _c, _d]);
      expect(plan, [_b, _sh, _a, _c, _d]);
    });

    test('the order does not depend on how the solution was written down', () {
      expect(hintOrder(_tiers, [_d, _c, _b, _a, _sh]), [_b, _sh, _a, _c, _d]);
    });
  });

  group('every level', () {
    final levels = [
      for (final n in levelIds)
        if (recordedSolution(n).length > 1) n,
    ];

    test('hints still give away exactly the recorded solution', () {
      for (final n in levels) {
        final sol = recordedSolution(n);
        final plan = hintOrder(levelDataFor(n)!, sol);
        expect(plan.toSet(), sol.toSet(), reason: 'level $n');
        expect(plan.length, sol.length, reason: 'level $n');
      }
    });

    test('the first hint is never the turn into the exit', () {
      for (final n in levels) {
        final level = levelDataFor(n)!;
        final sol = recordedSolution(n);
        final size = level.size;
        final placed = {for (final p in sol) p.r * size + p.c: p.element};
        final route = <int>[];
        simulateDetailed(level, placed, trail: route);
        // The turn home: the piece the dot meets last, met for the first time,
        // with nothing the player placed after it. A route that comes back
        // over its own pieces has none — level 73 passes its portal again on
        // the way in, and that portal is the level's trick, not its last turn.
        final firstMet = {
          for (final p in sol) p: route.indexOf(p.r * size + p.c),
        };
        final last = sol.where((p) {
          final at = firstMet[p]!;
          return at >= 0 &&
              !route
                  .skip(at + 1)
                  .any((k) => k != p.r * size + p.c && placed.containsKey(k));
        }).toList();
        if (last.isEmpty) continue;
        final turns = last.single.element.type == PlacedType.arrow ||
            last.single.element.type == PlacedType.teleporter;
        if (!turns) continue; // a shield or pause last is no gift from the exit
        expect(hintOrder(level, sol).first, isNot(last.single),
            reason: 'level $n opens with the turn the exit already shows');
      }
    });

    test('a piece the level does not need is given away last', () {
      for (final n in levels) {
        final level = levelDataFor(n)!;
        final sol = recordedSolution(n);
        final size = level.size;
        final placed = {for (final p in sol) p.r * size + p.c: p.element};
        final plan = hintOrder(level, sol);
        for (final p in sol) {
          final without = {...placed}..remove(p.r * size + p.c);
          if (simulate(level, without) != SimOutcome.win) continue;
          // Level 77's spare up arrow at (6,1) is the case in point: the old
          // order gave it away first.
          final needed = plan.where((q) {
            final w = {...placed}..remove(q.r * size + q.c);
            return simulate(level, w) != SimOutcome.win;
          });
          expect(plan.indexOf(p), greaterThanOrEqualTo(needed.length),
              reason: 'level $n hands out a piece it does not need before '
                  'one it does');
        }
      }
    });
  });
}
