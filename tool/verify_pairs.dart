// ignore_for_file: avoid_print
// Exhaustive verifier for levels whose toolkit hands out teleporters — the one
// case the shipped solvers cannot fully cover. Run with:
//
//   dart run tool/verify_pairs.dart <level> [--max-wins N] [--budget S]
//   dart run tool/verify_pairs.dart <level> --compare
//
// BruteSearch pairs portals by BOARD order, but the player pairs them by
// PLACEMENT order, so any level offering more than one pair is declared
// unverifiable and hand-checked (see levels_solvable_test.dart). This tool
// closes that gap: it follows the dot's path like PathSearch, and when the dot
// lands on an undecided cell it may place a portal there and BRANCH ON EVERY
// CHOICE OF PARTNER CELL. Each pair created this way gets consecutive portal
// indices, exactly as if the player had dropped the two ends in that order —
// so the sweep covers every wiring any placement order can produce.
//
// Like PathSearch, it only places pieces on cells the dot actually lands on
// (plus portal partners, which are landed on via the jump). A piece anywhere
// else is provably inert, so the sweep still reports exact SOLVABILITY and the
// exact MINIMUM piece count; the solution count omits placements that dump
// spare pieces on cells the dot never visits.
//
// Every win found is re-run through the real simulator (with placement-order
// portal indices) before it is counted — the searcher proposes, simulate()
// disposes. A mismatch aborts loudly: it would mean this port has drifted from
// the engine, and every number printed would be untrustworthy.
//
// --compare cross-checks the sweep against the exhaustive BruteSearch on
// levels with a single pair (where board order and placement order agree), so
// the port's semantics are validated against the shipped solver.

import 'dart:io';

import 'package:dotto/data/level_definitions.dart';
import 'package:dotto/engine/level_solver.dart';
import 'package:dotto/engine/simulator.dart';
import 'package:dotto/models/game_state.dart';
import 'package:dotto/models/grid_cell.dart';
import 'package:dotto/models/level_data.dart';

/// One full simulation state, cloned at every branch point.
class _State {
  _State({
    required this.r,
    required this.c,
    required this.dir,
    required this.pause,
    required this.shielded,
    required this.tick,
    required this.taken,
    required this.removed,
    required this.decided,
    required this.moverPos,
    required this.moverDir,
    required this.placed,
    required this.links,
    required this.portalOrder,
    required this.remaining,
    required this.rotations,
  });

  int r, c, pause, tick;
  Direction dir;
  bool shielded;
  Set<int> taken, removed, decided;
  List<int> moverPos, moverDir;

  /// Live rotating-arrow headings (cell -> current direction) — advances one
  /// quarter-turn CW per pass, exactly as in the simulator.
  Map<int, Direction> rotations;

  /// Cell -> tool placed there (portals included, one entry per end).
  Map<int, ToolType> placed;

  /// Symmetric portal wiring for the player-placed pairs.
  Map<int, int> links;

  /// Portal cells in placement order (index i pairs with i ^ 1).
  List<int> portalOrder;

  Map<ToolType, int> remaining;

  _State clone() => _State(
        r: r,
        c: c,
        dir: dir,
        pause: pause,
        shielded: shielded,
        tick: tick,
        taken: {...taken},
        removed: {...removed},
        decided: {...decided},
        moverPos: [...moverPos],
        moverDir: [...moverDir],
        placed: {...placed},
        links: {...links},
        portalOrder: [...portalOrder],
        remaining: {...remaining},
        rotations: {...rotations},
      );
}

class PairSearch {
  PairSearch(this.level)
      : n = level.size,
        maxTicks = level.size * level.size * 4 + 20,
        movers = buildMovers(level),
        forced = buildForcedPieces(level),
        placeable = placeableCells(level).toSet() {
    fixedLinks = <int, int>{};
    for (final t in level.teleporters) {
      final a = t.a.r * n + t.a.c, b = t.b.r * n + t.b.c;
      fixedLinks[a] = b;
      fixedLinks[b] = a;
    }
  }

  final LevelData level;
  final int n;
  final int maxTicks;
  final List<MoverState> movers; // templates: lane, size, blocked set
  final Map<int, PlacedElement> forced;
  final Set<int> placeable;
  late final Map<int, int> fixedLinks;

  /// Canonical form of every win, to guard against double-counting.
  final Map<String, Map<int, PlacedElement>> wins = {};
  int leaves = 0;
  int minPieces = 1 << 30;
  final Stopwatch sw = Stopwatch();
  Duration budget = const Duration(minutes: 30);
  int maxWins = 1 << 30;
  bool timedOut = false;

