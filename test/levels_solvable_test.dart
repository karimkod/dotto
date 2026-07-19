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
    42: [(3, 3, Direction.up)],
    43: [(5, 0, Direction.up), (5, 5, Direction.left)],
    44: [(0, 2, Direction.left), (5, 2, Direction.up)],
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
    42: [(3, 2)],
    43: [(1, 4), (5, 4)],
    44: [(2, 2), (5, 1)],
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
    44: [(4, 2)],
    47: [(5, 4)],
    48: [(6, 5)],
    49: [(6, 5), (3, 6)],
    50: [(7, 6)],
  };

  int worldOf(int n) =>
      n <= 15 ? 1 : (n <= 20 ? 2 : (n <= 30 ? 3 : 4));

  // Moving destroyers (World 4) make timing matter, and pause/teleporter pieces
  // are invisible to the path solver — for either, only the brute-force,
  // simulate-based solver is reliable.
  List<Map<int, PlacedElement>> solveFor(LevelData lvl) =>
      needsBruteSolver(lvl) ? solveAll(lvl) : pathSolve(lvl);
  int minPiecesFor(LevelData lvl) =>
      needsBruteSolver(lvl) ? minSolutionPieces(lvl) : pathMinPieces(lvl);

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
  for (final n in [7, 8, 11, 12, 13, 14, 15, 19, 20, 22, 25, 27, 29, 30, 38, 39, 43, 47, 48, 49, 50]) {
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

  // ── Solver routing ───────────────────────────────────────────────────────
  // The path solver has no clock and never sees movers, so it cannot reason
  // about pause/teleporter. It used to drop those pieces from the toolkit
  // silently, which made pause levels look unsolvable (or "solvable" without
  // ever placing the pause). It must now refuse them, and routing must send
  // them to the brute force.
  for (final n in [41, 42, 43, 44]) {
    test('level $n (pause) routes to the brute solver and uses every pause', () {
      final level = levelDataFor(n)!;
      expect(needsBruteSolver(level), isTrue,
          reason: 'a pause in the toolkit means timing matters');
      expect(() => pathSolve(level), throwsA(isA<PathSolverUnsupported>()));
      expect(() => pathMinPieces(level), throwsA(isA<PathSolverUnsupported>()));

      final sols = solveAll(level);
      expect(sols, isNotEmpty, reason: 'level $n must be solvable');
      final pauses = level.toolkit
          .where((e) => e.type == ToolType.pause)
          .fold(0, (a, e) => a + e.count);
      for (final s in sols.where((s) => s.length == toolkitTotal(level))) {
        expect(s.values.where((e) => e.type == PlacedType.pause).length, pauses,
            reason: 'a full-toolkit solution must place every pause piece');
      }
    });
  }

  test('pause-free static levels still use the fast path solver', () {
    for (final n in [11, 12, 13, 14, 15]) {
      expect(needsBruteSolver(levelDataFor(n)!), isFalse);
    }
  });

  // The Find Toolkit cost guard must admit the real pause levels; the old
  // pow(placeable, total) estimate overstated them by orders of magnitude and
  // skipped 43 and 44 outright.
  test('brute-force cost estimate admits the authored pause levels', () {
    for (final n in [41, 42, 43, 44]) {
      final level = levelDataFor(n)!;
      final cost = bruteForcePlacements(
        placeableCells(level).length,
        level.toolkit.map((e) => e.count),
      );
      expect(cost, lessThanOrEqualTo(kMaxBrutePlacements),
          reason: 'level $n toolkit should be within the search budget');
    }
  });

  // ── Brute force: iterative DFS vs. the original recursion ────────────────
  // solveAll was rewritten as an explicit-stack search so it can be paused
  // mid-sweep (web has no isolates, so it runs in slices). The rewrite must
  // enumerate exactly the same space, so check it against a straight
  // transcription of the recursion it replaced.
  List<Map<int, PlacedElement>> referenceSolveAll(LevelData level) {
    final cells = placeableCells(level);
    final remaining = {for (final e in level.toolkit) e.type: e.count};
    final solutions = <Map<int, PlacedElement>>[];
    final current = <int, PlacedElement>{};
    void recurse(int i) {
      if (i == cells.length) {
        if (simulate(level, current) == SimOutcome.win) {
          solutions.add(Map.of(current));
        }
        return;
      }
      recurse(i + 1); // leave this cell empty
      final cell = cells[i];
      for (final type in remaining.keys) {
        if (remaining[type]! <= 0) continue;
        remaining[type] = remaining[type]! - 1;
        current[cell] = PlacedElement(
            type: type.placedType, tool: type, direction: type.direction);
        recurse(i + 1);
        current.remove(cell);
        remaining[type] = remaining[type]! + 1;
      }
    }

    recurse(0);
    return solutions;
  }

  String canon(Map<int, PlacedElement> m) {
    final keys = m.keys.toList()..sort();
    return keys.map((k) => '$k:${m[k]!.tool.name}').join(',');
  }

  for (final n in [2, 5, 12, 21, 24, 41, 42]) {
    test('level $n — iterative solveAll matches the reference recursion', () {
      final level = levelDataFor(n)!;
      final got = solveAll(level).map(canon).toList();
      final want = referenceSolveAll(level).map(canon).toList();
      expect(got, want,
          reason: 'the pausable search must explore the same space, in order');
    });
  }

  test('bruteStats agrees with solveAll', () {
    for (final n in [2, 5, 24, 41, 42, 44]) {
      final level = levelDataFor(n)!;
      final sols = solveAll(level);
      final stats = bruteStats(level);
      expect(stats.count, sols.length, reason: 'level $n solution count');
      expect(
          stats.minPieces,
          sols.isEmpty
              ? -1
              : sols.map((m) => m.length).reduce((a, b) => a < b ? a : b),
          reason: 'level $n min pieces');
    }
  });

  // Pausing must not corrupt the search: a sliced sweep sees the same wins as
  // an uninterrupted one. A 1-microsecond budget forces a pause at almost every
  // checkpoint, which is the worst case for resume bookkeeping.
  test('a sliced BruteSearch finds the same solutions as an unsliced one', () {
    for (final n in [5, 24, 41, 42]) {
      final level = levelDataFor(n)!;
      final sliced = <String>[];
      final search = BruteSearch(level, (p) => sliced.add(canon(p)));
      var slices = 0;
      while (!search.runSlice(const Duration(microseconds: 1))) {
        slices++;
        expect(slices, lessThan(1000000), reason: 'slicing must terminate');
      }
      expect(sliced, solveAll(level).map(canon).toList(),
          reason: 'level $n sliced sweep');
    }
  });

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
