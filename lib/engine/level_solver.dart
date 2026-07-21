import '../models/game_state.dart';
import '../models/grid_cell.dart';
import '../models/level_data.dart';
import 'simulator.dart';

/// Cells the player may place a piece on (empty, not start/exit/hazard/forced).
List<int> placeableCells(LevelData level) {
  final n = level.size;
  final cells = <int>[];
  for (var r = 0; r < n; r++) {
    for (var c = 0; c < n; c++) {
      if (level.baseTypeAt(r, c) != CellType.empty) continue;
      if (level.hasForcedPieceAt(r, c)) continue;
      cells.add(r * n + c);
    }
  }
  return cells;
}

PlacedElement _element(ToolType t) =>
    PlacedElement(type: t.placedType, tool: t, direction: t.direction);

/// Every cell the dot could land on under ANY placement of the toolkit.
///
/// A placed piece only ever changes the run when the dot lands on its cell, so
/// a piece anywhere outside this set is provably inert — the brute force can
/// skip those cells without losing a single solution.
///
/// The walk is deliberately generous, because it must be a SUPERSET of what any
/// real run can touch:
///   * at every empty cell the player could have placed any arrow, so all four
///     headings are explored from it;
///   * destroyers are treated as survivable (a shield may clear them);
///   * walls beside a destroyer — or beside any cell in a patrol's lane — are
///     treated as demolishable, since a shielded hit chain-explodes them;
///   * gaps, and walls no explosion can reach, block. Nothing ever clears a gap.
/// Mover collisions and shield supply are ignored; both only ever kill the dot,
/// so ignoring them can add cells but never lose one.
Set<int> reachableCells(LevelData level) {
  final n = level.size;

  // Walls some chain explosion could open.
  final clearable = <int>{};
  void markWallsAround(int r, int c) {
    for (final (dr, dc) in const [(-1, 0), (1, 0), (0, -1), (0, 1)]) {
      final ar = r + dr, ac = c + dc;
      if (ar < 0 || ar >= n || ac < 0 || ac >= n) continue;
      if (level.baseTypeAt(ar, ac) == CellType.wall) clearable.add(ar * n + ac);
    }
  }

  for (final d in level.destroyers) {
    markWallsAround(d.r, d.c);
  }
  for (final m in level.movers) {
    // A patrol sweeps its whole lane, and can be shielded anywhere along it.
    for (var p = 0; p < n; p++) {
      markWallsAround(m.horizontal ? m.r : p, m.horizontal ? p : m.c);
    }
  }

  bool blocks(int r, int c) {
    final t = level.baseTypeAt(r, c);
    if (t == CellType.gap) return true;
    if (t == CellType.wall) return !clearable.contains(r * n + c);
    return false;
  }

  final cells = <int>{};
  // State is (cell, heading) packed as key * 4 + direction index.
  final seen = <int>{};
  final stack = <int>[];
  void push(int r, int c, Direction d) {
    final s = (r * n + c) * 4 + d.index;
    if (seen.add(s)) stack.add(s);
  }

  push(level.start.r, level.start.c, level.start.dir);
  while (stack.isNotEmpty) {
    final s = stack.removeLast();
    final dir = Direction.values[s % 4];
    final from = s ~/ 4;
    final (dr, dc) = dir.delta;
    final nr = from ~/ n + dr, nc = from % n + dc;
    if (nr < 0 || nr >= n || nc < 0 || nc >= n) continue;
    if (blocks(nr, nc)) continue;
    cells.add(nr * n + nc);
    final t = level.baseTypeAt(nr, nc);
    if (t == CellType.exit) continue; // the run ends here
    final forcedDir = level.forcedArrowAt(nr, nc);
    if (forcedDir != null) {
      push(nr, nc, forcedDir);
    } else if (level.teleporterPairAt(nr, nc) >= 0) {
      // A fixed teleporter: the dot reappears at the far end, same heading, so
      // reachability has to jump with it or everything past the exit-side
      // portal looks unreachable.
      final pair = level.teleporters[level.teleporterPairAt(nr, nc)];
      final other = (pair.a.r == nr && pair.a.c == nc) ? pair.b : pair.a;
      cells.add(other.r * n + other.c);
      push(other.r, other.c, dir);
    } else if (level.hasForcedPieceAt(nr, nc)) {
      // A fixed shield or pause: the player can't place here, and neither piece
      // turns the dot, so the heading carries straight through.
      push(nr, nc, dir);
    } else if (t == CellType.start) {
      push(nr, nc, level.start.dir); // start permanently redirects
    } else if (t == CellType.empty) {
      // Any arrow could sit here — or none, which keeps the incoming heading.
      for (final d in Direction.values) {
        push(nr, nc, d);
      }
    } else {
      push(nr, nc, dir); // destroyer or blown-open wall: straight through
    }
  }
  return cells;
}

