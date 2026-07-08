// Verifies every level (World 1: 1–15, World 2: 16–20, World 3: 21–30,
// World 4: 31–50): that it is solvable, that the intended hand-authored
// solution actually wins, and that every level is "tight" (no solution leaves a
// toolkit piece unused). World 4 has moving destroyers, so it uses the
// timing-aware brute solver. Doubles as the "level solver" the design called
// for.

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dotto/data/level_definitions.dart';
import 'package:dotto/engine/level_solver.dart';
import 'package:dotto/engine/simulator.dart';
import 'package:dotto/models/game_state.dart';
import 'package:dotto/models/grid_cell.dart';
import 'package:dotto/models/level_data.dart';

/// Build a placement map from arrows ((r,c,dir)), shields ((r,c)) and pauses
/// ((r,c)).
Map<int, PlacedElement> place(
  LevelData level,
  List<(int, int, Direction)> arrows, [
  List<(int, int)> shields = const [],
  List<(int, int)> pauses = const [],
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
    for (final (r, c) in pauses)
      r * level.size + c: const PlacedElement(
        type: PlacedType.pause,
        tool: ToolType.pause,
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
    29: [
      (3, 2, Direction.right),
      (5, 4, Direction.right),
      (5, 6, Direction.down),
    ],
    30: [
      (3, 3, Direction.right),
      (3, 5, Direction.down),
      (5, 2, Direction.down),
      (5, 5, Direction.left),
    ],
    // ----- World 4 (31–46): arrows here, pauses/shields below. -----
    31: [(3, 3, Direction.up)],
    32: [(3, 3, Direction.right), (3, 4, Direction.up), (4, 3, Direction.up)],
    33: [(0, 5, Direction.left), (5, 5, Direction.up)],
    34: [(5, 1, Direction.up), (0, 1, Direction.left)],
    // 35–39: shield + patrol chain explosions (shields listed below).
    35: [(4, 2, Direction.up)],
    36: [(4, 3, Direction.up)],
    37: [(0, 5, Direction.left), (5, 5, Direction.up)],
    38: [(0, 5, Direction.down), (5, 3, Direction.up)],
    39: [(1, 6, Direction.left), (6, 6, Direction.up)],
    // 40: pure timing — weave around the sweeping patrol.
    40: [(2, 2, Direction.down), (5, 2, Direction.right), (5, 5, Direction.up)],
    // 41–46: timing puzzles (pauses listed below).
    41: [],
    42: [(4, 4, Direction.up)],
    43: [(5, 5, Direction.up)],
    44: [(0, 3, Direction.left), (5, 3, Direction.up)],
    45: [(5, 5, Direction.up)],
    46: [(6, 6, Direction.up)],
    // 47–50: final exams.
    47: [(5, 5, Direction.up)],
    48: [(6, 6, Direction.up)],
    49: [(6, 6, Direction.up)],
    50: [(7, 7, Direction.up)],
  };

  // Intended pause placements (World 4).
  final pauses = <int, List<(int, int)>>{
    41: [(2, 1)],
    42: [(4, 3)],
    43: [(5, 1), (5, 4)],
    45: [(5, 3), (5, 4)],
    46: [(6, 4), (6, 5)],
    47: [(5, 1)],
    48: [(6, 1)],
    49: [(6, 1)],
    50: [(7, 3)],
  };

  // Intended shield placements (World 3, plus World 4's chain-explosion levels).
  final shields = <int, List<(int, int)>>{
    21: [(3, 2)],
    22: [(2, 2)],
    23: [(3, 2)],
    24: [(1, 1)],
    25: [(4, 1), (3, 4)],
    26: [(2, 1), (4, 3)],
    27: [(2, 2), (3, 4)],
    28: [(0, 2)],
    29: [(1, 2), (3, 3)],
    30: [(1, 3), (3, 4), (5, 3)],
    35: [(4, 1)],
    36: [(4, 2)],
    37: [(5, 2), (5, 3)],
    38: [(5, 2)],
    39: [(3, 6), (6, 5)],
    44: [(5, 2)],
    47: [(5, 4)],
    48: [(6, 5)],
    49: [(6, 5), (3, 6)],
    50: [(7, 6)],
  };

  int worldOf(int n) =>
      n <= 15 ? 1 : (n <= 20 ? 2 : (n <= 30 ? 3 : 4));

  // World 4 (31+) has moving destroyers, so timing matters — only the
  // brute-force, simulate-based solver is reliable there.
  List<Map<int, PlacedElement>> solveFor(LevelData lvl) =>
      lvl.movers.isNotEmpty ? solveAll(lvl) : pathSolve(lvl);
  int minPiecesFor(LevelData lvl) =>
      lvl.movers.isNotEmpty ? minSolutionPieces(lvl) : pathMinPieces(lvl);

  for (var n = 1; n <= 50; n++) {
    test('World ${worldOf(n)} — level $n is solvable', () {
      final level = levelDataFor(n)!;
      final solutions = solveFor(level);
      debugPrint('Level $n "${level.title}": ${solutions.length} solution(s)');
      expect(solutions, isNotEmpty,
          reason: 'level $n should have at least one solution');
    });

    test('World ${worldOf(n)} — level $n intended solution wins', () {
      final level = levelDataFor(n)!;
      expect(
          simulate(
              level,
              place(level, intended[n]!, shields[n] ?? const [],
                  pauses[n] ?? const [])),
          SimOutcome.win,
          reason: 'the recorded solution for level $n must win');
    });
  }

  // Every level (with a toolkit) must require its whole toolkit — no piece can
  // be left unused, so the Play-gating never forces a wasted placement.
  for (var n = 2; n <= 50; n++) {
    test('World ${worldOf(n)} — level $n requires every toolkit piece', () {
      final level = levelDataFor(n)!;
      expect(minPiecesFor(level), toolkitTotal(level),
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
  for (final n in [7, 8, 11, 12, 13, 14, 15, 19, 20, 22, 25, 27, 29, 30, 38, 39, 47, 48, 49, 50]) {
    test('level $n forced arrow is on the solution path', () {
      final level = levelDataFor(n)!;
      final visited = tracePath(
          level,
          place(level, intended[n]!, shields[n] ?? const [],
              pauses[n] ?? const []));
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
