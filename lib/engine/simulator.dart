import '../models/game_state.dart';
import '../models/grid_cell.dart';
import '../models/level_data.dart';

/// Outcome of running a level configuration to completion.
enum SimOutcome { win, lose }

/// Why the dot died, for showing the player a clear fail reason.
enum DeathCause {
  /// Stepped off the grid boundary.
  edge,

  /// Ran into a wall.
  wall,

  /// Hit a static mine / destroyer.
  destroyer,

  /// Caught by a moving destroyer (patrol).
  patrol,

  /// Fell into a gap.
  gap,
}

/// A simulation outcome with — when the dot loses — the reason it died. [cause]
/// is null for a win, or when the run simply looped without reaching the exit.
class SimResult {
  const SimResult(this.outcome, [this.cause]);
  final SimOutcome outcome;
  final DeathCause? cause;
}

/// The keys of every wall cell orthogonally adjacent to [key] — the cells a
/// chain explosion at [key] demolishes.
List<int> adjacentWallKeys(LevelData level, int key) {
  final n = level.size;
  final r = key ~/ n;
  final c = key % n;
  final out = <int>[];
  for (final (dr, dc) in const [(-1, 0), (1, 0), (0, -1), (0, 1)]) {
    final ar = r + dr, ac = c + dc;
    if (ar < 0 || ar >= n || ac < 0 || ac >= n) continue;
    if (level.baseTypeAt(ar, ac) == CellType.wall) out.add(ar * n + ac);
  }
  return out;
}

/// Mutable runtime state of a patrolling (moving) destroyer.
class MoverState {
  MoverState(this.fixed, this.pos, this.dir, this.lo, this.hi, this.horizontal,
      this.blocked);
  final int fixed;
  int pos;
  int dir;
  final int lo;
  final int hi;
  final bool horizontal;

  /// Positions (along the patrol axis) that are solid — walls, static
  /// destroyers, the exit — and that the mover bounces off of.
  final Set<int> blocked;

  int get row => horizontal ? fixed : pos;
  int get col => horizontal ? pos : fixed;

  bool _solid(int p) => p < lo || p > hi || blocked.contains(p);

  /// Advance one cell, bouncing at the patrol bounds and off any solid cell
  /// (wall, static destroyer, exit). If both neighbors are solid the mover is
  /// trapped and stays put.
  void step() {
    if (lo >= hi) return; // degenerate (single cell) — stays put
    var next = pos + dir;
    if (_solid(next)) {
      dir = -dir;
      next = pos + dir;
      if (_solid(next)) return; // boxed in on both sides — can't move
    }
    pos = next;
  }
}

/// Cells a mover treats as solid (bounces off): walls, static destroyers and
/// the exit.
bool _isSolidForMover(LevelData level, int r, int c) {
  final t = level.baseTypeAt(r, c);
  return t == CellType.wall ||
      t == CellType.destroyer ||
      t == CellType.movingDestroyer ||
      t == CellType.exit;
}

/// Build the runtime mover list for a level (positions reset to their starts).
List<MoverState> buildMovers(LevelData level) {
  final n = level.size;
  return [
    for (final m in level.movers)
      MoverState(
        m.horizontal ? m.r : m.c,
        m.horizontal ? m.c : m.r,
        m.dir,
        m.lo ?? 0,
        m.hi ?? (n - 1),
        m.horizontal,
        {
          // Solid positions along this mover's fixed row/column.
          for (var p = 0; p < n; p++)
            if (m.horizontal
                ? _isSolidForMover(level, m.r, p)
                : _isSolidForMover(level, p, m.c))
              p,
        },
      ),
  ];
}

/// Headless, deterministic run of a level with the given player-placed pieces.
/// Mirrors the tick rules used by the game screen, so it is the single source
/// of truth for verifying that a level is solvable.
///
/// Tick order: the dot and the moving destroyers move SIMULTANEOUSLY, then we
/// check whether any mover ended on the dot's final cell — if so, the dot dies.
/// If the dot and a mover merely cross paths (swap cells) the dot escapes. A
/// shield does NOT save the dot from a mover (pure timing hazards).
SimOutcome simulate(LevelData level, Map<int, PlacedElement> placed) =>
    simulateDetailed(level, placed).outcome;

