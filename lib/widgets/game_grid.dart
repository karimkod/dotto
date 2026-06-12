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

/// Paints the static board: outer frame, cells, hazards, placed pieces and the
/// dot's trail. The moving dot itself is drawn as a sibling widget on top.
class GameGridPainter extends CustomPainter {
  GameGridPainter({
    required this.level,
    required this.placed,
    required this.trail,
    required this.revision,
    this.previewKey,
    this.previewTool,
  });

  final LevelData level;
  final Map<int, PlacedElement> placed;
  final Set<int> trail;

  /// Bumped by the screen whenever [placed] or [trail] change, so the painter
  /// repaints even though the underlying collections are mutated in place.
  final int revision;

  /// Cell index currently being hovered during a drag (null if none), plus the
  /// tool being dragged — used to draw a translucent placement preview.
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

    for (var r = 0; r < n; r++) {
      for (var c = 0; c < n; c++) {
        _paintCell(canvas, geo, r, c);
      }
    }

    if (previewKey != null && previewTool != null) {
      _paintPreview(canvas, geo, previewKey!, previewTool!);
    }
  }

  /// Translucent ghost of the tool snapped to the hovered cell.
  void _paintPreview(Canvas canvas, GridGeometry geo, int key, ToolType tool) {
    final r = key ~/ geo.n;
    final c = key % geo.n;
    final center = geo.center(r, c);
    final rect = Rect.fromCenter(
      center: center,
      width: geo.cell - 7,
      height: geo.cell - 7,
    );
    final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(10));

    final (fill, color, glyph) = _toolStyle(tool);
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

  (Color fill, Color color, String glyph) _toolStyle(ToolType tool) {
    switch (tool.placedType) {
      case PlacedType.arrow:
        return (_C.arrowFill, _C.arrow, tool.direction!.glyph);
      case PlacedType.pause:
        return (_C.pauseFill, _C.pause, '❚❚');
      case PlacedType.teleporter:
        return (_C.teleFill, _C.tele, '◎');
    }
  }

  void _paintCell(Canvas canvas, GridGeometry geo, int r, int c) {
    final center = geo.center(r, c);
    final rect = Rect.fromCenter(
      center: center,
      width: geo.cell - 7,
      height: geo.cell - 7,
    );
    final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(10));

    final base = level.baseTypeAt(r, c);
    final piece = placed[r * geo.n + c];

    Color fill = AppColors.card;
    Color border = AppColors.ink.withValues(alpha: 0.85);
    double borderWidth = 2;
    String? glyph;
    Color glyphColor = AppColors.ink;
    bool dashedBorder = false;

    if (piece != null) {
      switch (piece.type) {
        case PlacedType.arrow:
          fill = _C.arrowFill;
          border = _C.arrow;
          glyph = piece.direction!.glyph;
          glyphColor = _C.arrow;
        case PlacedType.pause:
          fill = _C.pauseFill;
          border = _C.pause;
          glyph = '❚❚';
          glyphColor = _C.pause;
        case PlacedType.teleporter:
          fill = _C.teleFill;
          border = _C.tele;
          glyph = '◎';
          glyphColor = _C.tele;
      }
    } else {
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
    }

    canvas.drawRRect(rrect, Paint()..color = fill);

    // Faint trail dot for visited empty/start cells.
    if (trail.contains(r * geo.n + c) && base != CellType.exit) {
      canvas.drawCircle(
        center,
        geo.cell * 0.14,
        Paint()..color = AppColors.accent.withValues(alpha: 0.30),
      );
    }

    final borderPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = borderWidth
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
        canvas.drawPath(
          metric.extractPath(d, d + dash),
          paint,
        );
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
      old.revision != revision ||
      old.level != level ||
      old.previewKey != previewKey ||
      old.previewTool != previewTool;
}
