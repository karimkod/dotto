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

  /// This heading turned 90° clockwise: up → right → down → left → up. Drives
  /// the rotating-arrow mechanic, which advances one quarter-turn per pass.
  Direction get rotatedCW {
    switch (this) {
      case Direction.up:
        return Direction.right;
      case Direction.right:
        return Direction.down;
      case Direction.down:
        return Direction.left;
      case Direction.left:
        return Direction.up;
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

  /// The arrow toolkit item that points this way.
  ToolType get arrowTool {
    switch (this) {
      case Direction.up:
        return ToolType.arrowUp;
      case Direction.down:
        return ToolType.arrowDown;
      case Direction.left:
        return ToolType.arrowLeft;
      case Direction.right:
        return ToolType.arrowRight;
    }
  }

  /// The single-use arrow that points this way.
  ToolType get oneShotTool {
    switch (this) {
      case Direction.up:
        return ToolType.oneShotUp;
      case Direction.down:
        return ToolType.oneShotDown;
      case Direction.left:
        return ToolType.oneShotLeft;
      case Direction.right:
        return ToolType.oneShotRight;
    }
  }
}

/// Base, level-defined contents of a cell (everything the player can't move).
enum CellType { empty, start, exit, wall, destroyer, movingDestroyer, gap }

/// A piece the player places on the board.
enum PlacedType { arrow, pause, teleporter, shield }

/// Selectable toolkit item kinds.
///
/// The `oneShot*` arrows point the same four ways as the ordinary ones and are
/// [PlacedType.arrow] like them, so placement, painting and the solvers all
/// treat them as arrows. The single difference is spelled out in the simulator:
/// the dot consumes one as it passes, and the cell is empty from then on.
enum ToolType {
  arrowUp,
  arrowDown,
  arrowLeft,
  arrowRight,
  oneShotUp,
  oneShotDown,
  oneShotLeft,
  oneShotRight,
  pause,
  teleporter,
  shield,
}

extension ToolTypeX on ToolType {
  PlacedType get placedType {
    switch (this) {
      case ToolType.pause:
        return PlacedType.pause;
      case ToolType.teleporter:
        return PlacedType.teleporter;
      case ToolType.shield:
        return PlacedType.shield;
      case ToolType.arrowUp:
      case ToolType.arrowDown:
      case ToolType.arrowLeft:
      case ToolType.arrowRight:
      case ToolType.oneShotUp:
      case ToolType.oneShotDown:
      case ToolType.oneShotLeft:
      case ToolType.oneShotRight:
        return PlacedType.arrow;
    }
  }

  /// True for an arrow the dot uses up on its way through. See [ToolType].
  bool get isOneShot {
    switch (this) {
      case ToolType.oneShotUp:
      case ToolType.oneShotDown:
      case ToolType.oneShotLeft:
      case ToolType.oneShotRight:
        return true;
      case ToolType.arrowUp:
      case ToolType.arrowDown:
      case ToolType.arrowLeft:
      case ToolType.arrowRight:
      case ToolType.pause:
      case ToolType.teleporter:
      case ToolType.shield:
        return false;
    }
  }

  Direction? get direction {
    switch (this) {
      case ToolType.arrowUp:
      case ToolType.oneShotUp:
        return Direction.up;
      case ToolType.arrowDown:
      case ToolType.oneShotDown:
        return Direction.down;
      case ToolType.arrowLeft:
      case ToolType.oneShotLeft:
        return Direction.left;
      case ToolType.arrowRight:
      case ToolType.oneShotRight:
        return Direction.right;
      case ToolType.pause:
      case ToolType.teleporter:
      case ToolType.shield:
        return null;
    }
  }

  String get glyph {
    switch (this) {
      case ToolType.arrowUp:
      case ToolType.oneShotUp:
        return '↑';
      case ToolType.arrowDown:
      case ToolType.oneShotDown:
        return '↓';
      case ToolType.arrowLeft:
      case ToolType.oneShotLeft:
        return '←';
      case ToolType.arrowRight:
      case ToolType.oneShotRight:
        return '→';
      case ToolType.pause:
        return '❚❚';
      case ToolType.teleporter:
        return '◎';
      case ToolType.shield:
        return '🛡';
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
      case ToolType.oneShotUp:
        return 'ONCE UP';
      case ToolType.oneShotDown:
        return 'ONCE DN';
      case ToolType.oneShotLeft:
        return 'ONCE LT';
      case ToolType.oneShotRight:
        return 'ONCE RT';
      case ToolType.pause:
        return 'PAUSE';
      case ToolType.teleporter:
        return 'WARP';
      case ToolType.shield:
        return 'SHIELD';
    }
  }
}
