import 'grid_cell.dart';

/// High-level phase of a game.
enum GameStatus { planning, running, won, lost }

/// A piece the player has placed on the board.
class PlacedElement {
  const PlacedElement({
    required this.type,
    required this.tool,
    this.direction,
  });

  final PlacedType type;

  /// The toolkit item this came from (so removal can refund the right slot).
  final ToolType tool;

  /// Set for arrows.
  final Direction? direction;
}

/// Mutable runtime state of the moving dot.
class DotState {
  DotState({
    required this.r,
    required this.c,
    required this.dir,
    this.pause = 0,
  });

  int r;
  int c;
  Direction dir;

  /// Remaining ticks the dot stays paused.
  int pause;
}