/// The cells the brute force actually has to try: [placeableCells] narrowed to
/// those the dot can reach.
///
/// Falls back to the full set when the toolkit holds a teleporter. That is the
/// one piece whose effect is NOT local — the simulator reads the *other*
/// teleporter's cell to find the destination, so a teleporter on a cell the dot
/// never lands on still changes the run, and pruning it away would be wrong.
List<int> candidateCells(LevelData level) {
  final all = placeableCells(level);
  if (level.toolkit.any((e) => e.type == ToolType.teleporter)) return all;
  final reach = reachableCells(level);
  return [
    for (final c in all)
      if (reach.contains(c)) c,
  ];
}

/// Called for each winning placement. The map is the searcher's live board —
/// copy it if you need to keep it.
typedef WinSink = void Function(Map<int, PlacedElement> placement);

/// One cell's position in the depth-first walk.
class _Frame {
  _Frame(this.i);

  /// Index into the searcher's cell list.
  final int i;

  /// 0 = "leave empty" not yet taken; 1..n = place types[choice-1].
  int choice = 0;

  /// What this frame currently has on the board, so it can be undone.
  ToolType? placed;
}

/// Brute-force every distinct way to place a subset of the toolkit on the
/// board, reporting each configuration that solves the level. Visiting cells in
/// index order yields each configuration exactly once.
///
/// This is an explicit-stack DFS rather than plain recursion so the sweep can be
/// PAUSED mid-search: Flutter web has no isolates, so the only way to keep the
/// UI painting during a long solve is to run it in slices and hand the event
/// loop a turn in between. [runSlice] does exactly that. Native code paths run
/// it to completion in one call inside a real isolate.
class BruteSearch {
  BruteSearch(this.level, this._onWin)
      : cells = candidateCells(level),
        remaining = {for (final e in level.toolkit) e.type: e.count} {
    types = remaining.keys.toList();
    if (cells.isEmpty) {
      _leaf(); // nowhere to place anything — the bare board is the only config
      done = true;
    } else {
      _stack.add(_Frame(0));
    }
  }

  final LevelData level;
  final WinSink _onWin;
  final List<int> cells;
  final Map<ToolType, int> remaining;
  late final List<ToolType> types;
  final List<_Frame> _stack = [];

  /// The placement currently on the board.
  final Map<int, PlacedElement> current = {};

  /// True once the whole space has been explored.
  bool done = false;

  void _leaf() {
    if (simulate(level, current) == SimOutcome.win) _onWin(current);
  }

  /// Explore for up to [budget], then return. True means the search is finished;
  /// false means call again to resume exactly where it left off.
  bool runSlice(Duration budget) {
    if (done) return true;
    final sw = Stopwatch()..start();
    var leaves = 0;
    while (_stack.isNotEmpty) {
      final f = _stack.last;
      // Undo whatever the previous choice left on the board.
      final prev = f.placed;
      if (prev != null) {
        current.remove(cells[f.i]);
        remaining[prev] = remaining[prev]! + 1;
        f.placed = null;
      }
      if (f.choice > types.length) {
        _stack.removeLast(); // choices exhausted — back up
        continue;
      }
      final choice = f.choice++;
      if (choice > 0) {
        final t = types[choice - 1];
        if (remaining[t]! <= 0) continue; // none of this tool left
        remaining[t] = remaining[t]! - 1;
        current[cells[f.i]] = _element(t);
        f.placed = t;
      }
      final next = f.i + 1;
      if (next == cells.length) {
        _leaf();
        // Check the clock rarely — the mask keeps the hot path branch-cheap.
        // Pausing here is safe: `current` and `remaining` stay consistent
        // because the frame's placement is undone on re-entry.
        if ((++leaves & 255) == 0 && sw.elapsed >= budget) return false;
      } else {
        _stack.add(_Frame(next));
      }
    }
    done = true;
    return true;
  }
}

/// A budget long enough that a `runSlice` call runs to completion.
const Duration _uninterrupted = Duration(days: 1);

// ── Path-following search ──────────────────────────────────────────────────
// [BruteSearch] tries every piece on every candidate cell, which explodes: on
// level 45 that is ~2.4e12 placements. Reachability pruning barely dents it,
// because once any arrow may sit on any empty cell the dot can steer almost
// anywhere.
//
// The real saving is per-RUN, not per-board: on any single run the dot lands on
// a dozen-odd cells, and a piece anywhere else cannot have influenced it. So
// this search simulates the dot tick-accurately — movers, pauses, shields,
// chain explosions and all — and branches ONLY when it lands on a cell whose
// contents are still undecided. Every distinct decision sequence yields a
// distinct placement, so solutions are enumerated exactly once.
//
// Versus [BruteSearch] this reports the same SOLVABILITY and the same MINIMUM
// piece count (a minimal solution never contains an inert piece, or it would
// not be minimal). It reports a smaller solution COUNT, because it omits
// placements that merely dump spare pieces on cells the dot never visits —
// which is the same convention [pathSolve] already uses.