/// Like [simulate], but also reports WHY the dot died (see [SimResult]). The
/// game screen uses the cause to show a clear fail message.
SimResult simulateDetailed(LevelData level, Map<int, PlacedElement> placed) {
  final n = level.size;

  // Forced arrows behave like immovable placed arrows.
  final forced = <int, PlacedElement>{};
  for (final a in level.forcedArrows) {
    forced[a.r * n + a.c] = PlacedElement(
      type: PlacedType.arrow,
      tool: a.dir.arrowTool,
      direction: a.dir,
    );
  }

  PlacedElement? pieceAt(int key) => placed[key] ?? forced[key];

  var r = level.start.r;
  var c = level.start.c;
  var dir = level.start.dir;
  var pause = 0;
  // The dot carries at most one shield aura at a time. Passing a shield cell
  // grants it; the next destroyer it hits is destroyed and the aura is spent.
  var shielded = false;
  // Cells cleared by a chain explosion (the hit destroyer + its adjacent walls).
  // They become passable empty cells for the rest of the run.
  final removed = <int>{};
  CellType effBase(int rr, int cc) =>
      removed.contains(rr * n + cc) ? CellType.empty : level.baseTypeAt(rr, cc);
  final movers = buildMovers(level);
  bool moverHit(int rr, int cc) =>
      movers.any((mv) => mv.row == rr && mv.col == cc);
  final maxTicks = n * n * 4 + 20;

  for (var t = 0; t < maxTicks; t++) {
    for (final mv in movers) {
      mv.step();
    }

    if (pause > 0) {
      pause--;
      // The dot held still this tick — a mover that ends on it still catches it.
      if (moverHit(r, c)) return const SimResult(SimOutcome.lose, DeathCause.patrol);
      continue;
    }

    final (dr, dc) = dir.delta;
    final nr = r + dr;
    final nc = c + dc;
    if (nr < 0 || nr >= n || nc < 0 || nc >= n) {
      return const SimResult(SimOutcome.lose, DeathCause.edge);
    }
    if (effBase(nr, nc) == CellType.wall) {
      return const SimResult(SimOutcome.lose, DeathCause.wall);
    }

    r = nr;
    c = nc;
    // Both have moved — die only if they share the FINAL cell. If the dot and a
    // mover merely crossed paths (swapped cells) the dot escapes.
    if (moverHit(r, c)) return const SimResult(SimOutcome.lose, DeathCause.patrol);
    final key = r * n + c;
    final base = effBase(r, c);
    if (base == CellType.gap) {
      return const SimResult(SimOutcome.lose, DeathCause.gap);
    }
    if (base == CellType.destroyer || base == CellType.movingDestroyer) {
      if (shielded) {
        // Chain explosion: the shield is spent, the destroyer is cleared, and
        // every wall orthogonally adjacent to it is demolished — opening a path.
        shielded = false;
        removed.add(key);
        removed.addAll(adjacentWallKeys(level, key));
      } else {
        return const SimResult(SimOutcome.lose, DeathCause.destroyer);
      }
    }
    // The start cell acts as a permanent forced arrow on every visit.
    if (base == CellType.start) dir = level.start.dir;

    final piece = pieceAt(key);
    if (piece != null) {
      switch (piece.type) {
        case PlacedType.arrow:
          dir = piece.direction!;
        case PlacedType.pause:
          pause = 2;
        case PlacedType.shield:
          shielded = true;
        case PlacedType.teleporter:
          for (final e in placed.entries) {
            if (e.value.type == PlacedType.teleporter && e.key != key) {
              r = e.key ~/ n;
              c = e.key % n;
              break;
            }
          }
      }
    }

    if (level.baseTypeAt(r, c) == CellType.exit) {
      return const SimResult(SimOutcome.win);
    }
  }

  // Ran out of ticks (loop) → not a solution; no specific death cause.
  return const SimResult(SimOutcome.lose);
}

/// Runs the level and returns the set of cell keys the dot visits if it wins,
/// or null if it loses. Used to verify forced arrows lie on the path.
Set<int>? tracePath(LevelData level, Map<int, PlacedElement> placed) {
  final n = level.size;
  final forced = <int, PlacedElement>{};
  for (final a in level.forcedArrows) {
    forced[a.r * n + a.c] = PlacedElement(
      type: PlacedType.arrow,
      tool: a.dir.arrowTool,
      direction: a.dir,
    );
  }
  PlacedElement? pieceAt(int key) => placed[key] ?? forced[key];

  var r = level.start.r;
  var c = level.start.c;
  var dir = level.start.dir;
  var pause = 0;
  var shielded = false;
  final removed = <int>{};
  CellType effBase(int rr, int cc) =>
      removed.contains(rr * n + cc) ? CellType.empty : level.baseTypeAt(rr, cc);
  final movers = buildMovers(level);
  bool moverHit(int rr, int cc) =>
      movers.any((mv) => mv.row == rr && mv.col == cc);
  final visited = <int>{r * n + c};
  final maxTicks = n * n * 4 + 20;

  for (var t = 0; t < maxTicks; t++) {
    for (final mv in movers) {
      mv.step();
    }
    if (pause > 0) {
      pause--;
      if (moverHit(r, c)) return null; // mover lands on the held-still dot
      continue;
    }
    final (dr, dc) = dir.delta;
    final nr = r + dr;
    final nc = c + dc;
    if (nr < 0 || nr >= n || nc < 0 || nc >= n) return null;
    if (effBase(nr, nc) == CellType.wall) return null;
    r = nr;
    c = nc;
    // Die only on a shared FINAL cell; crossing (swapping cells) is safe.
    if (moverHit(r, c)) return null;
    final base = effBase(r, c);
    if (base == CellType.gap) return null;
    if (base == CellType.destroyer || base == CellType.movingDestroyer) {
      if (shielded) {
        shielded = false;
        removed.add(r * n + c);
        removed.addAll(adjacentWallKeys(level, r * n + c));
      } else {
        return null;
      }
    }
    visited.add(r * n + c);
    if (base == CellType.start) dir = level.start.dir; // permanent redirector
    final piece = pieceAt(r * n + c);
    if (piece != null && piece.type == PlacedType.arrow) {
      dir = piece.direction!;
    } else if (piece != null && piece.type == PlacedType.pause) {
      pause = 2;
    } else if (piece != null && piece.type == PlacedType.shield) {
      shielded = true;
    }
    if (level.baseTypeAt(r, c) == CellType.exit) return visited;
  }
  return null;
}
