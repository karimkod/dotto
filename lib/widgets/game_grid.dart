import 'package:flutter/material.dart';

import '../models/game_state.dart';
import '../models/grid_cell.dart';
import '../models/level_data.dart';
import '../theme/app_theme.dart';

/// Palette for the board, matching the prototype.
class _C {
  static const start = Color(0xFF81C784);
  static const exit = Color(0xFFFFD54F);
  static const wall = Color(0xFF78909C);
  static const destroyer = Color(0xFFEF5350);
  static const arrowFill = Color(0xFFE3F1FD);
  static const arrow = Color(0xFF1E88E5);
  static const pauseFill = Color(0xFFF3E5F8);
  static const pause = Color(0xFFBA68C8);
  static const teleFill = Color(0xFFFFE7DD);
  static const tele = Color(0xFFFF8A65);
}

/// Solid accent color used when a tool's cell glows.
Color toolGlowColor(ToolType tool) {
  switch (tool.placedType) {
    case PlacedType.arrow:
      return _C.arrow;
    case PlacedType.pause:
      return _C.pause;
    case PlacedType.teleporter:
      return _C.tele;
  }
}

/// A placed piece in the middle of its shrink-out (removal) animation.
class FadingPiece {
  FadingPiece(this.key, this.tool, this.direction);
  final int key;
  final ToolType tool;
  final Direction? direction;
  double progress = 0; // 0 → 1
}

/// Pop-in scale curve (overshoots ~1.1 then settles to 1.0).
double popScale(double p) => Curves.elasticOut.transform(p.clamp(0.0, 1.0));

/// Shrink-out scale curve: 1.0 → 0.8 → 0.0.
double shrinkScale(double p) {
  if (p <= 0) return 1;
  if (p < 0.3) return 1.0 - 0.2 * (p / 0.3);
  return 0.8 * (1 - (p - 0.3) / 0.7);
}

/// Semi-transparent preview of a tool that follows the finger during a drag.
class DragGhost extends StatelessWidget {
  const DragGhost({super.key, required this.tool, this.size = 58});

  final ToolType tool;
  final double size;

  @override
  Widget build(BuildContext context) {
    final Color fill;
    final Color color;
    switch (tool.placedType) {
      case PlacedType.arrow:
        fill = _C.arrowFill;
        color = _C.arrow;
      case PlacedType.pause:
        fill = _C.pauseFill;
        color = _C.pause;
      case PlacedType.teleporter:
        fill = _C.teleFill;
        color = _C.tele;
    }
    return Material(
      color: Colors.transparent,
      child: Opacity(
        opacity: 0.85,
        child: Container(
          width: size,
          height: size,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: fill,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: color, width: 3),
          ),
          child: Text(
            tool.glyph,
            style: TextStyle(
              fontSize: size * 0.42,
              height: 1,
              fontWeight: FontWeight.w900,
              color: color,
            ),
          ),
        ),
      ),
    );
  }
}

/// Maps between board pixels and cell coordinates for a square board of [side]
/// pixels holding [n] cells, with an outer [pad].
class GridGeometry {
  const GridGeometry(this.side, this.n, {this.pad = 8});

  final double side;
  final int n;
  final double pad;

  double get cell => (side - pad * 2) / n;

  /// Pixel center of cell (r, c).
  Offset center(int r, int c) =>
      Offset(pad + c * cell + cell / 2, pad + r * cell + cell / 2);

  /// Cell at a local pixel position, or null if outside the grid.
  (int r, int c)? cellAt(Offset p) {
    final c = ((p.dx - pad) / cell).floor();
    final r = ((p.dy - pad) / cell).floor();
    if (r < 0 || r >= n || c < 0 || c >= n) return null;
    return (r, c);
  }
}

/// Paints the board: outer frame, cells, hazards, trail, cell glows, placed
/// pieces (with pop-in / shrink-out scaling) and the drag preview. The moving
/// dot is drawn as a sibling widget on top.
class GameGridPainter extends CustomPainter {
  GameGridPainter({
    required this.level,
    required this.placed,
    required this.trail,
    required this.revision,
    required this.placeAnim,
    required this.removing,
    required this.cellGlow,
    required this.cellGlowColor,
    required this.glowTick,
    this.previewKey,
    this.previewTool,
  });

  final LevelData level;
  final Map<int, PlacedElement> placed;