/// One branch point: the state to restore, and which choices remain.
class _Choice {
  _Choice(this.saved, this.key, this.options);
  final _RunState saved;
  final int key;

  /// null = leave the cell empty; otherwise the tool to place.
  final List<ToolType?> options;
  int next = 0;
}

/// A full simulation state, cheap enough to snapshot at each branch point.
class _RunState {
  _RunState({
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
    required this.remaining,
  });

  int r, c, pause, tick;
  Direction dir;
  bool shielded;
  Set<int> taken, removed, decided;
  List<int> moverPos, moverDir;
  Map<int, PlacedElement> placed;
  Map<ToolType, int> remaining;

  _RunState clone() => _RunState(
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
        remaining: {...remaining},
      );
}

/// Enumerates every winning placement by following the dot's actual path.
/// Mirrors [simulateDetailed]'s tick order exactly — that is what makes its
/// answers trustworthy. Pausable via [runSlice], like [BruteSearch].
class PathSearch {
  PathSearch(this.level, this._onWin)
      : n = level.size,
        maxTicks = level.size * level.size * 4 + 20,
        _movers = buildMovers(level) {
    _forced.addAll(buildForcedPieces(level));
    for (final k in placeableCells(level)) {
      _placeable.add(k);
    }
    _cur = _RunState(
      r: level.start.r,
      c: level.start.c,
      dir: level.start.dir,
      pause: 0,
      shielded: false,
      tick: 0,
      taken: {},
      removed: {},
      decided: {},
      moverPos: [for (final m in _movers) m.pos],
      moverDir: [for (final m in _movers) m.dir],
      placed: {},
      remaining: {for (final e in level.toolkit) e.type: e.count},
    );
  }

  final LevelData level;
  final int n;
  final int maxTicks;
  final WinSink _onWin;
  final List<MoverState> _movers; // templates: lane, size, blocked set
  /// Pieces the level pins to the board — arrows, shields and pauses alike.
  final Map<int, PlacedElement> _forced = {};
  final Set<int> _placeable = {};
  final List<_Choice> _stack = [];
  late _RunState _cur;

  /// Scratch buffer for pre-step patrol positions, reused every tick. This runs
  /// millions of times on a heavy level, so it must not allocate.
  late final List<int> _beforeStep = List<int>.filled(_movers.length, 0);

  bool done = false;

  /// Step one mover, mirroring [MoverState.step] — including the fact that a
  /// wall a chain explosion has opened stops being solid. The templates in
  /// [_movers] are shared across every branch of the search, so the cleared
  /// cells have to come from the branch's own state, never from mutating them.
  void _stepMover(int i) {
    final m = _movers[i];
    var pos = _cur.moverPos[i], d = _cur.moverDir[i];
    bool solid(int p) {
      if (p < 0 || p >= m.size) return true;
      if (!m.blocked.contains(p)) return false;
      return !_cur.removed.contains(m.keyAt(p));
    }
    var next = pos + d;
    if (solid(next)) {
      d = -d;
      next = pos + d;
      if (solid(next)) {
        _cur.moverDir[i] = d;
        return; // boxed in
      }
    }
    _cur.moverPos[i] = next;
    _cur.moverDir[i] = d;
  }

  int _moverRow(int i) => _movers[i].horizontal ? _movers[i].fixed : _cur.moverPos[i];
  int _moverCol(int i) => _movers[i].horizontal ? _cur.moverPos[i] : _movers[i].fixed;

  /// Resolve patrols that hit the dot — sharing its cell, or trading places
  /// with it when it moved from ([fromR],[fromC]). Returns true when fatal.
  /// Mirrors [moversCrossed] in the simulator; the two must never diverge.
  bool _moverCollision({int? fromR, int? fromC, List<int>? before}) {
    final hit = <int>[];
    for (var i = 0; i < _movers.length; i++) {
      if (_cur.moverPos[i] < 0) continue; // destroyed
      if (_moverRow(i) == _cur.r && _moverCol(i) == _cur.c) {
        hit.add(i);
        continue;
      }
      if (fromR == null || fromC == null || before == null) continue;
      final m = _movers[i];
      final wasRow = m.horizontal ? m.fixed : before[i];
      final wasCol = m.horizontal ? before[i] : m.fixed;
      if (moversCrossed(
        dotFromR: fromR,
        dotFromC: fromC,
        dotToR: _cur.r,
        dotToC: _cur.c,
        moverFromR: wasRow,
        moverFromC: wasCol,
        moverToR: _moverRow(i),
        moverToC: _moverCol(i),
      )) {
        hit.add(i);
      }
    }
    if (hit.isEmpty) return false;
    if (!_cur.shielded) return true;
    _cur.shielded = false;
    for (final i in hit) {
      final mk = _moverRow(i) * n + _moverCol(i);
      _cur.moverPos[i] = -1000; // destroyed, parked off-lane
      _cur.removed.add(mk);
      _cur.removed.addAll(adjacentWallKeys(level, mk));
    }
    return false;
  }

