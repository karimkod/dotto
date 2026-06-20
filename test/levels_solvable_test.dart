// Verifies every level (World 1: 1–15, World 2: 16–20, World 3: 21–35): that it
// is solvable, that the intended hand-authored solution actually wins, and that
// every level is "tight" (no solution leaves a toolkit piece unused). Doubles
// as the "level solver" the design called for.

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dotto/data/level_definitions.dart';
import 'package:dotto/engine/level_solver.dart';
import 'package:dotto/engine/simulator.dart';
import 'package:dotto/models/game_state.dart';
import 'package:dotto/models/grid_cell.dart';
import 'package:dotto/models/level_data.dart';

/// Build a placement map from arrows ((r,c,dir)) and shields ((r,c)).
Map<int, PlacedElement> place(
  LevelData level,
  List<(int, int, Direction)> arrows, [
  List<(int, int)> shields = const [],
]) {
  return {
    for (final (r, c, dir) in arrows)
      r * level.size + c: PlacedElement(
        type: PlacedType.arrow,
        tool: dir.arrowTool,
        direction: dir,
      ),
    for (final (r, c) in shields)
      r * level.size + c: const PlacedElement(
        type: PlacedType.shield,
        tool: ToolType.shield,
        direction: null,
      ),
  };
}

void main() {
  // Intended arrow placements per level (empty where the kit is shields-only).
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
    // ----- World 2 (16–20): the five hand-picked destroyer levels. -----
    16: [(3, 1, Direction.up)],
    17: [(0, 2, Direction.left), (0, 0, Direction.down), (4, 0, Direction.right)],
    18: [(5, 3, Direction.up), (2, 3, Direction.right), (2, 5, Direction.up)],
    19: [(2, 5, Direction.left), (2, 3, Direction.down), (5, 3, Direction.left)],
    20: [(3, 2, Direction.right), (3, 4, Direction.up), (0, 4, Direction.right)],
    // ----- World 3 (21–35): arrows here, shields in `shields` below. -----
    21: [],
    22: [
      (0, 3, Direction.right),
      (4, 3, Direction.up),
      (4, 4, Direction.left),
    ],
    23: [
      (0, 1, Direction.down),
      (0, 3, Direction.left),
      (2, 3, Direction.up),
      (3, 1, Direction.right),
      (3, 4, Direction.down),
    ],
    24: [(0, 1, Direction.right), (2, 1, Direction.up)],
    25: [], // shields only (see below)
    26: [
      (0, 5, Direction.left),
      (2, 0, Direction.right),
      (2, 5, Direction.up),
      (4, 2, Direction.right),
      (4, 5, Direction.down),
    ],
    27: [
      (2, 5, Direction.down),
      (3, 0, Direction.down),
      (3, 5, Direction.left),
      (5, 0, Direction.right),
    ],
    28: [(0, 3, Direction.down), (5, 3, Direction.right)],
    29: [(0, 6, Direction.down)],
    30: [(1, 4, Direction.down)],
    31: [(0, 1, Direction.down), (5, 1, Direction.right)],
    32: [(6, 6, Direction.up)],
    33: [(0, 3, Direction.down), (6, 3, Direction.right)],
    34: [(0, 2, Direction.down), (7, 2, Direction.right)],
    35: [(0, 4, Direction.down), (7, 4, Direction.right)],
  };

  // Intended shield placements (World 3 only).
  final shields = <int, List<(int, int)>>{
    21: [(3, 2)],
    22: [(2, 2)],
    23: [(3, 2)],
    24: [(1, 1)],
    25: [(4, 1), (3, 4)],
    26: [(2, 1), (4, 3)],
    27: [(2, 2), (3, 4)],
    28: [(0, 2)],
    29: [(0, 2)],
    30: [(1, 1), (2, 4)],
    31: [(5, 2)],
    32: [(6, 1)],
    33: [(5, 3)],
    34: [(7, 4)],
    35: [(6, 4)],
  };

  int worldOf(int n) => n <= 15 ? 1 : (n <= 20 ? 2 : 3);

  for (var n = 1; n <= 35; n++) {
    test('World ${worldOf(n)} — level $n is solvable', () {
      final level = levelDataFor(n)!;
      final solutions = pathSolve(level);
      debugPrint('Level $n "${level.title}": ${solutions.length} solution(s)');
      expect(solutions, isNotEmpty,
          reason: 'level $n should have at least one solution');
    });

    test('World ${worldOf(n)} — level $n intended solution wins', () {
      final level = levelDataFor(n)!;
      expect(
          simulate(level, place(level, intended[n]!, shields[n] ?? const [])),
          SimOutcome.win,
          reason: 'the recorded solution for level $n must win');
    });
  }

  // Every level (with a toolkit) must require its whole toolkit — no piece can
  // be left unused, so the Play-gating never forces a wasted placement.
  for (var n = 2; n <= 35; n++) {
    test('World ${worldOf(n)} — level $n requires every toolkit piece', () {
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
  for (final n in [7, 8, 11, 12, 13, 14, 15, 19, 20, 22, 25, 27, 29]) {
    test('level $n forced arrow is on the solution path', () {
      final level = levelDataFor(n)!;
      final visited =
          tracePath(level, place(level, intended[n]!, shields[n] ?? const []));
      expect(visited, isNotNull);
      for (final a in level.forcedArrows) {
        expect(visited!.contains(a.r * level.size + a.c), isTrue,
            reason: 'the dot must pass through the forced arrow at '
                '(${a.r},${a.c})');
      }
    });
  }

  // World 3 spot-check: the chain explosion is genuinely required.
  test('World 3 — Break Through (24) needs the shield to clear the wall', () {
    final level = levelDataFor(24)!;
    const arrows = [(0, 1, Direction.right), (2, 1, Direction.up)];
    // The shield blasts the wall blocking the exit; the same arrows without it
    // run the dot into the destroyer.
    expect(simulate(level, place(level, arrows, const [(1, 1)])),
        SimOutcome.win);
    expect(simulate(level, place(level, arrows)), SimOutcome.lose);
  });
}
