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
      if (level.forcedArrowAt(r, c) != null) continue;
      cells.add(r * n + c);
    }
  }
  return cells;
}

PlacedElement _element(ToolType t) =>
    PlacedElement(type: t.placedType, tool: t, direction: t.direction);

/// Brute-force every distinct way to place a subset of the toolkit on the
/// board and return all configurations that solve the level. Visiting cells in
/// index order yields each configuration exactly once.
List<Map<int, PlacedElement>> solveAll(LevelData level) {
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
    // Leave this cell empty.
    recurse(i + 1);
    // Or place any still-available tool here.
    final cell = cells[i];
    for (final type in remaining.keys) {
      if (remaining[type]! <= 0) continue;
      remaining[type] = remaining[type]! - 1;
      current[cell] = _element(type);
      recurse(i + 1);
      current.remove(cell);
      remaining[type] = remaining[type]! + 1;
    }
  }

  recurse(0);
  return solutions;
}

/// True if at least one placement of the toolkit solves the level.
bool isSolvable(LevelData level) => solveAll(level).isNotEmpty;

/// Total number of pieces in the toolkit.
int toolkitTotal(LevelData level) =>
    level.toolkit.fold(0, (sum, e) => sum + e.count);

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

/// Toolkit pieces the path solver can place: arrows (which turn the dot) and
/// shields (which grant the protective aura). Pause/teleporter are not used by
/// the authored worlds and are left to the brute-force [solveAll].
Map<ToolType, int> _placeableKit(LevelData level) => {
      for (final e in level.toolkit)
        if (e.type.direction != null || e.type == ToolType.shield)
          e.type: e.count,
    };

/// Smallest number of pieces (arrows + shields) any solution needs (-1 if
/// unsolvable). Branch-and-bound on the fewest-piece win found. When this equals
/// [toolkitTotal] the level is "tight" — no piece can be left unused.
int pathMinPieces(LevelData level) {
  final n = level.size;
  final forced = <int, Direction>{
    for (final a in level.forcedArrows) a.r * n + a.c: a.dir,
  };
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
      final forcedDir = forced[key];
      final here = placed[key];
      if (forcedDir != null) {
        advance(nr, nc, forcedDir, shielded, removed);
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
List<Map<int, PlacedElement>> pathSolve(LevelData level,
    {int maxResults = 256}) {
  final n = level.size;
  final forced = <int, Direction>{
    for (final a in level.forcedArrows) a.r * n + a.c: a.dir,
  };
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
      final forcedDir = forced[key];
      final here = placed[key];
      if (forcedDir != null) {
        advance(nr, nc, forcedDir, shielded, removed);
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