  CellType _eff(int r, int c) => _cur.removed.contains(r * n + c)
      ? CellType.empty
      : level.baseTypeAt(r, c);

  /// Apply a piece's effect to the live state.
  void _apply(PlacedElement piece, int key) {
    switch (piece.type) {
      case PlacedType.arrow:
        _cur.dir = piece.direction!;
      case PlacedType.pause:
        _cur.pause = 2;
      case PlacedType.shield:
        if (_cur.taken.add(key)) _cur.shielded = true;
      case PlacedType.teleporter:
        // Links are rebuilt per branch, since the player's own teleporters pair
        // up by board order and that changes as pieces are placed.
        final dest =
            buildTeleportLinks(level, {..._forced, ..._cur.placed})[key];
        if (dest != null) {
          _cur.r = dest ~/ n;
          _cur.c = dest % n;
        }
    }
  }

  /// Take the next untried choice, restoring state. False when exhausted.
  bool _backtrack() {
    while (_stack.isNotEmpty) {
      final f = _stack.last;
      if (f.next >= f.options.length) {
        _stack.removeLast();
        continue;
      }
      final opt = f.options[f.next++];
      _cur = f.saved.clone();
      _cur.decided.add(f.key);
      if (opt != null) {
        _cur.remaining[opt] = _cur.remaining[opt]! - 1;
        final piece = _element(opt);
        _cur.placed[f.key] = piece;
        _apply(piece, f.key);
      }
      // The exit check happens after the piece resolves, as in the simulator.
      if (level.baseTypeAt(_cur.r, _cur.c) == CellType.exit) {
        _onWin(_cur.placed);
        continue; // a win is a leaf — keep looking for others
      }
      return true;
    }
    return false;
  }

  /// Explore for up to [budget]. True when the search is finished.
  bool runSlice(Duration budget) {
    if (done) return true;
    final sw = Stopwatch()..start();
    var leaves = 0;

    while (true) {
      var dead = false;
      // Advance until this run ends or reaches an undecided cell.
      while (_cur.tick < maxTicks) {
        _cur.tick++;
        // Positions before the step, so a crossing can be spotted below.
        for (var i = 0; i < _movers.length; i++) {
          _beforeStep[i] = _cur.moverPos[i];
          if (_cur.moverPos[i] > -1000) _stepMover(i);
        }
        if (_cur.pause > 0) {
          _cur.pause--;
          if (_moverCollision()) {
            dead = true;
            break;
          }
          continue;
        }
        final (dr, dc) = _cur.dir.delta;
        final nr = _cur.r + dr, nc = _cur.c + dc;
        if (nr < 0 || nr >= n || nc < 0 || nc >= n) {
          dead = true;
          break;
        }
        if (_eff(nr, nc) == CellType.wall) {
          dead = true;
          break;
        }
        final fromR = _cur.r, fromC = _cur.c;
        _cur.r = nr;
        _cur.c = nc;
        if (_moverCollision(
            fromR: fromR, fromC: fromC, before: _beforeStep)) {
          dead = true;
          break;
        }
        final key = nr * n + nc;
        final base = _eff(nr, nc);
        if (base == CellType.gap) {
          dead = true;
          break;
        }
        if (base == CellType.destroyer || base == CellType.movingDestroyer) {
          if (!_cur.shielded) {
            dead = true;
            break;
          }
          _cur.shielded = false;
          _cur.removed.add(key);
          _cur.removed.addAll(adjacentWallKeys(level, key));
        }
        if (base == CellType.start) _cur.dir = level.start.dir;

        // Branch point: an undecided cell we could still put a piece on.
        if (_placeable.contains(key) &&
            !_cur.decided.contains(key) &&
            !_cur.placed.containsKey(key)) {
          final opts = <ToolType?>[
            null, // leave it empty
            for (final t in _cur.remaining.keys)
              if (_cur.remaining[t]! > 0) t,
          ];
          _stack.add(_Choice(_cur.clone(), key, opts));
          if (!_backtrack()) {
            done = true;
            return true;
          }
          continue; // resume simulating with the chosen option applied
        }

        // A fixed piece resolves exactly like a placed one — same _apply, so a
        // fixed shield grants the aura and a fixed pause holds the dot.
        final here = _cur.placed[key] ?? _forced[key];
        if (here != null) _apply(here, key);
        if (level.baseTypeAt(_cur.r, _cur.c) == CellType.exit) {
          _onWin(_cur.placed);
          dead = true; // a win ends this run
          break;
        }
      }
      // This run is over (won, died, or looped) — take the next branch.
      if (dead || _cur.tick >= maxTicks) {
        if (!_backtrack()) {
          done = true;
          return true;
        }
      }
      if ((++leaves & 63) == 0 && sw.elapsed >= budget) return false;
    }
  }
}