  /// Ordered list of visited cells (most recent last).
  final List<int> trail;

  final int revision;

  /// Per-cell pop-in progress (0→1) for freshly placed pieces.
  final Map<int, double> placeAnim;

  /// Pieces currently shrinking away (removal animation).
  final List<FadingPiece> removing;

  /// Per-cell glow intensity (0→1) and color for the highlight effect.
  final Map<int, double> cellGlow;
  final Map<int, Color> cellGlowColor;

  /// Continuously-changing value so the painter repaints every frame while
  /// effects are running.
  final double glowTick;

  final int? previewKey;
  final ToolType? previewTool;

  @override
  void paint(Canvas canvas, Size size) {
    final n = level.size;
    final geo = GridGeometry(size.width, n);

    // Board background + thick outer frame.
    final boardRect = Offset.zero & size;
    final boardRRect =
        RRect.fromRectAndRadius(boardRect, const Radius.circular(22));
    canvas.drawRRect(boardRRect, Paint()..color = AppColors.background);
    canvas.drawRRect(
      boardRRect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4
        ..color = AppColors.ink,
    );

    // Base cells (no placed pieces — those are drawn scaled below).
    for (var r = 0; r < n; r++) {
      for (var c = 0; c < n; c++) {
        _paintBase(canvas, geo, r, c);
      }
    }

    _paintTrail(canvas, geo);

    // Cell glow highlights (dot entry, arrow flash, placement ripple).
    cellGlow.forEach((key, intensity) {
      _paintGlow(canvas, geo, key, intensity, cellGlowColor[key] ?? _C.arrow);
    });

    // Placed pieces, scaled by their pop-in animation.
    placed.forEach((key, piece) {
      final p = placeAnim[key];
      final scale = p == null ? 1.0 : popScale(p);
      _paintPiece(canvas, geo, key, piece.tool, piece.direction, scale);
    });

    // Pieces shrinking away.
    for (final f in removing) {
      _paintPiece(canvas, geo, f.key, f.tool, f.direction, shrinkScale(f.progress));
    }

    if (previewKey != null && previewTool != null) {
      _paintPreview(canvas, geo, previewKey!, previewTool!);
    }
  }

  RRect _cellRRect(GridGeometry geo, Offset center) => RRect.fromRectAndRadius(
        Rect.fromCenter(
            center: center, width: geo.cell - 7, height: geo.cell - 7),
        const Radius.circular(10),
      );

  void _paintBase(Canvas canvas, GridGeometry geo, int r, int c) {
    final center = geo.center(r, c);
    final rrect = _cellRRect(geo, center);
    final base = level.baseTypeAt(r, c);

    Color fill = AppColors.card;
    Color border = AppColors.ink.withValues(alpha: 0.85);
    String? glyph;
    Color glyphColor = AppColors.ink;
    bool dashedBorder = false;

    switch (base) {
      case CellType.start:
        fill = _C.start;
        border = const Color(0xFF5BA45F);
        glyph = level.start.dir.glyph;
        glyphColor = Colors.white;
      case CellType.exit:
        fill = _C.exit;
        border = const Color(0xFFE0B73C);
        glyph = '⚑';
        glyphColor = Colors.white;
      case CellType.wall:
        fill = _C.wall;
        border = const Color(0xFF5C6B73);
      case CellType.destroyer:
      case CellType.movingDestroyer:
        fill = _C.destroyer;
        border = const Color(0xFFC62828);
        glyph = '✕';
        glyphColor = Colors.white;
      case CellType.gap:
        fill = AppColors.background;
        border = AppColors.textSoft;
        dashedBorder = true;
      case CellType.empty:
        break;
    }

    canvas.drawRRect(rrect, Paint()..color = fill);

    final borderPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = border;
    if (dashedBorder) {
      _drawDashedRRect(canvas, rrect, borderPaint);
    } else {
      canvas.drawRRect(rrect, borderPaint);
    }

    if (glyph != null) {
      _drawGlyph(canvas, center, glyph, glyphColor, geo.cell * 0.42);
    }
  }

