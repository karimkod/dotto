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
enum PlacedType { arrow, pause, teleporter, shield, bouncer }

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
  // A bouncer turns the dot a quarter-turn, and which way depends on the side
  // it comes in from (see [ToolTypeX.bounce]). The slash kind joins the left
  // side of its cell to the top and the right to the bottom; the backslash
  // kind joins left to bottom and right to top. Last, so every older tool
  // keeps its index.
  bouncerSlash,
  bouncerBackslash,
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
      case ToolType.bouncerSlash:
      case ToolType.bouncerBackslash:
        return PlacedType.bouncer;
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
      case ToolType.bouncerSlash:
      case ToolType.bouncerBackslash:
        return false;
    }
  }

  /// True for either kind of bouncer. See [bounce].
  bool get isBouncer =>
      this == ToolType.bouncerSlash || this == ToolType.bouncerBackslash;

  /// The heading a bouncer sends the dot off on, given the [heading] it
  /// arrives with. Always a quarter-turn: a bouncer never lets the dot run
  /// straight on and never sends it back. The slash kind swaps right with up
  /// and left with down; the backslash kind swaps right with down and left
  /// with up. So one bouncer turns the dot one way from one side and the
  /// other way from another, which is the whole point of the piece.
  ///
  /// Any other tool leaves [heading] as it is.
  Direction bounce(Direction heading) {
    switch (this) {
      case ToolType.bouncerSlash:
        return switch (heading) {
          Direction.right => Direction.up,
          Direction.up => Direction.right,
          Direction.left => Direction.down,
          Direction.down => Direction.left,
        };
      case ToolType.bouncerBackslash:
        return switch (heading) {
          Direction.right => Direction.down,
          Direction.down => Direction.right,
          Direction.left => Direction.up,
          Direction.up => Direction.left,
        };
      case ToolType.arrowUp:
      case ToolType.arrowDown:
      case ToolType.arrowLeft:
      case ToolType.arrowRight:
      case ToolType.oneShotUp:
      case ToolType.oneShotDown:
      case ToolType.oneShotLeft:
      case ToolType.oneShotRight:
      case ToolType.pause:
      case ToolType.teleporter:
      case ToolType.shield:
        return heading;
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
      case ToolType.bouncerSlash:
      case ToolType.bouncerBackslash:
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
      case ToolType.bouncerSlash:
        return '/';
      case ToolType.bouncerBackslash:
        return '\u005C';
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
      case ToolType.bouncerSlash:
        return 'BOUNCE /';
      case ToolType.bouncerBackslash:
        return 'BOUNCE \u005C';
    }
  }
}