/// True when the TOOLKIT hands the player a teleporter.
///
/// [PathSearch] only ever places a piece on a cell the dot lands on, but a
/// teleporter's partner is by definition somewhere the dot has not been — it is
/// the destination. So these levels need the exhaustive [BruteSearch], which
/// considers every candidate cell whether or not the dot reaches it. (This is
/// the same locality assumption [candidateCells] already opts out of.)
bool needsExhaustiveSolver(LevelData level) =>
    level.toolkit.any((e) => e.type == ToolType.teleporter);

/// Every winning placement, found by following the dot's path.
///
/// Throws when handed a level whose toolkit holds a teleporter — see
/// [needsExhaustiveSolver]. Failing loud beats quietly reporting "unsolvable".
List<Map<int, PlacedElement>> pathSolveAll(LevelData level) {
  if (needsExhaustiveSolver(level)) {
    throw PathSolverUnsupported(
        'level ${level.id} has a teleporter in its toolkit; the path search '
        'cannot place a partner on a cell the dot has not reached');
  }
  final out = <Map<int, PlacedElement>>[];
  PathSearch(level, (p) => out.add(Map.of(p))).runSlice(_uninterrupted);
  return out;
}

/// Every winning placement, using whichever engine is correct for [level].
/// This is the entry point callers should reach for.
List<Map<int, PlacedElement>> enumerateSolutions(LevelData level) =>
    needsExhaustiveSolver(level) ? solveAll(level) : pathSolveAll(level);

/// The right slice-driver for [level]: the exhaustive search when a teleporter
/// is in the toolkit, the path search otherwise. Both expose the same
/// `runSlice(Duration) -> done` shape.
bool Function(Duration) _sliceFor(LevelData level, WinSink sink) =>
    needsExhaustiveSolver(level)
        ? BruteSearch(level, sink).runSlice
        : PathSearch(level, sink).runSlice;

/// Brute-force every distinct way to place a subset of the toolkit on the board
/// and return all configurations that solve the level.
List<Map<int, PlacedElement>> solveAll(LevelData level) {
  final solutions = <Map<int, PlacedElement>>[];
  BruteSearch(level, (p) => solutions.add(Map.of(p))).runSlice(_uninterrupted);
  return solutions;
}

/// How many placements win, and the fewest pieces any of them uses (-1 when
/// there are none). Tallying instead of materialising every solution keeps a
/// wide-open candidate from building a huge list just to count it.
class BruteStats {
  const BruteStats(this.count, this.minPieces, {this.complete = true});
  final int count;
  final int minPieces;

  /// False when the search hit its time cap before exhausting the space. The
  /// numbers are then a floor, not an answer — treat the result as "don't
  /// know", never as "unsolvable".
  final bool complete;
}

/// Default ceiling on a single solve. Level 45 — the heaviest authored level —
/// enumerates fully in ~18s, so this leaves headroom without letting a
/// pathological board hang forever.
const Duration kSolveCap = Duration(seconds: 40);

WinSink _tally(void Function(int count, int minPieces) set) {
  var count = 0;
  var minPieces = -1;
  return (p) {
    count++;
    if (minPieces < 0 || p.length < minPieces) minPieces = p.length;
    set(count, minPieces);
  };
}

/// Solution count and minimum piece count.
///
/// Normally uses [PathSearch]: it gives the same solvability and the same
/// minimum while skipping placements the dot could never have touched, which is
/// the difference between 18 seconds and 2.4e12 placements on level 45. Levels
/// with a toolkit teleporter fall back to [BruteSearch] — see
/// [needsExhaustiveSolver].
BruteStats bruteStats(LevelData level, {Duration cap = kSolveCap}) {
  var count = 0;
  var minPieces = -1;
  final slice = _sliceFor(
      level,
      _tally((c, m) {
        count = c;
        minPieces = m;
      }));
  final sw = Stopwatch()..start();
  var finished = false;
  while (!(finished = slice(const Duration(milliseconds: 50)))) {
    if (sw.elapsed >= cap) break;
  }
  return BruteStats(count, minPieces, complete: finished);
}

