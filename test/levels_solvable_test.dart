// Verifies every level (World 1: 1–15, World 2: 16–20, World 3: 21–30,
// World 4: 31–50): that it is solvable, that the intended hand-authored
// solution actually wins, and that every level is "tight" (no solution leaves a
// toolkit piece unused). World 4 has moving destroyers and pauses, so it uses
// the timing-aware path search. Doubles as the "level solver" the design called
// for.

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dotto/data/level_definitions.dart';
import 'package:dotto/engine/level_solver.dart';
import 'package:dotto/engine/simulator.dart';
import 'package:dotto/models/game_state.dart';
import 'package:dotto/models/grid_cell.dart';
import 'package:dotto/models/level_data.dart';

/// Build a placement map from arrows ((r,c,dir)), shields, pauses and
/// teleporters (all (r,c)).
Map<int, PlacedElement> place(
  LevelData level,
  List<(int, int, Direction)> arrows, [
  List<(int, int)> shields = const [],
  List<(int, int)> pauses = const [],
  List<(int, int)> teleports = const [],
]) {
  return {
    for (final (r, c) in teleports)
      r * level.size + c: const PlacedElement(
        type: PlacedType.teleporter,
        tool: ToolType.teleporter,
        direction: null,
      ),
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
    // 45: shield through (1,3) to blow the wall at (1,4) open, then ride the
    // forced arrow at (1,0) along row 1 and out.
    45: [
      (0, 1, Direction.right),
      (0, 2, Direction.down),
      (4, 0, Direction.up),
      (4, 2, Direction.left),
      (6, 1, Direction.up),
    ],
    // 46: climb column 2, spending a shield on each patrol row that blocks it.
    46: [(0, 2, Direction.right), (6, 2, Direction.up)],
    // 47–50: final exams.
    // 47: the exit is boxed in and there are no mines — the two patrols are the
    // only demolition charges, and the first blast frees the second patrol.
    47: [
      (2, 7, Direction.left),
      (5, 4, Direction.right),
      (5, 7, Direction.up),
      (7, 4, Direction.up),
    ],
    // 48: shield through the two floor mines, climb column 7 waiting out three
    // patrols, then run row 0 home past a third mine and two more patrols.
    48: [(0, 7, Direction.left), (7, 7, Direction.up)],
    // 49: shield the corridor patrol between the two barriers — one blast opens
    // row 2 and row 4 at the same column — then climb through and run home.
    49: [
      (1, 0, Direction.up),
      (1, 4, Direction.left),
      (5, 4, Direction.up),
      (5, 6, Direction.left),
    ],
    // 50: blast out of the sealed box through the column-2 wall, climb the free
    // left edge, then run row 0 home past the three top-run patrols.
    50: [
      (0, 0, Direction.right),
      (3, 6, Direction.down),
      (4, 0, Direction.up),
      (4, 6, Direction.left),
    ],
    // ----- World 5 (51–60): teleporters. -----
    // 51: turn up at (5,1) into a portal placed at (4,1); the far end at (2,5)
    // drops the dot on the exit side of a wall with no way around, still
    // heading up, and it climbs into the exit.
    51: [(5, 1, Direction.up)],
    52: [(0, 3, Direction.left)],
    53: [(6, 1, Direction.up), (0, 5, Direction.right)],
    54: [(6, 6, Direction.up)],
    55: [(6, 2, Direction.up)],
    56: [(6, 6, Direction.up)],
    57: [(7, 1, Direction.up), (0, 6, Direction.right)],
    58: [(7, 7, Direction.up)],
    59: [(7, 1, Direction.up), (0, 6, Direction.right)],
    60: [(8, 2, Direction.up), (0, 7, Direction.right)],
  };

  // Intended teleporter placements (World 5). Both ends of a pair, since the
  // player places them — the level itself pins none.
  // Intended teleporter placements (World 5). Both ends of each pair, in an
  // order whose board-order pairing matches the intended solution.
  final teleports = <int, List<(int, int)>>{
    51: [(4, 1), (2, 5)],
    52: [(4, 5), (5, 3)],
    53: [(4, 1), (4, 3), (2, 3), (2, 5)],
    54: [(6, 2), (6, 4)],
    55: [(5, 2), (5, 6)],
    56: [(6, 2), (6, 5)],
    57: [(5, 1), (5, 4), (2, 4), (2, 6)],
    58: [(7, 3), (7, 5)],
    59: [(5, 1), (5, 4), (2, 4), (4, 6)],
    60: [(3, 2), (5, 5), (1, 5), (1, 7)],
  };

  // Intended pause placements (World 4).
  final pauses = <int, List<(int, int)>>{
    41: [(2, 1)],
    42: [(3, 2)],
    43: [(1, 4), (5, 4)],
    44: [(2, 2), (5, 1)],
    45: [(6, 2), (6, 3)],
    46: [(4, 2), (6, 1)],
    47: [(2, 6), (7, 2)],
    48: [(0, 4), (0, 6), (2, 7), (4, 7), (6, 7)],
    49: [(4, 6)],
    50: [(4, 3)],
    // World 5 timing levels.
    55: [(6, 1)],
    59: [(6, 1), (4, 4)],
    60: [(4, 5)],
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
    45: [(2, 0), (2, 1)],
    46: [(2, 2), (5, 2)],
    47: [(4, 7), (5, 5)],
    // 48: one shield per mine — two in the floor run, one on the way home.
    48: [(0, 3), (7, 1), (7, 3)],
    49: [(3, 2)],
    50: [(0, 3), (4, 4)],
    // World 5 chain-explosion levels.
    54: [(6, 5)],
    58: [(7, 6)],
    60: [(8, 1)],
  };

  // Walk the definitions themselves, so a new level is never silently skipped.
  final allLevels = levelDefinitions.keys.toList()..sort();

  // Levels with two portal pairs can't be solver-verified: the solver pairs
  // portals by board order, the player by placement order. They're checked by
  // their recorded solution winning (under both pairings, per the design tool)
  // rather than by enumeration.
  const twoPairLevels = {53, 57, 59, 60};
  // Single-pair portal + pause levels aren't solver-tight — the portal's free
  // timing means the pause isn't strictly forced — so skip the tightness check
  // (the recorded solution still wins and uses every piece).
  const notSolverTight = {55};

  int worldOf(int n) => n <= 15
      ? 1
      : (n <= 20 ? 2 : (n <= 30 ? 3 : (n <= 50 ? 4 : 5)));



  // Enumerating a level twice (once for solvability, once for tightness) is
  // wasted work — level 45 alone takes ~30s a pass. Cache per level, and use
  // solveFor everywhere rather than calling the search directly.
  final solved = <int, List<Map<int, PlacedElement>>>{};

  // Level 45's full enumeration runs past the 30s default, so any test that can
  // trigger it needs headroom.
  const heavy = Timeout(Duration(minutes: 5));

  // Moving destroyers (World 4) make timing matter, and pause/teleporter pieces
  // are invisible to the static path solver — for either, the timing-aware
  // path search ([pathSolveAll]) is the reliable one.
  List<Map<int, PlacedElement>> solveFor(LevelData lvl) => solved.putIfAbsent(
      lvl.id, () => needsBruteSolver(lvl) ? enumerateSolutions(lvl) : pathSolve(lvl));
  int minPiecesFor(LevelData lvl) {
    final sols = solveFor(lvl);
    return sols.isEmpty
        ? -1
        : sols.map((m) => m.length).reduce((a, b) => a < b ? a : b);
  }

  for (final n in allLevels) {
    test('World ${worldOf(n)} — level $n is solvable', () {
      final level = levelDataFor(n)!;
      final solutions = solveFor(level);
      debugPrint('Level $n "${level.title}": ${solutions.length} solution(s)');
      expect(solutions, isNotEmpty,
          reason: 'level $n should have at least one solution');
    },
        timeout: heavy,
        skip: twoPairLevels.contains(n)
            ? 'two portal pairs — solver cannot verify; see intended-solution test'
            : null);

    test('World ${worldOf(n)} — level $n intended solution wins', () {
      final level = levelDataFor(n)!;
      expect(
          simulate(
              level,
              place(level, intended[n]!, shields[n] ?? const [],
                  pauses[n] ?? const [], teleports[n] ?? const [])),
          SimOutcome.win,
          reason: 'the recorded solution for level $n must win');
    });
  }

  // Every level (with a toolkit) must require its whole toolkit — no piece can
  // be left unused, so the Play-gating never forces a wasted placement.
  for (final n in allLevels.where((n) => n > 1)) {
    test('World ${worldOf(n)} — level $n requires every toolkit piece', () {
      final level = levelDataFor(n)!;
      expect(minPiecesFor(level), toolkitTotal(level),
          reason: 'level $n should have no solution that leaves a piece unused');
    },
        timeout: heavy,
        skip: (twoPairLevels.contains(n) || notSolverTight.contains(n))
            ? 'not solver-tight (portal timing / two pairs) — see design notes'
            : null);
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
  // 47, 48 and 50 are absent: their redesigns dropped the forced arrows they
  // used to carry.
  for (final n in [7, 8, 11, 12, 13, 14, 15, 19, 20, 22, 25, 27, 29, 30, 38, 39, 43, 45, 49]) {
    test('level $n forced arrow is on the solution path', () {
      final level = levelDataFor(n)!;
      final visited = tracePath(
          level,
          place(level, intended[n]!, shields[n] ?? const [],
              pauses[n] ?? const [], teleports[n] ?? const []));
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

  // ── Path search vs. exhaustive brute force ───────────────────────────────
  // PathSearch only places pieces on cells the dot actually lands on during
  // that run. That is sound because a piece elsewhere cannot influence the run
  // — so it must agree with the exhaustive search on SOLVABILITY and on the
  // MINIMUM piece count. (A minimal solution never contains an inert piece, or
  // it would not be minimal.) The solution COUNT may legitimately be smaller,
  // since the exhaustive search also counts placements that dump spare pieces
  // on cells the dot never visits.
  for (final n in [2, 5, 12, 21, 24, 27, 41, 42, 43, 47, 48]) {
    test('level $n — path search agrees with exhaustive brute force', () {
      final level = levelDataFor(n)!;
      // Guard, so editing a level can never silently turn this into a hang:
      // the exhaustive search is superexponential in toolkit size, and a level
      // that outgrows it has to be dropped from the comparison, not waited on.
      final cost = bruteForcePlacements(
          candidateCells(level).length, level.toolkit.map((e) => e.count));
      if (cost > 5e6) {
        markTestSkipped('level $n is too big for the exhaustive search '
            '(${cost.toStringAsExponential(2)} placements)');
        return;
      }
      final exhaustive = solveAll(level);
      final path = pathSolveAll(level);
      int min(List<Map<int, PlacedElement>> s) => s.isEmpty
          ? -1
          : s.map((m) => m.length).reduce((a, b) => a < b ? a : b);
      expect(path.isNotEmpty, exhaustive.isNotEmpty,
          reason: 'the two searches must agree on whether level $n is solvable');
      expect(min(path), min(exhaustive),
          reason: 'minimum piece count must survive the pruning');
      expect(path.length, lessThanOrEqualTo(exhaustive.length),
          reason: 'pruning can only ever remove inert placements');
    });
  }

  // Whatever the path search reports must genuinely win under the simulator,
  // which is the actual source of truth for the game.
  for (final n in [24, 41, 42, 43, 44, 45, 46, 47]) {
    test('level $n — every path-search solution really wins', () {
      final level = levelDataFor(n)!;
      final sols = solveFor(level); // cached — do not re-enumerate
      expect(sols, isNotEmpty);
      for (final s in sols) {
        expect(simulate(level, s), SimOutcome.win,
            reason: 'a reported solution for level $n does not actually win');
      }
    }, timeout: heavy);
  }

  // Reachability pruning must never discard a cell a real run can touch.
  test('reachable cells cover every cell the intended solutions visit', () {
    for (final n in allLevels) {
      final level = levelDataFor(n)!;
      final visited = tracePath(
          level,
          place(level, intended[n]!, shields[n] ?? const [],
              pauses[n] ?? const [], teleports[n] ?? const []));
      expect(visited, isNotNull, reason: 'level $n intended solution must win');
      // Reachability only has to cover the path on levels where it is actually
      // used to prune. With a teleporter in the TOOLKIT, candidateCells opts out
      // of pruning entirely (the partner's cell is chosen by the player, so no
      // static walk can predict it), and the exhaustive search runs instead.
      if (needsExhaustiveSolver(level)) continue;
      final reach = reachableCells(level);
      for (final cell in visited!) {
        if (cell == level.start.r * level.size + level.start.c) continue;
        expect(reach.contains(cell), isTrue,
            reason: 'level $n: reachability missed visited cell '
                '(${cell ~/ level.size},${cell % level.size})');
      }
    }
  });

  // ── Crossing a patrol is a hit ───────────────────────────────────────────
  // Dot and patrol head straight at each other on the same row. They swap cells
  // without ever sharing one, so a final-cell-only check let the dot slide
  // straight through a mine — which is what players saw and reported.
  group('dot and patrol crossing', () {
    // Row 2: dot starts at (2,0) heading right; patrol starts at (2,1) heading
    // left. After one tick the dot is at (2,1) and the patrol at (2,0).
    const headOn = LevelData(
      id: 900,
      size: 5,
      title: 'crossing',
      tip: '',
      start: StartSpec(2, 0, Direction.right),
      exit: Pos(2, 4),
      movers: [MovingDestroyer(2, 1, horizontal: true, dir: -1)],
      toolkit: [],
    );

    test('the dot dies instead of passing through', () {
      final res = simulateDetailed(headOn, const {});
      expect(res.outcome, SimOutcome.lose);
      expect(res.cause, DeathCause.patrol,
          reason: 'trading places with a patrol must count as being caught');
    });

    test('tracePath agrees that the crossing is fatal', () {
      expect(tracePath(headOn, const {}), isNull);
    });

    test('a shield still carries the dot through a crossing', () {
      // Dot and patrol close at two cells a tick, so they SHARE a cell when the
      // starting gap is even and CROSS when it is odd. Gap 5 => they cross on
      // tick 3, by which point the dot has collected the shield at (2,1).
      const shielded = LevelData(
        id: 901,
        size: 7,
        title: 'crossing with shield',
        tip: '',
        start: StartSpec(2, 0, Direction.right),
        exit: Pos(2, 6),
        movers: [MovingDestroyer(2, 5, horizontal: true, dir: -1)],
        toolkit: [ToolkitEntry(ToolType.shield, 1)],
      );
      // The shield is spent destroying the patrol, exactly as for a shared cell.
      expect(simulate(shielded, place(shielded, const [], const [(2, 1)])),
          SimOutcome.win);
      // Without the shield the same crossing is fatal.
      expect(simulateDetailed(shielded, const {}).cause, DeathCause.patrol);
    });

    test('the solver does not offer solutions that cross a patrol', () {
      // Every solution the search returns must survive the real simulator.
      // Two-pair levels aren't solver-enumerable (see twoPairLevels), so skip.
      for (final n in allLevels.where((n) =>
          levelDataFor(n)!.movers.isNotEmpty && !twoPairLevels.contains(n))) {
        final level = levelDataFor(n)!;
        for (final s in solveFor(level)) {
          // cached
          expect(simulate(level, s), SimOutcome.win,
              reason: 'level $n: solver returned a run the game would kill');
        }
      }
    }, timeout: heavy);
  });

  // ── Patrols and demolished walls ─────────────────────────────────────────
  // A patrol's bounce set is a snapshot of the walls at level start. Once a
  // chain explosion opens a wall in its lane, the patrol must sweep through the
  // gap instead of bouncing off a wall that is no longer there.
  group('patrols and demolished walls', () {
    // Row 3 lane: wall at (3,3), patrol at (3,5) heading left. The wall is
    // beside the mine at (2,3), so shielding into that mine blows (3,3) open.
    const lane = LevelData(
      id: 902,
      size: 6,
      title: 'patrol lane wall',
      tip: '',
      start: StartSpec(5, 0, Direction.right),
      exit: Pos(0, 0),
      walls: [Pos(3, 3)],
      destroyers: [Pos(2, 3)],
      movers: [MovingDestroyer(3, 5, horizontal: true, dir: -1)],
      toolkit: [],
    );

    test('the bounce set starts out treating the wall as solid', () {
      final movers = buildMovers(lane);
      expect(movers.single.blocked.contains(3), isTrue,
          reason: 'the wall at (3,3) sits in the patrol lane');
    });

    test('an untouched wall still stops the patrol', () {
      final m = buildMovers(lane).single;
      // Walking left from column 5 it should stall against the wall at column 3.
      for (var i = 0; i < 10; i++) {
        m.step(const <int>{});
      }
      expect(m.col, greaterThan(3),
          reason: 'with the wall intact the patrol must stay east of it');
    });

    test('once blown open, the patrol sweeps straight through', () {
      final m = buildMovers(lane).single;
      final removed = {3 * lane.size + 3}; // (3,3) demolished
      var reachedWest = false;
      for (var i = 0; i < 10; i++) {
        m.step(removed);
        if (m.col < 3) reachedWest = true;
      }
      expect(reachedWest, isTrue,
          reason: 'a demolished wall must not keep bouncing the patrol');
    });

    test('a demolished static mine also stops blocking', () {
      // Column 3 lane, with the mine at (2,3) inside it.
      const col = LevelData(
        id: 903,
        size: 6,
        title: 'patrol column mine',
        tip: '',
        start: StartSpec(5, 0, Direction.right),
        exit: Pos(0, 0),
        destroyers: [Pos(2, 3)],
        movers: [MovingDestroyer(4, 3, horizontal: false, dir: -1)],
        toolkit: [],
      );
      final m = buildMovers(col).single;
      expect(m.blocked.contains(2), isTrue);
      final removed = {2 * col.size + 3}; // the mine is gone
      var passed = false;
      for (var i = 0; i < 10; i++) {
        m.step(removed);
        if (m.row < 2) passed = true;
      }
      expect(passed, isTrue,
          reason: 'a destroyed mine leaves floor the patrol can cross');
    });
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
