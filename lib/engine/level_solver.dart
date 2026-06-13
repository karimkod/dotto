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