/// [bruteStats] run in [slice]-sized pieces, yielding to the event loop between
/// them so the UI keeps painting. Use on web, where there are no isolates.
Future<BruteStats> bruteStatsPaced(
  LevelData level, {
  Duration slice = const Duration(milliseconds: 12),
  Duration cap = kSolveCap,
}) async {
  var count = 0;
  var minPieces = -1;
  final step = _sliceFor(
      level,
      _tally((c, m) {
        count = c;
        minPieces = m;
      }));
  final sw = Stopwatch()..start();
  var finished = false;
  while (!(finished = step(slice))) {
    if (sw.elapsed >= cap) break;
    // A macrotask, not a microtask — microtasks drain before the browser gets
    // to paint, so `Duration.zero` here is what actually frees the frame.
    await Future<void>.delayed(Duration.zero);
  }
  return BruteStats(count, minPieces, complete: finished);
}

/// True if at least one placement of the toolkit solves the level.
bool isSolvable(LevelData level) => solveAll(level).isNotEmpty;

/// Total number of pieces in the toolkit.
int toolkitTotal(LevelData level) =>
    level.toolkit.fold(0, (sum, e) => sum + e.count);

/// Tools the fast path solver cannot reason about. Pause changes only the dot's
/// TIMING and the teleporter moves it off its path — neither is expressible in a
/// solver whose state is (cell, heading, shield, cleared-walls) with no clock.
const Set<ToolType> pathSolverBlindTools = {
  ToolType.pause,
  ToolType.teleporter,
};

/// True when [level] needs the timing-aware brute-force solver ([solveAll]).
/// Moving destroyers make arrival time matter, and pause/teleporter pieces are
/// invisible to the path solver — in either case only the simulate-based brute
/// force gives a correct answer. This is the single routing predicate: every
/// caller picks its solver with it, and [pathSolve]/[pathMinPieces] refuse any
/// level it flags, so the two can never drift apart.
/// Boards wider than this overflow the static path solver's 64-bit cleared-cell
/// mask (a 9x9 has keys up to 80), so they are routed to the Set-based search.
const int kMaxPathSolverSize = 8;

bool needsBruteSolver(LevelData level) =>
    level.movers.isNotEmpty ||
    level.size > kMaxPathSolverSize ||
    // A teleporter moves the dot off its path; the static solver walks cell by
    // cell and cannot express that jump.
    level.teleporters.isNotEmpty ||
    level.toolkit.any((e) => pathSolverBlindTools.contains(e.type));

/// Thrown when the path solver is handed a level only [solveAll] can answer.
/// Route with [needsBruteSolver] instead of catching this.
class PathSolverUnsupported implements Exception {
  const PathSolverUnsupported(this.reason);
  final String reason;
  @override
  String toString() => 'PathSolverUnsupported: $reason — use solveAll().';
}

void _requirePathSolvable(LevelData level) {
  if (!needsBruteSolver(level)) return;
  if (level.size > kMaxPathSolverSize) {
    throw PathSolverUnsupported(
        'level ${level.id} is ${level.size}x${level.size}; the path solver\'s '
        'cleared-cell mask only holds ${kMaxPathSolverSize * kMaxPathSolverSize} '
        'cells');
  }
  final blind = level.toolkit
      .map((e) => e.type)
      .where(pathSolverBlindTools.contains)
      .map((t) => t.name)
      .toSet();
  throw PathSolverUnsupported(
    level.movers.isNotEmpty && blind.isNotEmpty
        ? 'level ${level.id} has moving destroyers and ${blind.join("/")} '
            'in its toolkit'
        : level.movers.isNotEmpty
            ? 'level ${level.id} has moving destroyers (timing matters)'
            : 'level ${level.id} has ${blind.join("/")} in its toolkit',
  );
}

/// C(n, k) as a double, saturating rather than overflowing.
double _choose(int n, int k) {
  if (k < 0 || k > n) return 0;
  var r = 1.0;
  for (var i = 1; i <= k; i++) {
    r = r * (n - k + i) / i;
    if (r.isInfinite) return double.infinity;
  }
  return r;
}

/// How many distinct full-toolkit placements [solveAll] enumerates: choose which
/// [placeable] cells hold a piece, then which piece lands on each (identical
/// pieces don't double-count). This dominates the smaller-subset leaves, so it
/// is the right scale for a cost guard — and it is far tighter than
/// `pow(placeable, total)`, which counts ordered placements and overstates the
/// real work by orders of magnitude.
double bruteForcePlacements(int placeable, Iterable<int> pieceCounts) {
  final counts = pieceCounts.where((c) => c > 0).toList();
  final total = counts.fold(0, (a, b) => a + b);
  if (total == 0 || placeable <= 0) return 0;
  if (total > placeable) return double.infinity;
  // multinomial(total; counts) built up as a product of binomials.
  var arrangements = 1.0;
  var used = 0;
  for (final c in counts) {
    used += c;
    arrangements *= _choose(used, c);
  }
  return _choose(placeable, total) * arrangements;
}

