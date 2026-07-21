// Fixed shields and pauses: pinned to the board like a fixed arrow, behaving
// exactly like the player's own pieces once the run starts, but never placeable
// and never drawn from the toolkit.

import 'package:flutter_test/flutter_test.dart';

import 'package:dotto/data/level_definitions.dart';
import 'package:dotto/engine/level_solver.dart';
import 'package:dotto/engine/simulator.dart';
import 'package:dotto/models/grid_cell.dart';
import 'package:dotto/models/level_data.dart';

void main() {
  group('fixed shield', () {
    // Row 0: dot runs right into a mine at (0,2). The only thing that can save
    // it is the shield pinned at (0,1) — the toolkit is empty.
    const level = LevelData(
      id: 950,
      size: 4,
      title: 'fixed shield',
      tip: '',
      start: StartSpec(0, 0, Direction.right),
      exit: Pos(0, 3),
      destroyers: [Pos(0, 2)],
      forcedShields: [Pos(0, 1)],
      toolkit: [],
    );

    test('is collected and survives the mine, with no toolkit at all', () {
      expect(simulate(level, const {}), SimOutcome.win);
    });

    test('without it the same board kills the dot', () {
      const bare = LevelData(
        id: 951,
        size: 4,
        title: 'no shield',
        tip: '',
        start: StartSpec(0, 0, Direction.right),
        exit: Pos(0, 3),
        destroyers: [Pos(0, 2)],
        toolkit: [],
      );
      expect(simulateDetailed(bare, const {}).cause, DeathCause.destroyer);
    });

    test('the solver sees it as already on the board', () {
      // Solvable with an empty toolkit means the solver placed nothing.
      final sols = pathSolveAll(level);
      expect(sols, isNotEmpty);
      expect(sols.first, isEmpty);
    });
  });

  group('fixed pause', () {
    // Row 2: a patrol sweeps the dot's path. The pause pinned at (2,1) is the
    // only way to let it clear, and the toolkit is empty.
    const level = LevelData(
      id: 952,
      size: 5,
      title: 'fixed pause',
      tip: '',
      start: StartSpec(2, 0, Direction.right),
      exit: Pos(2, 4),
      movers: [MovingDestroyer(4, 2, horizontal: false, dir: -1)],
      forcedPauses: [Pos(2, 1)],
      toolkit: [],
    );

    test('holds the dot so the patrol clears', () {
      expect(simulate(level, const {}), SimOutcome.win);
    });

    test('without it the patrol catches the dot', () {
      const bare = LevelData(
        id: 953,
        size: 5,
        title: 'no pause',
        tip: '',
        start: StartSpec(2, 0, Direction.right),
        exit: Pos(2, 4),
        movers: [MovingDestroyer(4, 2, horizontal: false, dir: -1)],
        toolkit: [],
      );
      expect(simulateDetailed(bare, const {}).cause, DeathCause.patrol);
    });
  });

  group('fixed pieces are not placeable', () {
    const level = LevelData(
      id: 954,
      size: 5,
      title: 'occupancy',
      tip: '',
      start: StartSpec(4, 0, Direction.right),
      exit: Pos(0, 4),
      forcedArrows: [ForcedArrow(4, 4, Direction.up)],
      forcedShields: [Pos(2, 2)],
      forcedPauses: [Pos(3, 3)],
      toolkit: [ToolkitEntry(ToolType.arrowUp, 1)],
    );

    test('hasForcedPieceAt covers all three kinds', () {
      expect(level.hasForcedPieceAt(4, 4), isTrue, reason: 'arrow');
      expect(level.hasForcedPieceAt(2, 2), isTrue, reason: 'shield');
      expect(level.hasForcedPieceAt(3, 3), isTrue, reason: 'pause');
      expect(level.hasForcedPieceAt(1, 1), isFalse);
    });

    test('the solver will not place a piece on any of them', () {
      final cells = placeableCells(level);
      const n = 5;
      expect(cells, isNot(contains(4 * n + 4)), reason: 'fixed arrow cell');
      expect(cells, isNot(contains(2 * n + 2)), reason: 'fixed shield cell');
      expect(cells, isNot(contains(3 * n + 3)), reason: 'fixed pause cell');
    });

    test('buildForcedPieces returns all three, typed correctly', () {
      final f = buildForcedPieces(level);
      const n = 5;
      expect(f[4 * n + 4]!.type, PlacedType.arrow);
      expect(f[4 * n + 4]!.direction, Direction.up);
      expect(f[2 * n + 2]!.type, PlacedType.shield);
      expect(f[3 * n + 3]!.type, PlacedType.pause);
      expect(f, hasLength(3));
    });
  });

  test('every shipped level still has no fixed shields or pauses', () {
    // The new fields default to empty, so this pins that adding them changed
    // nothing about the existing 50 levels.
    for (var n = 1; n <= 50; n++) {
      final lvl = levelDataFor(n)!;
      expect(lvl.forcedShields, isEmpty, reason: 'level $n');
      expect(lvl.forcedPauses, isEmpty, reason: 'level $n');
    }
  });
}
