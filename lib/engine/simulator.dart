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

/// Every piece the LEVEL pins to the board, keyed by cell: fixed arrows, fixed
/// shields and fixed pauses. They behave exactly like the player's own pieces
/// once the run starts — the only difference is that they cannot be placed,
/// moved or removed, and they are not drawn from the toolkit.
///
/// Single source of truth: the simulator, the solver, the live game and the
/// painter all build their "forced" map from here, so a new kind of fixed piece
/// only has to be taught to one place.
Map<int, PlacedElement> buildForcedPieces(LevelData level) {
  final n = level.size;
  final out = <int, PlacedElement>{};
  for (final a in level.forcedArrows) {
    out[a.r * n + a.c] = PlacedElement(
      type: PlacedType.arrow,
      tool: a.dir.arrowTool,
      direction: a.dir,
    );
  }
  for (final p in level.forcedShields) {
    out[p.r * n + p.c] = const PlacedElement(
      type: PlacedType.shield,
      tool: ToolType.shield,
      direction: null,
    );
  }
  for (final p in level.forcedPauses) {
    out[p.r * n + p.c] = const PlacedElement(
      type: PlacedType.pause,
      tool: ToolType.pause,
      direction: null,
    );
  }
  return out;
}

/// Mutable runtime state of a patrolling (moving) destroyer.
class MoverState {
  MoverState(this.fixed, this.pos, this.dir, this.size, this.horizontal,
      this.blocked);
  final int fixed;
  int pos;
  int dir;

  /// Grid size along the moving axis; the mover bounces at the edges (0..size-1).
  final int size;
  final bool horizontal;

  /// Positions (along the patrol axis) that were solid AT LEVEL START — walls,
  /// static destroyers, the exit. This is a snapshot and never changes, so it
  /// must always be read together with the run's live removed-cell set: a chain
  /// explosion turns a wall into floor, and the patrol has to sweep through the
  /// new opening rather than bounce off a wall that is no longer there.
  final Set<int> blocked;

  int get row => horizontal ? fixed : pos;
  int get col => horizontal ? pos : fixed;

  /// Cell key of position [p] along this patrol's lane.
  int keyAt(int p) => horizontal ? fixed * size + p : p * size + fixed;

  bool _solid(int p, Set<int> removed) {
    if (p < 0 || p >= size) return true; // grid edge
    if (!blocked.contains(p)) return false;
    return !removed.contains(keyAt(p)); // blown open? then it's floor now
  }

  /// Advance one cell, bouncing at the grid edge and off any cell still solid
  /// (wall, static destroyer, exit). If both neighbours are solid the mover is
  /// trapped and stays put.
  ///
  /// [removed] is the run's live set of cell keys cleared by chain explosions.
  /// It is a required argument on purpose: passing a stale or empty set silently
  /// makes patrols bounce off demolished walls, which is hard to spot in play.
  void step(Set<int> removed) {
    var next = pos + dir;
    if (_solid(next, removed)) {
      dir = -dir;
      next = pos + dir;
      if (_solid(next, removed)) return; // boxed in on both sides — can't move
    }
    pos = next;
  }
}

/// True when the dot and a patrol swapped cells this tick: the dot stepped into
/// the cell the patrol just left, and the patrol stepped into the cell the dot
/// just left. They never share a cell, so a final-cell-only check misses it and
/// the two slide through one another.
///
/// Every code path that moves the dot past a patrol must apply this — the live
/// game tick, [simulateDetailed], [tracePath] and the solver's own path search —
/// or the game and the solver disagree about what kills you.
bool moversCrossed({
  required int dotFromR,
  required int dotFromC,
  required int dotToR,
  required int dotToC,
  required int moverFromR,
  required int moverFromC,
  required int moverToR,
  required int moverToC,
}) =>
    moverFromR == dotToR &&
    moverFromC == dotToC &&
    moverToR == dotFromR &&
    moverToC == dotFromC;

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
        n,
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
/// The dot ALSO dies when it and a patrol trade places (see [moversCrossed]):
/// they never share a cell, but they pass straight through each other, which
/// reads on screen as the dot surviving a direct hit. A shield saves the dot in
/// either case, destroying the patrol and chain-exploding the walls beside it.
SimOutcome simulate(LevelData level, Map<int, PlacedElement> placed) =>
    simulateDetailed(level, placed).outcome;

