// Verifies every level (World 1: 1–15, World 2: 16–30): that it is solvable,
// that the intended hand-authored solution actually wins, and that every level
// is "tight" (no solution leaves a toolkit piece unused). Doubles as the
// "level solver" the design called for.

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dotto/data/level_definitions.dart';
import 'package:dotto/engine/level_solver.dart';
import 'package:dotto/engine/simulator.dart';
import 'package:dotto/models/game_state.dart';
import 'package:dotto/models/grid_cell.dart';
import 'package:dotto/models/level_data.dart';

Map<int, PlacedElement> place(LevelData level, List<(int, int, Direction)> arrows) {
  return {
    for (final (r, c, dir) in arrows)
      r * level.size + c: PlacedElement(
        type: PlacedType.arrow,
        tool: dir.arrowTool,
        direction: dir,
      ),
  };
}

void main() {
  // The intended solution for each level (empty for the no-toolkit level 1).
  final intended = <int, List<(int, int, Direction)>>{
    // ----- World 1 -----
    1: [],
    2: [(2, 2, Direction.up)],
    3: [(2, 0, Direction.right)],
    4: [(2, 2, Direction.left), (2, 0, Direction.up)],
    5: [(3, 2, Direction.up), (0, 2, Direction.left)],
    6: [(0, 2, Direction.left), (0, 0, Direction.down), (4, 0, Direction.right)],
    7: [(3, 1, Direction.left)],
    8: [(0, 0, Direction.right), (0, 4, Direction.down)],
    9: [(4, 2, Direction.right), (4, 4, Direction.up), (0, 4, Direction.left)],
    10: [(2, 3, Direction.down), (4, 3, Direction.right), (4, 5, Direction.down)],
    11: [(1, 0, Direction.right), (1, 3, Direction.down), (3, 3, Direction.left)],
    12: [(0, 4, Direction.down), (6, 2, Direction.up), (6, 6, Direction.up)],
    13: [(0, 1, Direction.down), (2, 2, Direction.right), (4, 5, Direction.down)],
    14: [(0, 6, Direction.down), (2, 0, Direction.down), (4, 6, Direction.down)],
    15: [
      (7, 0, Direction.right),
      (0, 1, Direction.right),
      (7, 3, Direction.right),
      (0, 4, Direction.right),
      (7, 6, Direction.right),
    ],
    // ----- World 2 — Static Destroyers (player arrows only; forced arrows are
    // applied by the simulator automatically). -----
    16: [(3, 1, Direction.up)],
    17: [(1, 0, Direction.right), (1, 3, Direction.down)],
    18: [(0, 1, Direction.right), (4, 1, Direction.up)],
    19: [(0, 1, Direction.right), (4, 1, Direction.up)],
    20: [(0, 2, Direction.left), (0, 0, Direction.down), (4, 0, Direction.right)],
    21: [(5, 3, Direction.up), (2, 3, Direction.right), (2, 5, Direction.up)],
    22: [(0, 2, Direction.down), (5, 2, Direction.right)],
    23: [(5, 2, Direction.up), (3, 2, Direction.right), (3, 4, Direction.up)],
    24: [(2, 5, Direction.left), (2, 3, Direction.down), (5, 3, Direction.left)],
    25: [(3, 2, Direction.right), (3, 4, Direction.up), (0, 4, Direction.right)],
    26: [(0, 2, Direction.down), (2, 2, Direction.right), (2, 5, Direction.down)],
    27: [
      (0, 3, Direction.left),
      (0, 0, Direction.down),
      (6, 0, Direction.right),
      (6, 6, Direction.up),
    ],
    28: [(4, 2, Direction.right), (4, 4, Direction.down), (6, 4, Direction.right)],
    29: [(4, 3, Direction.right), (4, 4, Direction.up), (0, 4, Direction.right)],
    30: [
      (7, 2, Direction.up),
      (4, 2, Direction.right),
      (4, 3, Direction.up),
      (1, 3, Direction.right),
      (1, 7, Direction.up),
    ],
  };

  for (var n = 1; n <= 30; n++) {
    final world = n <= 15 ? 1 : 2;
    test('World $world — level $n is solvable', () {
      final level = levelDataFor(n)!;
      // Path-based solver — scales to the large open grids where the
      // brute-force `solveAll` would be far too slow.
      final solutions = pathSolve(level);
      debugPrint('Level $n "${level.title}": ${solutions.length} solution(s)');
      expect(solutions, isNotEmpty,
          reason: 'level $n should have at least one solution');
    });

    test('World $world — level $n intended solution wins', () {
      final level = levelDataFor(n)!;
      expect(simulate(level, place(level, intended[n]!)), SimOutcome.win,
          reason: 'the recorded solution for level $n must win');
    });
  }

  // Every level (with a toolkit) must require its whole toolkit — no piece can
  // be left unused, so the Play-gating never forces a wasted placement.
  for (var n = 2; n <= 30; n++) {
    final world = n <= 15 ? 1 : 2;
    test('World $world — level $n requires every toolkit piece', () {
      final level = levelDataFor(n)!;
      expect(pathMinPieces(level), toolkitTotal(level),
          reason: 'level $n should have no solution that leaves a piece unused');
    });
  }

  // The World 1 exam levels (11–15) are designed to have a single solution.
  for (final n in [11, 12, 13, 14, 15]) {
    test('World 1 — exam level $n has a unique solution', () {
      final level = levelDataFor(n)!;
      expect(pathSolve(level).length, 1,
          reason: 'exam level $n should have exactly one solution');
    });
  }

  // Forced arrows must lie on the winning path, not be decoys.
  for (final n in [7, 8, 11, 12, 13, 14, 15, 19, 22, 24, 25, 28, 29]) {
    test('level $n forced arrow is on the solution path', () {
      final level = levelDataFor(n)!;
      final visited = tracePath(level, place(level, intended[n]!));
      expect(visited, isNotNull);
      for (final a in level.forcedArrows) {
        expect(visited!.contains(a.r * level.size + a.c), isTrue,
            reason: 'the dot must pass through the forced arrow at '
                '(${a.r},${a.c})');
      }
    });
  }
}