  void _paintPiece(Canvas canvas, GridGeometry geo, int key, ToolType tool,
      Direction? dir, double scale) {
    if (scale <= 0) return;
    final r = key ~/ geo.n;
    final c = key % geo.n;
    final center = geo.center(r, c);
    final rrect = _cellRRect(geo, center);
    final (fill, color, glyph) = _toolStyle(tool, dir);

    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.scale(scale);
    canvas.translate(-center.dx, -center.dy);

    canvas.drawRRect(rrect, Paint()..color = fill);
    canvas.drawRRect(
      rrect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..color = color,
    );
    _drawGlyph(canvas, center, glyph, color, geo.cell * 0.42);
    canvas.restore();
  }

  void _paintGlow(
      Canvas canvas, GridGeometry geo, int key, double intensity, Color color) {
    final i = intensity.clamp(0.0, 1.0);
    final r = key ~/ geo.n;
    final c = key % geo.n;
    final rrect = _cellRRect(geo, geo.center(r, c));
    canvas.drawRRect(rrect, Paint()..color = color.withValues(alpha: 0.18 * i));
    canvas.drawRRect(
      rrect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..color = color.withValues(alpha: 0.75 * i)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, 2 + 3 * i),
    );
  }

  void _paintTrail(Canvas canvas, GridGeometry geo) {
    if (trail.isEmpty) return;
    final start = trail.length <= 6 ? 0 : trail.length - 6;
    final visible = trail.sublist(start);
    for (var i = 0; i < visible.length; i++) {
      final key = visible[i];
      final r = key ~/ geo.n;
      final c = key % geo.n;
      if (level.baseTypeAt(r, c) == CellType.exit) continue;
      final center = geo.center(r, c);
      final recency = (i + 1) / visible.length; // newest → 1
      final radius = geo.cell * (0.14 + 0.07 * recency);
      // Warm outer glow.
      canvas.drawCircle(
        center,
        radius * 1.8,
        Paint()
          ..color = AppColors.accent.withValues(alpha: 0.10 * recency)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
      );
      // Core dot.
      canvas.drawCircle(
        center,
        radius,
        Paint()..color = AppColors.accent.withValues(alpha: 0.18 + 0.30 * recency),
      );
    }
  }

  /// Translucent ghost of the tool snapped to the hovered cell.
  void _paintPreview(Canvas canvas, GridGeometry geo, int key, ToolType tool) {
    final r = key ~/ geo.n;
    final c = key % geo.n;
    final center = geo.center(r, c);
    final rrect = _cellRRect(geo, center);

    final (fill, color, glyph) = _toolStyle(tool, tool.direction);
    canvas.drawRRect(rrect, Paint()..color = fill.withValues(alpha: 0.55));
    canvas.drawRRect(
      rrect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..color = color.withValues(alpha: 0.85),
    );
    _drawGlyph(canvas, center, glyph,
        color.withValues(alpha: 0.85), geo.cell * 0.42);
  }

  (Color fill, Color color, String glyph) _toolStyle(
      ToolType tool, Direction? dir) {
    switch (tool.placedType) {
      case PlacedType.arrow:
        return (_C.arrowFill, _C.arrow, (dir ?? tool.direction!).glyph);
      case PlacedType.pause:
        return (_C.pauseFill, _C.pause, '❚❚');
      case PlacedType.teleporter:
        return (_C.teleFill, _C.tele, '◎');
    }
  }

  void _drawGlyph(
      Canvas canvas, Offset center, String s, Color color, double fontSize) {
    final tp = TextPainter(
      text: TextSpan(
        text: s,
        style: TextStyle(
          color: color,
          fontSize: fontSize,
          fontWeight: FontWeight.w900,
          height: 1,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, center - Offset(tp.width / 2, tp.height / 2));
  }

  void _drawDashedRRect(Canvas canvas, RRect rrect, Paint paint) {
    final path = Path()..addRRect(rrect);
    const dash = 5.0;
    const gap = 4.0;
    for (final metric in path.computeMetrics()) {
      var d = 0.0;
      while (d < metric.length) {
        canvas.drawPath(metric.extractPath(d, d + dash), paint);
        d += dash + gap;
      }
    }
  }

  // The whole board surface is hittable so taps and drag-drops register on any
  // cell, not just where a piece/dot already paints.
  @override
  bool? hitTest(Offset position) => true;

  @override
  bool shouldRepaint(covariant GameGridPainter old) =>
      old.glowTick != glowTick ||
      old.revision != revision ||
      old.level != level ||
      old.previewKey != previewKey ||
      old.previewTool != previewTool;
}