  bool get _outOfTime {
    if (sw.elapsed >= budget) {
      timedOut = true;
      return true;
    }
    return false;
  }

  int _moverRow(int i, _State s) =>
      movers[i].horizontal ? movers[i].fixed : s.moverPos[i];
  int _moverCol(int i, _State s) =>
      movers[i].horizontal ? s.moverPos[i] : movers[i].fixed;

  void _stepMover(int i, _State s) {
    final m = movers[i];
    var pos = s.moverPos[i], d = s.moverDir[i];
    bool solid(int p) {
      if (p < 0 || p >= m.size) return true;
      if (!m.blocked.contains(p)) return false;
      return !s.removed.contains(m.keyAt(p));
    }

    var next = pos + d;
    if (solid(next)) {
      d = -d;
      next = pos + d;
      if (solid(next)) {
        s.moverDir[i] = d;
        return; // boxed in
      }
    }
    s.moverPos[i] = next;
    s.moverDir[i] = d;
  }

  /// Mirrors the simulator's collision rules: a patrol kills by sharing the
  /// dot's cell or by trading places with it; a shield destroys the patrol(s)
  /// and chain-explodes the walls beside them. Returns true when fatal.
  bool _moverCollision(_State s, {int? fromR, int? fromC, List<int>? before}) {
    final hit = <int>[];
    for (var i = 0; i < movers.length; i++) {
      if (s.moverPos[i] <= -1000) continue; // destroyed
      if (_moverRow(i, s) == s.r && _moverCol(i, s) == s.c) {
        hit.add(i);
        continue;
      }
      if (fromR == null || fromC == null || before == null) continue;
      final m = movers[i];
      final wasRow = m.horizontal ? m.fixed : before[i];
      final wasCol = m.horizontal ? before[i] : m.fixed;
      if (moversCrossed(
        dotFromR: fromR,
        dotFromC: fromC,
        dotToR: s.r,
        dotToC: s.c,
        moverFromR: wasRow,
        moverFromC: wasCol,
        moverToR: _moverRow(i, s),
        moverToC: _moverCol(i, s),
      )) {
        hit.add(i);
      }
    }
    if (hit.isEmpty) return false;
    if (!s.shielded) return true;
    s.shielded = false;
    for (final i in hit) {
      final mk = _moverRow(i, s) * n + _moverCol(i, s);
      s.moverPos[i] = -1000;
      s.removed.add(mk);
      s.removed.addAll(adjacentWallKeys(level, mk));
    }
    return false;
  }

  CellType _eff(_State s, int r, int c) =>
      s.removed.contains(r * n + c) ? CellType.empty : level.baseTypeAt(r, c);

  /// Applies a landed-on piece. Returns false when it killed the dot (only a
  /// teleport can, by dropping it onto a hazard).
  bool _apply(_State s, PlacedType type, Direction? dir, int key) {
    switch (type) {
      case PlacedType.arrow:
        s.dir = dir!;
      case PlacedType.pause:
        s.pause = 2;
      case PlacedType.shield:
        if (s.taken.add(key)) s.shielded = true;
      case PlacedType.teleporter:
        final dest = s.links[key] ?? fixedLinks[key];
        if (dest != null) {
          s.r = dest ~/ n;
          s.c = dest % n;
          if (_moverCollision(s)) return false;
          final base = _eff(s, s.r, s.c);
          if (base == CellType.gap) return false;
          if (base == CellType.destroyer || base == CellType.movingDestroyer) {
            if (!s.shielded) return false;
            s.shielded = false;
            final dk = s.r * n + s.c;
            s.removed.add(dk);
            s.removed.addAll(adjacentWallKeys(level, dk));
          }
        }
    }
    return true;
  }

  void _recordWin(_State s) {
    final keys = s.placed.keys.toList()..sort();
    final canon = keys.map((k) {
      final t = s.placed[k]!;
      final pi = t == ToolType.teleporter ? ':${s.links[k]}' : '';
      return '$k=${t.name}$pi';
    }).join(',');
    if (wins.containsKey(canon)) return;

    // Rebuild as the player would place it, and let the real simulator judge.
    final placement = <int, PlacedElement>{};
    for (final e in s.placed.entries) {
      if (e.value == ToolType.teleporter) continue;
      placement[e.key] = PlacedElement(
        type: e.value.placedType,
        tool: e.value,
        direction: e.value.direction,
      );
    }
    for (var i = 0; i < s.portalOrder.length; i++) {
      placement[s.portalOrder[i]] = const PlacedElement(
        type: PlacedType.teleporter,
        tool: ToolType.teleporter,
        direction: null,
      ).withPortalIndex(i);
    }
    if (simulate(level, placement) != SimOutcome.win) {
      throw StateError(
          'search found a "win" the simulator rejects: $canon — the port has '
          'drifted from the engine; every number from this run is invalid');
    }
    wins[canon] = placement;
    if (s.placed.length < minPieces) minPieces = s.placed.length;
  }