/// Placement budget for one brute-force solve. Measured cost is ~1.5µs per
/// placement (level 43: 285k placements in ~420ms), so this is a few seconds at
/// the very top end — fine off the UI thread, and generous enough to admit the
/// real pause levels (level 44 is ~5.9M) that the old `pow(...) > 5e5` guard
/// silently skipped.
const double kMaxBrutePlacements = 8e6;

/// Fewest pieces used by any solution (-1 if unsolvable). When this equals
/// [toolkitTotal], every solution uses all pieces.
int minSolutionPieces(LevelData level) {
  final sols = solveAll(level);
  if (sols.isEmpty) return -1;
  return sols.map((m) => m.length).reduce((a, b) => a < b ? a : b);
}

// ── Path-based solver ──────────────────────────────────────────────────────
// `solveAll` enumerates every placement on every cell, which explodes on large
// OPEN grids. The functions below instead follow the dot's actual journey and
// only ever place a piece on a cell the dot reaches. They thread the full
// runtime state — heading, whether the dot is shielded, and the bitmask of
// cells cleared by chain explosions — so they handle World 3's shields and the
// mutating wall grid. (n ≤ 8, so cell keys fit in a 64-bit removed-mask.)

/// Bitmask of the wall cells a chain explosion at [key] would demolish.
int _adjacentWallMask(LevelData level, int key) {
  var m = 0;
  for (final k in adjacentWallKeys(level, key)) {
    m |= 1 << k;
  }
  return m;
}

/// Toolkit pieces the path solver places. Callers reach here only after
/// [_requirePathSolvable], so every entry is an arrow or a shield — the whole
/// toolkit is used. It must never quietly drop a piece: doing so made the solver
/// answer a different question than it was asked (a level needing a pause looked
/// unsolvable, or "solvable" without ever placing it).
Map<ToolType, int> _placeableKit(LevelData level) => {
      for (final e in level.toolkit) e.type: e.count,
    };

/// Smallest number of pieces (arrows + shields) any solution needs (-1 if
/// unsolvable). Branch-and-bound on the fewest-piece win found. When this equals
/// [toolkitTotal] the level is "tight" — no piece can be left unused.
///
/// Throws [PathSolverUnsupported] when [needsBruteSolver] flags the level.
int pathMinPieces(LevelData level) {
  _requirePathSolvable(level);
  final n = level.size;
  final forced = buildForcedPieces(level);
  final remaining = _placeableKit(level);
  final placed = <int, ToolType>{};
  final seen = <String>{};
  var best = 1 << 30;

  void advance(int r, int c, Direction dir, bool shielded, int removed) {
    if (placed.length >= best) return;
    final (dr, dc) = dir.delta;
    final nr = r + dr, nc = c + dc;
    if (nr < 0 || nr >= n || nc < 0 || nc >= n) return;
    final key = nr * n + nc;
    final clearedHere = (removed >> key) & 1 == 1;
    final bt = level.baseTypeAt(nr, nc);
    if (bt == CellType.wall && !clearedHere) return;
    if (bt == CellType.exit) {
      best = placed.length;
      return;
    }
    if (bt == CellType.gap && !clearedHere) return;
    if ((bt == CellType.destroyer || bt == CellType.movingDestroyer) &&
        !clearedHere) {
      if (!shielded) return;
      final nrem = removed | (1 << key) | _adjacentWallMask(level, key);
      final st = 'D$key.${dir.index}.$nrem';
      if (seen.contains(st)) return;
      seen.add(st);
      advance(nr, nc, dir, false, nrem); // shield spent; pass through
      seen.remove(st);
      return;
    }
    // Passable cell: an original empty cell, or one cleared by an explosion.
    final st = '$key.${dir.index}.${shielded ? 1 : 0}.$removed';
    if (seen.contains(st)) return;
    seen.add(st);
    if (!(bt == CellType.empty && !clearedHere)) {
      // A cleared wall/destroyer passes straight; the start cell permanently
      // redirects to the launch direction (like a forced arrow).
      advance(nr, nc, bt == CellType.start ? level.start.dir : dir, shielded,
          removed);
    } else {
      final forcedHere = forced[key];
      final here = placed[key];
      if (forcedHere != null) {
        // A fixed arrow turns the dot; a fixed shield grants the aura; a fixed
        // pause only costs ticks, which this clock-less solver does not model
        // (it is never used on levels where timing matters).
        switch (forcedHere.type) {
          case PlacedType.arrow:
            advance(nr, nc, forcedHere.direction!, shielded, removed);
          case PlacedType.shield:
            advance(nr, nc, dir, true, removed);
          case PlacedType.pause:
          case PlacedType.teleporter:
            advance(nr, nc, dir, shielded, removed);
        }
      } else if (here != null) {
        if (here.direction != null) {
          advance(nr, nc, here.direction!, shielded, removed);
        } else {
          advance(nr, nc, dir, true, removed); // shield
        }
      } else {
        advance(nr, nc, dir, shielded, removed); // leave empty
        for (final type in remaining.keys) {
          if (remaining[type]! <= 0) continue;
          remaining[type] = remaining[type]! - 1;
          placed[key] = type;
          if (type.direction != null) {
            advance(nr, nc, type.direction!, shielded, removed);
          } else {
            advance(nr, nc, dir, true, removed); // place a shield, pick it up
          }
          placed.remove(key);
          remaining[type] = remaining[type]! + 1;
        }
      }
    }
    seen.remove(st);
  }

  advance(level.start.r, level.start.c, level.start.dir, false, 0);
  return best == (1 << 30) ? -1 : best;
}

