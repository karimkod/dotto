/// Movement direction for the dot, arrows and start cell.
enum Direction { up, down, left, right }

extension DirectionX on Direction {
  /// Row/column delta for one step in this direction.
  (int dr, int dc) get delta {
    switch (this) {
      case Direction.up:
        return (-1, 0);
      case Direction.down:
        return (1, 0);
      case Direction.left:
        return (0, -1);
      case Direction.right:
        return (0, 1);
    }
  }

  /// Unicode chevron used to render the direction.
  String get glyph {
    switch (this) {
      case Direction.up:
        return '↑';
      case Direction.right:
        return '→';
      case Direction.down:
        return '↓';
      case Direction.left:
        return '←';
    }
  }
}

/// Base, level-defined contents of a cell (everything the player can't move).
enum CellType { empty, start, exit, wall, destroyer, movingDestroyer, gap }

/// A piece the player places on the board.
enum PlacedType { arrow, pause, teleporter }

/// Selectable toolkit item kinds.
enum ToolType { arrowUp, arrowDown, arrowLeft, arrowRight, pause, teleporter }

extension ToolTypeX on ToolType {
  PlacedType get placedType {
    switch (this) {
      case ToolType.pause:
        return PlacedType.pause;
      case ToolType.teleporter:
        return PlacedType.teleporter;
      case ToolType.arrowUp:
      case ToolType.arrowDown:
      case ToolType.arrowLeft:
      case ToolType.arrowRight:
        return PlacedType.arrow;
    }
  }

  Direction? get direction {
    switch (this) {
      case ToolType.arrowUp:
        return Direction.up;
      case ToolType.arrowDown:
        return Direction.down;
      case ToolType.arrowLeft:
        return Direction.left;
      case ToolType.arrowRight:
        return Direction.right;
      case ToolType.pause:
      case ToolType.teleporter:
        return null;
    }
  }

  String get glyph {
    switch (this) {
      case ToolType.arrowUp:
        return '↑';
      case ToolType.arrowDown:
        return '↓';
      case ToolType.arrowLeft:
        return '←';
      case ToolType.arrowRight:
        return '→';
      case ToolType.pause:
        return '❚❚';
      case ToolType.teleporter:
        return '◎';
    }
  }

  String get label {
    switch (this) {
      case ToolType.arrowUp:
        return 'UP';
      case ToolType.arrowDown:
        return 'DOWN';
      case ToolType.arrowLeft:
        return 'LEFT';
      case ToolType.arrowRight:
        return 'RIGHT';
      case ToolType.pause:
        return 'PAUSE';
      case ToolType.teleporter:
        return 'WARP';
    }
  }
}
