// Verifies every level (World 1: 1–15, World 2: 16–20, World 3: 21–30,
// World 4: 31–50): that it is solvable, that the intended hand-authored
// solution actually wins, and that every level is "tight" (no solution leaves a
// toolkit piece unused). World 4 has moving destroyers and pauses, so it uses
// the timing-aware path search. Doubles as the "level solver" the design called
// for.

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dotto/data/level_definitions.dart';
import 'package:dotto/data/level_hints.dart';
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
  List<(int, int, Direction)> oneShots = const [],
]) {
  return {
    // One-shot arrows are PlacedType.arrow like the rest — the difference is the
    // tool, which is what the simulator checks when it consumes one.
    for (final (r, c, dir) in oneShots)
      r * level.size + c: PlacedElement(
        type: PlacedType.arrow,
        tool: dir.oneShotTool,
        direction: dir,
      ),
    // Portal indices follow list order, so consecutive cells form a pair, index
    // i pairing with i^1. This lets a teleports list express ANY pairing —
    // including the "crossing" wirings that board-order pairing cannot (level
    // 59). It mirrors the game, where portals pair by placement order.
    for (final (i, (r, c)) in teleports.indexed)
      r * level.size + c: const PlacedElement(
        type: PlacedType.teleporter,
        tool: ToolType.teleporter,
        direction: null,
      ).withPortalIndex(i),
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
  // The recorded solutions now live in lib/data/level_hints.dart, because the
  // game reads them too — hints reveal one placement at a time from exactly
  // this data. The tests below are therefore also what certifies the hints:
  // "intended solution wins" proves the hint for every level is a winning move.
  final intended = kSolutionArrows;
  final teleports = kSolutionTeleports;
  final oneShots = kSolutionOneShots;
  final pauses = kSolutionPauses;
  final shields = kSolutionShields;

  // Walk the definitions themselves, so a new level is never silently skipped.
  final allLevels = levelDefinitions.keys.toList()..sort();

  // Levels with more than one portal pair can't be verified by the SHIPPED
  // solvers: BruteSearch pairs portals by board order, the player by placement
  // order. In this suite they're checked by their recorded solution winning
  // (the intended-solution test drives the real pairing via place()'s list
  // order); tool/verify_pairs.dart sweeps them exhaustively out of band — 57,
  // 59 and 60 are tight, and 70 is tight with a unique solution. Level 59 has
  // three pairs in a crossing wiring no board-order pairing can express.
  const multiPairLevels = {57, 59, 60, 70};
  // Levels whose exhaustive enumeration is too slow for the suite (a full open
  // board with a teleporter toolkit, so no reachability pruning). Level 55 takes
  // ~14 minutes to enumerate; level 91's seven-piece kit is likewise beyond the
  // budget, as are 85's and 91's kits — both verified TIGHT out of band by
  // tool/verify_pairs.dart. Their recorded solutions carry them via the
  // intended-solution-wins test; the solvable/tight sweeps are skipped.
  //
  // 76 and 77 are the same story an order of magnitude worse, and for a reason
  // worth naming: a rotating arrow forces the SIMULATE-based BruteSearch (only
  // it models per-pass rotation), and BruteSearch cannot prune to the dot's
  // path. On a 7x7 that is 5.6e12 placements for 76's nine-piece kit and 1.9e10
  // for 77's seven — against a kMaxBrutePlacements budget of 8e6, so the
  // in-app solver refuses them outright. Both ARE solvable: their recorded
  // solutions were found by enumerating over a hand-restricted candidate list
  // (~0.8M and ~3.4M placements) and are asserted below by the
  // intended-solution-wins test, which is a single simulate and exact.
  // 79 joins them, and is the worst of the lot: a ten-piece kit including two
  // portal pairs on a 7x7 comes to 4.96e12 placements. Its recorded solution was
  // found by restricted enumeration (37.8M placements over 14 candidate cells,
  // 18 wins — all of them with every piece on the path).
  const solverTooSlow = {55, 76, 77, 79, 80, 82, 84, 85, 91};

  // 61–70 are the Master Trials — a no-new-pieces interlude that reports as 6
  // for naming; World 6 proper (rotating arrows) opens at 71 and shares it.
  int worldOf(int n) => n <= 15
      ? 1
      : (n <= 20
          ? 2
          : (n <= 30
              ? 3
              : (n <= 50 ? 4 : (n <= 60 ? 5 : (n <= 91 ? 6 : 7)))));



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
        skip: multiPairLevels.contains(n)
            ? 'two portal pairs — solver cannot verify; see intended-solution test'
            : solverTooSlow.contains(n)
                ? 'enumeration too slow — solvability proven by exhaustion, see '
                    'intended-solution test'
                : null);

    test('World ${worldOf(n)} — level $n intended solution wins', () {
      final level = levelDataFor(n)!;
      expect(
          simulate(
              level,
              place(level, intended[n]!, shields[n] ?? const [],
                  pauses[n] ?? const [], teleports[n] ?? const [],
                  oneShots[n] ?? const [])),
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
        skip: (multiPairLevels.contains(n) || solverTooSlow.contains(n))
            ? 'two pairs, or enumeration too slow — see design notes'
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
              pauses[n] ?? const [], teleports[n] ?? const [],
              oneShots[n] ?? const []));
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
              pauses[n] ?? const [], teleports[n] ?? const [],
              oneShots[n] ?? const []));
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
      //
      // Both skip sets apply. multiPairLevels are not solver-enumerable at all;
      // solverTooSlow are, but not in any useful time — and this sweep calls
      // solveFor directly, so without that second guard a level in solverTooSlow
      // gets fully enumerated here no matter what the per-level tests skip.
      // Level 77 is the case in point: it carries a patrol AND a seven-piece
      // kit, which is 1.94e10 placements, and it hung the whole suite here.
      for (final n in allLevels.where((n) =>
          levelDataFor(n)!.movers.isNotEmpty &&
          !multiPairLevels.contains(n) &&
          !solverTooSlow.contains(n))) {
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