/// All distinct on-path placements that win, capped at [maxResults]. For a tight
/// level every entry uses the whole toolkit, so the count is the number of
/// genuinely different solutions — the design goal is one (or very few).
///
/// Throws [PathSolverUnsupported] when [needsBruteSolver] flags the level.
List<Map<int, PlacedElement>> pathSolve(LevelData level,
    {int maxResults = 256}) {
  _requirePathSolvable(level);
  final n = level.size;
  final forced = buildForcedPieces(level);
  final remaining = _placeableKit(level);
  final placed = <int, ToolType>{};
  final seen = <String>{};
  final results = <Map<int, PlacedElement>>[];

  void advance(int r, int c, Direction dir, bool shielded, int removed) {
    if (results.length >= maxResults) return;
    final (dr, dc) = dir.delta;
    final nr = r + dr, nc = c + dc;
    if (nr < 0 || nr >= n || nc < 0 || nc >= n) return;
    final key = nr * n + nc;
    final clearedHere = (removed >> key) & 1 == 1;
    final bt = level.baseTypeAt(nr, nc);
    if (bt == CellType.wall && !clearedHere) return;
    if (bt == CellType.exit) {
      results.add({
        for (final e in placed.entries) e.key: _element(e.value),
      });
      return;
    }
    if (bt == CellType.gap && !clearedHere) return;
    if ((bt == CellType.destroyer || bt == CellType.movingDestroyer) &&
        !clearedHere) {
      if (!shielded) return;
      final nrem = removed | (1 << key) | _adjacentWallMask(level, key);
      final st = 'D$key.${dir.index}.$nrem';
      if (seen.contains(st)) return;
      seen.add(st);
      advance(nr, nc, dir, false, nrem);
      seen.remove(st);
      return;
    }
    final st = '$key.${dir.index}.${shielded ? 1 : 0}.$removed';
    if (seen.contains(st)) return;
    seen.add(st);
    if (!(bt == CellType.empty && !clearedHere)) {
      advance(nr, nc, bt == CellType.start ? level.start.dir : dir, shielded,
          removed);
    } else {
      final forcedHere = forced[key];
      final here = placed[key];
      if (forcedHere != null) {
        // A fixed arrow turns the dot; a fixed shield grants the aura; a fixed
        // pause only costs ticks, which this clock-less solver does not model
        // (it is never used on levels where timing matters).
        switch (forcedHere.type) {
          case PlacedType.arrow:
            advance(nr, nc, forcedHere.direction!, shielded, removed);
          case PlacedType.shield:
            advance(nr, nc, dir, true, removed);
          case PlacedType.pause:
          case PlacedType.teleporter:
            advance(nr, nc, dir, shielded, removed);
        }
      } else if (here != null) {
        if (here.direction != null) {
          advance(nr, nc, here.direction!, shielded, removed);
        } else {
          advance(nr, nc, dir, true, removed);
        }
      } else {
        advance(nr, nc, dir, shielded, removed);
        for (final type in remaining.keys) {
          if (remaining[type]! <= 0) continue;
          remaining[type] = remaining[type]! - 1;
          placed[key] = type;
          if (type.direction != null) {
            advance(nr, nc, type.direction!, shielded, removed);
          } else {
            advance(nr, nc, dir, true, removed);
          }
          placed.remove(key);
          remaining[type] = remaining[type]! + 1;
        }
      }
    }
    seen.remove(st);
  }

  advance(level.start.r, level.start.c, level.start.dir, false, 0);
  return results;
}
