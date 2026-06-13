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
    4: [(2, 1, Direction.up), (0, 1, Direction.right)],
    5: [(3, 1, Direction.up), (0, 1, Direction.right)],
    6: [(4, 1, Direction.up), (1, 1, Direction.right), (1, 4, Direction.up)],
    7: [(0, 3, Direction.down)],
    8: [(4, 1, Direction.up), (0, 1, Direction.right)],
    9: [(4, 1, Direction.up), (1, 1, Direction.right), (1, 4, Direction.up)],
    10: [(5, 1, Direction.up), (2, 1, Direction.right), (2, 5, Direction.up)],
  };

  for (var n = 1; n <= 10; n++) {
    test('World 1 — level $n is solvable', () {
      final level = levelDataFor(n)!;
      final solutions = solveAll(level);
      debugPrint('Level $n "${level.title}": ${solutions.length} solution(s)');
      expect(solutions, isNotEmpty,
          reason: 'level $n should have at least one solution');
    });

    test('World 1 — level $n intended solution wins', () {
      final level = levelDataFor(n)!;
      expect(simulate(level, place(level, intended[n]!)), SimOutcome.win);
    });
  }
}