  void run() {
    sw.start();
    final s0 = _State(
      r: level.start.r,
      c: level.start.c,
      dir: level.start.dir,
      pause: 0,
      shielded: false,
      tick: 0,
      taken: {},
      removed: {},
      decided: {},
      moverPos: [for (final m in movers) m.pos],
      moverDir: [for (final m in movers) m.dir],
      placed: {},
      links: {},
      portalOrder: [],
      remaining: {for (final e in level.toolkit) e.type: e.count},
      rotations: buildRotations(level),
    );
    _advance(s0);
  }

  /// Runs the dot forward until it dies, wins, loops out, or reaches an
  /// undecided cell — where it branches over every piece that could sit there.
  void _advance(_State s) {
    if (wins.length >= maxWins || _outOfTime) return;
    final before = List<int>.filled(movers.length, 0);
    while (s.tick < maxTicks) {
      s.tick++;
      for (var i = 0; i < movers.length; i++) {
        before[i] = s.moverPos[i];
        if (s.moverPos[i] > -1000) _stepMover(i, s);
      }
      if (s.pause > 0) {
        s.pause--;
        if (_moverCollision(s)) return;
        continue;
      }
      final (dr, dc) = s.dir.delta;
      final nr = s.r + dr, nc = s.c + dc;
      if (nr < 0 || nr >= n || nc < 0 || nc >= n) return;
      if (_eff(s, nr, nc) == CellType.wall) return;
      final fromR = s.r, fromC = s.c;
      s.r = nr;
      s.c = nc;
      if (_moverCollision(s, fromR: fromR, fromC: fromC, before: before)) {
        return;
      }
      final key = nr * n + nc;
      final base = _eff(s, nr, nc);
      if (base == CellType.gap) return;
      if (base == CellType.destroyer || base == CellType.movingDestroyer) {
        if (!s.shielded) return;
        s.shielded = false;
        s.removed.add(key);
        s.removed.addAll(adjacentWallKeys(level, key));
      }
      if (base == CellType.start) s.dir = level.start.dir;

      // A rotating arrow turns the dot to its current heading, then advances a
      // quarter-turn clockwise — mirrors simulateDetailed exactly. Rotor cells
      // are never placeable, so this cannot collide with the branch below.
      final rot = s.rotations[key];
      if (rot != null) {
        s.dir = rot;
        s.rotations[key] = rot.rotatedCW;
      }

      // Branch point: an undecided placeable cell the dot just landed on.
      if (placeable.contains(key) &&
          !s.decided.contains(key) &&
          !s.placed.containsKey(key)) {
        _branch(s, key);
        return;
      }

      final placedHere = s.placed[key];
      if (placedHere != null) {
        if (!_apply(s, placedHere.placedType, placedHere.direction, key)) {
          return;
        }
      } else {
        final f = forced[key];
        if (f != null && !_apply(s, f.type, f.direction, key)) return;
      }
      if (level.baseTypeAt(s.r, s.c) == CellType.exit) {
        _recordWin(s);
        return;
      }
    }
  }

