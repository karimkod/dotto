import '../models/game_state.dart';
import '../models/grid_cell.dart';
import '../models/level_data.dart';

/// Outcome of running a level configuration to completion.
enum SimOutcome { win, lose }

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

/// Headless, deterministic run of a level with the given player-placed pieces.
/// Mirrors the tick rules used by the game screen, so it is the single source
/// of truth for verifying that a level is solvable.
///
/// (World 1 uses no moving hazards, so movers are not simulated here.)
SimOutcome simulate(LevelData level, Map<int, PlacedElement> placed) {
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
  final maxTicks = n * n * 4 + 20;

  for (var t = 0; t < maxTicks; t++) {
    if (pause > 0) {
      pause--;
      continue;
    }

    final (dr, dc) = dir.delta;
    final nr = r + dr;
    final nc = c + dc;
    if (nr < 0 || nr >= n || nc < 0 || nc >= n) return SimOutcome.lose;
    if (effBase(nr, nc) == CellType.wall) return SimOutcome.lose;

    r = nr;
    c = nc;
    final key = r * n + c;
    final base = effBase(r, c);
    if (base == CellType.gap) return SimOutcome.lose;
    if (base == CellType.destroyer || base == CellType.movingDestroyer) {
      if (shielded) {
        // Chain explosion: the shield is spent, the destroyer is cleared, and
        // every wall orthogonally adjacent to it is demolished — opening a path.
        shielded = false;
        removed.add(key);
        removed.addAll(adjacentWallKeys(level, key));
      } else {
        return SimOutcome.lose;
      }
    }

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

    if (level.baseTypeAt(r, c) == CellType.exit) return SimOutcome.win;
  }

  return SimOutcome.lose; // ran out of ticks (loop) → not a solution
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
  final visited = <int>{r * n + c};
  final maxTicks = n * n * 4 + 20;

  for (var t = 0; t < maxTicks; t++) {
    if (pause > 0) {
      pause--;
      continue;
    }
    final (dr, dc) = dir.delta;
    final nr = r + dr;
    final nc = c + dc;
    if (nr < 0 || nr >= n || nc < 0 || nc >= n) return null;
    if (effBase(nr, nc) == CellType.wall) return null;
    r = nr;
    c = nc;
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
