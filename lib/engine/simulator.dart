import '../models/game_state.dart';
import '../models/grid_cell.dart';
import '../models/level_data.dart';

/// Outcome of running a level configuration to completion.
enum SimOutcome { win, lose }

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
    if (level.baseTypeAt(nr, nc) == CellType.wall) return SimOutcome.lose;

    r = nr;
    c = nc;
    final base = level.baseTypeAt(r, c);
    if (base == CellType.gap ||
        base == CellType.destroyer ||
        base == CellType.movingDestroyer) {
      return SimOutcome.lose;
    }

    final key = r * n + c;
    final piece = pieceAt(key);
    if (piece != null) {
      switch (piece.type) {
        case PlacedType.arrow:
          dir = piece.direction!;
        case PlacedType.pause:
          pause = 2;
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
