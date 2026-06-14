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
// OPEN grids (60+ placeable cells, 5 pieces → tens of millions of full
// simulations). The functions below instead follow the dot's actual journey
// and only ever consider arrows on cells the dot reaches — the only arrows that
// can change the outcome. This scales to the open exam levels.

bool _lethal(LevelData level, int r, int c) {
  final b = level.baseTypeAt(r, c);
  return b == CellType.gap ||
      b == CellType.destroyer ||
      b == CellType.movingDestroyer;
}

/// Smallest number of on-path arrows any solution needs (-1 if unsolvable).
///
/// Equivalent to [minSolutionPieces] but computed by tracing the dot rather
/// than brute-forcing the board, with a branch-and-bound prune: once a partial
/// placement already uses as many arrows as the best solution found, the branch
/// can't improve and is abandoned. When this equals [toolkitTotal] the level is
/// "tight" — every solution must use the whole toolkit, so no piece is wasted.
int pathMinPieces(LevelData level) {
  final n = level.size;
  final forced = <int, Direction>{
    for (final a in level.forcedArrows) a.r * n + a.c: a.dir,
  };
  final remaining = <ToolType, int>{
    for (final e in level.toolkit)
      if (e.type.direction != null) e.type: e.count,
  };
  final placed = <int, Direction>{};
  final seen = <int>{};
  var best = 1 << 30; // fewest-arrow win found so far

  void advance(int r, int c, Direction dir) {
    if (placed.length >= best) return; // can't beat the best solution
    final (dr, dc) = dir.delta;
    final nr = r + dr, nc = c + dc;
    if (nr < 0 || nr >= n || nc < 0 || nc >= n) return;
    if (level.baseTypeAt(nr, nc) == CellType.wall) return;
    if (_lethal(level, nr, nc)) return;
    final key = nr * n + nc;
    if (level.baseTypeAt(nr, nc) == CellType.exit) {
      best = placed.length; // guard above guarantees this is an improvement
      return;
    }
    final state = key * 4 + dir.index;
    if (seen.contains(state)) return; // loop without reaching the exit
    seen.add(state);

    final forcedDir = forced[key];
    final here = placed[key];
    if (forcedDir != null) {
      advance(nr, nc, forcedDir);
    } else if (here != null) {
      advance(nr, nc, here);
    } else if (level.baseTypeAt(nr, nc) == CellType.empty) {
      advance(nr, nc, dir); // leave empty, continue straight
      for (final type in remaining.keys) {
        if (remaining[type]! <= 0) continue;
        remaining[type] = remaining[type]! - 1;
        placed[key] = type.direction!;
        advance(nr, nc, type.direction!);
        placed.remove(key);
        remaining[type] = remaining[type]! + 1;
      }
    } else {
      advance(nr, nc, dir); // start cell etc. — pass straight through
    }
    seen.remove(state);
  }

  advance(level.start.r, level.start.c, level.start.dir);
  return best == (1 << 30) ? -1 : best;
}

/// All distinct on-path placements that win, capped at [maxResults]. For a
/// tight level (where [pathMinPieces] == [toolkitTotal]) every entry uses the
/// whole toolkit, so the count is the number of genuinely different solutions —
/// the design goal is exactly one (or very few).
List<Map<int, PlacedElement>> pathSolve(LevelData level,
    {int maxResults = 256}) {
  final n = level.size;
  final forced = <int, Direction>{
    for (final a in level.forcedArrows) a.r * n + a.c: a.dir,
  };
  final remaining = <ToolType, int>{
    for (final e in level.toolkit)
      if (e.type.direction != null) e.type: e.count,
  };
  final placed = <int, PlacedElement>{};
  final seen = <int>{};
  final results = <Map<int, PlacedElement>>[];

  void advance(int r, int c, Direction dir) {
    if (results.length >= maxResults) return;
    final (dr, dc) = dir.delta;
    final nr = r + dr, nc = c + dc;
    if (nr < 0 || nr >= n || nc < 0 || nc >= n) return;
    if (level.baseTypeAt(nr, nc) == CellType.wall) return;
    if (_lethal(level, nr, nc)) return;
    final key = nr * n + nc;
    if (level.baseTypeAt(nr, nc) == CellType.exit) {
      results.add(Map.of(placed));
      return;
    }
    final state = key * 4 + dir.index;
    if (seen.contains(state)) return;
    seen.add(state);

    final forcedDir = forced[key];
    final here = placed[key];
    if (forcedDir != null) {
      advance(nr, nc, forcedDir);
    } else if (here != null) {
      advance(nr, nc, here.direction!);
    } else if (level.baseTypeAt(nr, nc) == CellType.empty) {
      advance(nr, nc, dir);
      for (final type in remaining.keys) {
        if (remaining[type]! <= 0) continue;
        remaining[type] = remaining[type]! - 1;
        placed[key] = _element(type);
        advance(nr, nc, type.direction!);
        placed.remove(key);
        remaining[type] = remaining[type]! + 1;
      }
    } else {
      advance(nr, nc, dir);
    }
    seen.remove(state);
  }

  advance(level.start.r, level.start.c, level.start.dir);
  return results;
}