  void _branch(_State s, int key) {
    leaves++;
    if (leaves % 500000 == 0) {
      print('  ... $leaves branch points, ${wins.length} wins, '
          '${sw.elapsed.inSeconds}s');
    }
    // Leave the cell empty.
    {
      final next = s.clone();
      next.decided.add(key);
      if (level.baseTypeAt(next.r, next.c) == CellType.exit) {
        _recordWin(next);
      } else {
        _advance(next);
      }
    }
    // Place each still-available non-portal piece.
    for (final t in s.remaining.keys) {
      if (s.remaining[t]! <= 0) continue;
      if (t == ToolType.teleporter) continue;
      final next = s.clone();
      next.decided.add(key);
      next.remaining[t] = next.remaining[t]! - 1;
      next.placed[key] = t;
      if (!_apply(next, t.placedType, t.direction, key)) continue;
      if (level.baseTypeAt(next.r, next.c) == CellType.exit) {
        _recordWin(next);
      } else {
        _advance(next);
      }
    }
    // Place a portal here, branching on every possible partner cell. The pair
    // gets the next two portal indices — the placement order a player would
    // have used. (A single leftover portal with no partner is a no-op piece,
    // so those placements are skipped as inert.)
    if ((s.remaining[ToolType.teleporter] ?? 0) >= 2) {
      for (final partner in placeable) {
        if (partner == key) continue;
        if (s.decided.contains(partner)) continue;
        if (s.placed.containsKey(partner)) continue;
        final next = s.clone();
        next.decided.add(key);
        next.decided.add(partner);
        next.remaining[ToolType.teleporter] =
            next.remaining[ToolType.teleporter]! - 2;
        next.placed[key] = ToolType.teleporter;
        next.placed[partner] = ToolType.teleporter;
        next.links[key] = partner;
        next.links[partner] = key;
        next.portalOrder.add(key);
        next.portalOrder.add(partner);
        if (!_apply(next, PlacedType.teleporter, null, key)) continue;
        if (level.baseTypeAt(next.r, next.c) == CellType.exit) {
          _recordWin(next);
        } else {
          _advance(next);
        }
      }
    }
  }
}

String _describe(LevelData level, Map<int, PlacedElement> placement) {
  final keys = placement.keys.toList()..sort();
  return keys.map((k) {
    final e = placement[k]!;
    final r = k ~/ level.size, c = k % level.size;
    final what = e.type == PlacedType.arrow
        ? e.direction!.name
        : e.type == PlacedType.teleporter
            ? 'portal#${e.portalIndex}'
            : e.type.name;
    return '($r,$c,$what)';
  }).join(' ');
}

void main(List<String> args) {
  final id = int.tryParse(args.firstWhere(
      (a) => int.tryParse(a) != null,
      orElse: () => ''));
  if (id == null) {
    print('usage: dart run tool/verify_pairs.dart <level> '
        '[--budget seconds] [--max-wins N] [--compare]');
    exit(2);
  }
  final level = levelDefinitions[id];
  if (level == null) {
    print('no level $id');
    exit(2);
  }

  Duration budget = const Duration(minutes: 30);
  int maxWins = 1 << 30;
  final bi = args.indexOf('--budget');
  if (bi >= 0 && bi + 1 < args.length) {
    budget = Duration(seconds: int.parse(args[bi + 1]));
  }
  final mi = args.indexOf('--max-wins');
  if (mi >= 0 && mi + 1 < args.length) maxWins = int.parse(args[mi + 1]);

  final total = toolkitTotal(level);
  print('L$id "${level.title}" ${level.size}x${level.size}, '
      'toolkit $total (${toolkitTeleporters(level)} teleporters), '
      'placeable ${placeableCells(level).length}');

  final search = PairSearch(level)
    ..budget = budget
    ..maxWins = maxWins;
  search.run();

  final wins = search.wins.values.toList();
  final min = wins.isEmpty ? -1 : search.minPieces;
  print('sweep: ${search.leaves} branch points in '
      '${search.sw.elapsed.inMilliseconds}ms'
      '${search.timedOut ? "  *** TIMED OUT — results are a floor ***" : ""}');
  print('wins=${wins.length} min=$min total=$total '
      '${wins.isEmpty ? "*** UNSOLVABLE ***" : min == total ? "TIGHT" : "*** LOOSE ***"}');

  // Show the minimal solutions (all of them if few, else a sample).
  final minimal = wins.where((w) => w.length == min).toList();
  print('${minimal.length} minimal solution(s):');
  for (final w in minimal.take(24)) {
    print('  ${_describe(level, w)}');
  }
  if (minimal.length > 24) print('  ... and ${minimal.length - 24} more');

  if (args.contains('--compare')) {
    if (toolkitTeleporters(level) > 2) {
      print('--compare skipped: BruteSearch cannot pair >1 pair');
      return;
    }
    print('comparing against exhaustive BruteSearch...');
    final swb = Stopwatch()..start();
    final brute = solveAll(level);
    final bmin = brute.isEmpty
        ? -1
        : brute.map((m) => m.length).reduce((a, b) => a < b ? a : b);
    print('BruteSearch: ${brute.length} wins, min=$bmin '
        '(${swb.elapsed.inMilliseconds}ms)');
    final okSolvable = brute.isNotEmpty == wins.isNotEmpty;
    final okMin = bmin == min;
    print('solvability match: $okSolvable, min-pieces match: $okMin');
    if (!okSolvable || !okMin) {
      print('*** MISMATCH — the sweep has a bug ***');
      exit(1);
    }
  }
}
