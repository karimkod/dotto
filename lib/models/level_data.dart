import 'grid_cell.dart';

/// A board coordinate (row, column).
class Pos {
  const Pos(this.r, this.c);
  final int r;
  final int c;
}

/// The start cell: position + the direction the dot leaves in.
class StartSpec {
  const StartSpec(this.r, this.c, this.dir);
  final int r;
  final int c;
  final Direction dir;
}

/// One toolkit entry: a tool and how many of it the player has.
class ToolkitEntry {
  const ToolkitEntry(this.type, this.count);
  final ToolType type;
  final int count;
}

/// A pre-placed arrow fixed to the board — it redirects the dot like a placed
/// arrow but cannot be moved or removed.
class ForcedArrow {
  const ForcedArrow(this.r, this.c, this.dir);
  final int r;
  final int c;
  final Direction dir;
}

/// A destroyer that patrols a row ([horizontal]) or column, moving one cell per
/// beat and bouncing off the grid edges and any solid cell (wall, static
/// destroyer, exit) in its lane. [r],[c] is its starting cell; [dir] is the
/// first step (+1 or -1) along the moving axis.
class MovingDestroyer {
  const MovingDestroyer(
    this.r,
    this.c, {
    required this.horizontal,
    this.dir = 1,
  });
  final int r;
  final int c;
  final bool horizontal;
  final int dir;
}

/// Static definition of a single level.
class LevelData {
  const LevelData({
    required this.id,
    required this.size,
    required this.title,
    required this.tip,
    required this.start,
    required this.exit,
    required this.toolkit,
    this.walls = const [],
    this.destroyers = const [],
    this.gaps = const [],
    this.forcedArrows = const [],
    this.movers = const [],
  });

  final int id;
  final int size;
  final String title;
  final String tip;
  final StartSpec start;
  final Pos exit;
  final List<ToolkitEntry> toolkit;
  final List<Pos> walls;
  final List<Pos> destroyers;
  final List<Pos> gaps;
  final List<ForcedArrow> forcedArrows;
  final List<MovingDestroyer> movers;

  /// The fixed arrow at (r, c), or null if none.
  Direction? forcedArrowAt(int r, int c) {
    for (final a in forcedArrows) {
      if (a.r == r && a.c == c) return a.dir;
    }
    return null;
  }

  /// The level-defined contents of cell (r, c), ignoring placed pieces.
  CellType baseTypeAt(int r, int c) {
    if (start.r == r && start.c == c) return CellType.start;
    if (exit.r == r && exit.c == c) return CellType.exit;
    for (final w in walls) {
      if (w.r == r && w.c == c) return CellType.wall;
    }
    for (final d in destroyers) {
      if (d.r == r && d.c == c) return CellType.destroyer;
    }
    for (final g in gaps) {
      if (g.r == r && g.c == c) return CellType.gap;
    }
    return CellType.empty;
  }
}
