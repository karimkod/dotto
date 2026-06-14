// Verifies every World 1 level: that it is solvable (the brute-force solver
// finds at least one solution) and that the intended hand-authored solution
// actually wins. Doubles as the "level solver" the design called for.

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
    1: [],
    2: [(2, 2, Direction.up)],
    3: [(2, 0, Direction.right)],
    4: [(2, 2, Direction.left), (2, 0, Direction.up)],
    5: [(3, 2, Direction.up), (0, 2, Direction.left)],
    6: [(1, 0, Direction.right), (1, 3, Direction.down), (4, 3, Direction.right)],
    7: [(3, 1, Direction.left)],
    8: [(0, 0, Direction.right), (0, 4, Direction.down)],
    9: [(1, 4, Direction.left), (1, 1, Direction.down), (4, 1, Direction.left)],
    10: [(2, 3, Direction.down), (4, 3, Direction.right), (4, 5, Direction.down)],
    11: [(1, 0, Direction.right), (1, 3, Direction.down), (3, 3, Direction.left)],
    12: [(0, 4, Direction.down), (6, 2, Direction.up), (6, 6, Direction.up)],
    13: [(0, 1, Direction.down), (2, 2, Direction.right), (4, 5, Direction.down)],
    14: [(2, 6, Direction.left), (4, 0, Direction.right), (6, 6, Direction.left)],
    15: [
      (0, 7, Direction.down),
      (1, 0, Direction.down),
      (3, 7, Direction.down),
      (4, 0, Direction.down),
      (6, 7, Direction.down),
    ],
  };

  for (var n = 1; n <= 15; n++) {
    test('World 1 — level $n is solvable', () {
      final level = levelDataFor(n)!;
      // Path-based solver — scales to the large open exam grids where the
      // brute-force `solveAll` would be far too slow.
      final solutions = pathSolve(level);
      debugPrint('Level $n "${level.title}": ${solutions.length} solution(s)');
      expect(solutions, isNotEmpty,
          reason: 'level $n should have at least one solution');
    });

    test('World 1 — level $n intended solution wins', () {
      final level = levelDataFor(n)!;
      expect(simulate(level, place(level, intended[n]!)), SimOutcome.win);
    });
  }

  // Every level (with a toolkit) must require its whole toolkit — no piece can
  // be left unused, so the Play-gating never forces a wasted placement.
  for (var n = 2; n <= 15; n++) {
    test('World 1 — level $n requires every toolkit piece', () {
      final level = levelDataFor(n)!;
      expect(pathMinPieces(level), toolkitTotal(level),
          reason: 'level $n should have no solution that leaves a piece unused');
    });
  }

  // The exam levels (11–15) are designed to have a single solution, so the
  // player must work out the one route rather than stumble onto an alternative.
  for (final n in [11, 12, 13, 14, 15]) {
    test('World 1 — exam level $n has a unique solution', () {
      final level = levelDataFor(n)!;
      expect(pathSolve(level).length, 1,
          reason: 'exam level $n should have exactly one solution');
    });
  }

  // Forced arrows must lie on the winning path, not be decoys.
  for (final n in [7, 8, 11, 12, 13, 14, 15]) {
    test('World 1 — level $n forced arrow is on the solution path', () {
      final level = levelDataFor(n)!;
      final visited = tracePath(level, place(level, intended[n]!));
      expect(visited, isNotNull);
      for (final a in level.forcedArrows) {
        expect(visited!.contains(a.r * level.size + a.c), isTrue,
            reason: 'the dot must pass through the forced arrow');
      }
    });
  }
}
