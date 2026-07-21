import 'grid_cell.dart';

/// High-level phase of a game.
enum GameStatus { planning, running, won, lost }

/// A piece the player has placed on the board.
class PlacedElement {
  const PlacedElement({
    required this.type,
    required this.tool,
    this.direction,
    this.portalIndex,
  });

  final PlacedType type;

  /// The toolkit item this came from (so removal can refund the right slot).
  final ToolType tool;

  /// Set for arrows.
  final Direction? direction;

  /// Placement order for teleporters, 0-based. One number carries everything
  /// about a portal: even is an ENTRANCE and odd an EXIT, `~/ 2` is which pair
  /// it belongs to (and so its colour), and `^ 1` is its partner's index. So
  /// the 1st entrance pairs with the 1st exit, the 2nd with the 2nd, and so on.
  ///
  /// Null on every other kind of piece.
  final int? portalIndex;

  /// True for the "way in" end of a pair. Purely cosmetic — the dot travels
  /// both directions (see [buildTeleportLinks]).
  bool get isPortalEntrance => portalIndex != null && portalIndex!.isEven;

  /// Which pair this portal belongs to, or null if it isn't a portal.
  int? get portalPair => portalIndex == null ? null : portalIndex! ~/ 2;

  PlacedElement withPortalIndex(int i) => PlacedElement(
        type: type,
        tool: tool,
        direction: direction,
        portalIndex: i,
      );
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
