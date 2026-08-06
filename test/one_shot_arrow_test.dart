// One-shot arrows: player-placed arrows the dot uses up. It turns exactly once
// on one, and the cell is empty for the rest of the run — so the same board
// answers differently on a later pass.

import 'package:flutter_test/flutter_test.dart';

import 'package:dotto/data/level_definitions.dart';
import 'package:dotto/engine/level_solver.dart';
import 'package:dotto/engine/simulator.dart';
import 'package:dotto/models/game_state.dart';
import 'package:dotto/models/grid_cell.dart';
import 'package:dotto/models/level_data.dart';

PlacedElement oneShot(Direction d) => PlacedElement(
      type: PlacedType.arrow,
      tool: d.oneShotTool,
      direction: d,
    );

PlacedElement plainArrow(Direction d) => PlacedElement(
      type: PlacedType.arrow,
      tool: d.arrowTool,
      direction: d,
    );

void main() {
  group('the tool type', () {
    test('one-shots are arrows that know they are single-use', () {
      for (final t in [
        ToolType.oneShotUp,
        ToolType.oneShotDown,
        ToolType.oneShotLeft,
        ToolType.oneShotRight,
      ]) {
        expect(t.placedType, PlacedType.arrow,
            reason: 'a one-shot must place, paint and solve as an arrow');
        expect(t.isOneShot, isTrue);
        expect(t.direction, isNotNull);
      }
      for (final t in [
        ToolType.arrowUp,
        ToolType.pause,
        ToolType.teleporter,
        ToolType.shield,
      ]) {
        expect(t.isOneShot, isFalse);
      }
    });

    test('every direction maps to its own pair of arrows', () {
      for (final d in Direction.values) {
        expect(d.oneShotTool.direction, d);
        expect(d.oneShotTool.isOneShot, isTrue);
        expect(d.arrowTool.direction, d);
        expect(d.arrowTool.isOneShot, isFalse);
        expect(d.oneShotTool, isNot(d.arrowTool));
      }
    });
  });

  // A corridor the dot runs down twice: it turns on the arrow at (2,2) going
  // east, the pinned arrow at (0,2) sends it back, and what happens on the
  // second pass is the whole difference between the two arrow kinds.
  const board = LevelData(
    id: 9070,
    size: 5,
    title: 'one-shot',
    tip: '',
    start: StartSpec(2, 0, Direction.right),
    exit: Pos(4, 2),
    forcedArrows: [ForcedArrow(0, 2, Direction.down)],
    toolkit: [ToolkitEntry(ToolType.oneShotUp, 1)],
  );

  group('using one up', () {
    test('a one-shot turns the dot, then lets it through', () {
      expect(simulate(board, {2 * 5 + 2: oneShot(Direction.up)}),
          SimOutcome.win);
    });

    test('an ordinary arrow in the same cell loops forever', () {
      // Turned north again on the way back down, the dot never escapes the
      // column — which is exactly the behaviour the one-shot exists to avoid.
      expect(simulate(board, {2 * 5 + 2: plainArrow(Direction.up)}),
          isNot(SimOutcome.win));
    });

    test('the bare board runs off the east edge', () {
      final res = simulateDetailed(board, const {});
      expect(res.outcome, SimOutcome.lose);
      expect(res.cause, DeathCause.edge);
    });

    test('the path crosses the spent cell twice', () {
      final path = tracePath(board, {2 * 5 + 2: oneShot(Direction.up)});
      expect(path, isNotNull, reason: 'the recorded solution must win');
      // Up through the turn, and back down through the empty cell below it.
      expect(path, contains(2 * 5 + 2)); // the one-shot's own cell
      expect(path, contains(0 * 5 + 2)); // the pinned arrow that turns it back
      expect(path, contains(4 * 5 + 2)); // the exit under the spent cell
    });
  });

  group('solver routing', () {
    test('one-shots are opaque to the clockless path solver', () {
      expect(needsBruteSolver(board), isTrue,
          reason: 'the board mutates mid-run as the arrow is used up');
      expect(needsExhaustiveSolver(board), isTrue);
      expect(() => pathSolve(board), throwsA(isA<PathSolverUnsupported>()));
      expect(() => pathMinPieces(board), throwsA(isA<PathSolverUnsupported>()));
    });

    test('the brute solver models the consumption', () {
      final sols = enumerateSolutions(board);
      expect(sols, isNotEmpty);
      for (final s in sols) {
        expect(simulate(board, s), SimOutcome.win,
            reason: 'a reported solution must really win');
      }
    });
  });

  group('level 92', () {
    test('is solvable, TIGHT and unique', () {
      final lvl = levelDataFor(92)!;
      expect(lvl.toolkit.single.type, ToolType.oneShotUp);
      final sols = enumerateSolutions(lvl);
      expect(sols, isNotEmpty, reason: 'the opener must be solvable');
      final min = sols.map((s) => s.length).reduce((a, b) => a < b ? a : b);
      expect(min, toolkitTotal(lvl), reason: 'the one arrow is load-bearing');
      expect(sols.length, 1,
          reason: 'only (2,2) is caught by the pinned arrow above it');
      expect(sols.single.keys.single, 2 * lvl.size + 2);
    });
  });
}