/// Like [simulate], but also reports WHY the dot died (see [SimResult]). The
/// game screen uses the cause to show a clear fail message.
SimResult simulateDetailed(LevelData level, Map<int, PlacedElement> placed) {
  final n = level.size;

  // Forced arrows behave like immovable placed arrows.
  final forced = buildForcedPieces(level);

  PlacedElement? pieceAt(int key) => placed[key] ?? forced[key];

  var r = level.start.r;
  var c = level.start.c;
  var dir = level.start.dir;
  var pause = 0;
  // The dot carries at most one shield aura at a time. Passing a shield cell
  // grants it; the next destroyer it hits is destroyed and the aura is spent.
  var shielded = false;
  // Shield cells already collected — picked up once, they leave the grid and
  // can't be collected again.
  final takenShields = <int>{};
  // Cells cleared by a chain explosion (the hit destroyer + its adjacent walls).
  // They become passable empty cells for the rest of the run.
  final removed = <int>{};
  CellType effBase(int rr, int cc) =>
      removed.contains(rr * n + cc) ? CellType.empty : level.baseTypeAt(rr, cc);
  final movers = buildMovers(level);
  // Where each patrol stood before this tick's step, so a crossing can be spotted.
  var was = <MoverState, (int, int)>{};
  // Resolve any patrol(s) that hit the dot — either by ending on its cell or by
  // trading places with it. A shield is spent to destroy the mover(s) and
  // chain-explode adjacent walls (the dot survives); without a shield the dot
  // dies. [fromR]/[fromC] is the cell the dot just left. Returns true when fatal.
  bool moverCollision(int rr, int cc, {int? fromR, int? fromC}) {
    final hit = movers.where((mv) {
      if (mv.row == rr && mv.col == cc) return true;
      final w = was[mv];
      if (w == null || fromR == null || fromC == null) return false;
      return moversCrossed(
        dotFromR: fromR,
        dotFromC: fromC,
        dotToR: rr,
        dotToC: cc,
        moverFromR: w.$1,
        moverFromC: w.$2,
        moverToR: mv.row,
        moverToC: mv.col,
      );
    }).toList();
    if (hit.isEmpty) return false;
    if (!shielded) return true;
    shielded = false;
    for (final mv in hit) {
      movers.remove(mv);
      final mk = mv.row * n + mv.col;
      removed.add(mk);
      removed.addAll(adjacentWallKeys(level, mk));
    }
    return false;
  }

  final maxTicks = n * n * 4 + 20;

  for (var t = 0; t < maxTicks; t++) {
    was = {for (final mv in movers) mv: (mv.row, mv.col)};
    for (final mv in movers) {
      mv.step(removed);
    }

    if (pause > 0) {
      pause--;
      // The dot held still this tick — a mover that ends on it still catches it.
      if (moverCollision(r, c)) {
        return const SimResult(SimOutcome.lose, DeathCause.patrol);
      }
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

    final fromR = r, fromC = c;
    r = nr;
    c = nc;
    // Both have moved — a patrol kills the dot by sharing its final cell OR by
    // trading places with it (passing through counts as a hit).
    if (moverCollision(r, c, fromR: fromR, fromC: fromC)) {
      return const SimResult(SimOutcome.lose, DeathCause.patrol);
    }
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
          // Collected once; revisiting the (now-empty) cell re-grants nothing.
          if (takenShields.add(key)) shielded = true;
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
  final forced = buildForcedPieces(level);
  PlacedElement? pieceAt(int key) => placed[key] ?? forced[key];

  var r = level.start.r;
  var c = level.start.c;
  var dir = level.start.dir;
  var pause = 0;
  var shielded = false;
  final takenShields = <int>{};
  final removed = <int>{};
  CellType effBase(int rr, int cc) =>
      removed.contains(rr * n + cc) ? CellType.empty : level.baseTypeAt(rr, cc);
  final movers = buildMovers(level);
  var was = <MoverState, (int, int)>{};
  // See simulate(): a shield destroys the patrol(s) that hit the dot — by
  // sharing its cell or by trading places with it — and chain-explodes adjacent
  // walls; otherwise the dot dies. Returns true if fatal.
  bool moverCollision(int rr, int cc, {int? fromR, int? fromC}) {
    final hit = movers.where((mv) {
      if (mv.row == rr && mv.col == cc) return true;
      final w = was[mv];
      if (w == null || fromR == null || fromC == null) return false;
      return moversCrossed(
        dotFromR: fromR,
        dotFromC: fromC,
        dotToR: rr,
        dotToC: cc,
        moverFromR: w.$1,
        moverFromC: w.$2,
        moverToR: mv.row,
        moverToC: mv.col,
      );
    }).toList();
    if (hit.isEmpty) return false;
    if (!shielded) return true;
    shielded = false;
    for (final mv in hit) {
      movers.remove(mv);
      final mk = mv.row * n + mv.col;
      removed.add(mk);
      removed.addAll(adjacentWallKeys(level, mk));
    }
    return false;
  }

  final visited = <int>{r * n + c};
  final maxTicks = n * n * 4 + 20;

  for (var t = 0; t < maxTicks; t++) {
    was = {for (final mv in movers) mv: (mv.row, mv.col)};
    for (final mv in movers) {
      mv.step(removed);
    }
    if (pause > 0) {
      pause--;
      if (moverCollision(r, c)) return null; // mover lands on the held-still dot
      continue;
    }
    final (dr, dc) = dir.delta;
    final nr = r + dr;
    final nc = c + dc;
    if (nr < 0 || nr >= n || nc < 0 || nc >= n) return null;
    if (effBase(nr, nc) == CellType.wall) return null;
    final fromR = r, fromC = c;
    r = nr;
    c = nc;
    // A shared final cell, or a crossing — both are fatal without a shield.
    if (moverCollision(r, c, fromR: fromR, fromC: fromC)) return null;
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
      if (takenShields.add(r * n + c)) shielded = true; // collected once
    }
    if (level.baseTypeAt(r, c) == CellType.exit) return visited;
  }
  return null;
}
