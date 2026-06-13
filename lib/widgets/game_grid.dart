import 'dart:math' as math;

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

/// Weighty pop-in: 0 → 1.3 → 0.95 → 1.05 → 1.0 (bouncy overshoot + settle).
final TweenSequence<double> _popTween = TweenSequence<double>([
  TweenSequenceItem(
    tween: Tween(begin: 0.0, end: 1.3).chain(CurveTween(curve: Curves.easeOutCubic)),
    weight: 34,
  ),
  TweenSequenceItem(
    tween: Tween(begin: 1.3, end: 0.95).chain(CurveTween(curve: Curves.easeInOut)),
    weight: 26,
  ),
  TweenSequenceItem(
    tween: Tween(begin: 0.95, end: 1.05).chain(CurveTween(curve: Curves.easeInOut)),
    weight: 20,
  ),
  TweenSequenceItem(
    tween: Tween(begin: 1.05, end: 1.0).chain(CurveTween(curve: Curves.easeOut)),
    weight: 20,
  ),
]);

double popScale(double p) => _popTween.transform(p.clamp(0.0, 1.0));

/// Extra border thickness while the piece lands. Progress fractions are of the
/// ~600ms pop: thicken over ~150ms, hold ~100ms, then thin back over ~250ms.
double placeBorderBoost(double p) {
  const peak = 2.5;
  if (p < 0.25) return peak * (p / 0.25); // thicken
  if (p < 0.42) return peak; // hold
  if (p < 0.83) return peak * (1 - (p - 0.42) / 0.41); // thin back
  return 0;
}

/// Shrink-out scale curve: 1.0 → 0.8 → 0.0.
double shrinkScale(double p) {
  if (p <= 0) return 1;
  if (p < 0.3) return 1.0 - 0.2 * (p / 0.3);
  return 0.8 * (1 - (p - 0.3) / 0.7);
}

/// Neighbor ripple pulse: 1.0 → ~1.09 → 1.0.
double pulseScale(double p) => 1 + 0.09 * math.sin(math.pi * p.clamp(0.0, 1.0));

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
        opacity: 0.92,
        child: Container(
          width: size,
          height: size,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: fill,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: color, width: 3),
            // Soft shadow so the piece feels lifted off the board.
            boxShadow: [
              BoxShadow(
                color: AppColors.ink.withValues(alpha: 0.28),
                blurRadius: size * 0.22,
                offset: Offset(0, size * 0.14),
              ),
            ],
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
    required this.forced,
    required this.trail,
    required this.revision,
    required this.placeAnim,
    required this.removing,
    required this.cellGlow,
    required this.cellGlowColor,
    required this.cellPulse,
    required this.glowTick,
    required this.showStartHint,
    required this.winProgress,
    this.previewKey,
    this.previewTool,
  });

  final LevelData level;
  final Map<int, PlacedElement> placed;

  /// Immovable, level-defined arrows (drawn with a fixed "pinned" look).
  final Map<int, PlacedElement> forced;

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

  /// Per-cell ripple-pulse progress (0→1) for neighbor reactions.
  final Map<int, double> cellPulse;

  /// Continuously-changing value so the painter repaints every frame while
  /// effects are running.
  final double glowTick;

  /// Whether to draw the pulsing start-direction indicator (planning phase).
  final bool showStartHint;

  /// 0 = no win celebration; 0→1 drives the on-grid celebration animation.
  final double winProgress;

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

    if (showStartHint) _paintStartHint(canvas, geo);

    // Cell glow highlights (dot entry, arrow flash, placement ripple).
    cellGlow.forEach((key, intensity) {
      _paintGlow(canvas, geo, key, intensity, cellGlowColor[key] ?? _C.arrow);
    });

    // Placed pieces, scaled by their pop-in animation.
    placed.forEach((key, piece) {
      final p = placeAnim[key];
      final scale = p == null ? 1.0 : popScale(p);
      final border = 2.5 + (p == null ? 0.0 : placeBorderBoost(p));
      _paintPiece(canvas, geo, key, piece.tool, piece.direction, scale, border);
    });

    // Pieces shrinking away.
    for (final f in removing) {
      _paintPiece(
          canvas, geo, f.key, f.tool, f.direction, shrinkScale(f.progress), 2.5);
    }

    // Fixed (forced) arrows — a "pinned" look so they read as immovable.
    forced.forEach((key, piece) {
      _paintForced(canvas, geo, key, piece.direction!);
    });

    if (previewKey != null && previewTool != null) {
      _paintPreview(canvas, geo, previewKey!, previewTool!);
    }

    if (winProgress > 0) _paintWin(canvas, geo, winProgress);
  }

  /// On-grid win celebration: a golden fuse lighting the trail from exit back
  /// to start, an expanding bloom at the exit, and a burst of sparkles.
  void _paintWin(Canvas canvas, GridGeometry geo, double p) {
    const gold = AppColors.star;
    final cell = geo.cell;
    final exitCenter = geo.center(level.exit.r, level.exit.c);

    // 1. Golden fuse along the trail, lit from the exit backward to the start.
    if (trail.isNotEmpty) {
      final fuse = (p / 0.6).clamp(0.0, 1.0);
      final lit = (fuse * trail.length).ceil();
      for (var i = 0; i < trail.length; i++) {
        final fromEnd = trail.length - 1 - i; // 0 at the exit
        if (fromEnd >= lit) continue;
        final key = trail[i];
        final center = geo.center(key ~/ geo.n, key % geo.n);
        final isFront = fuse < 1.0 && fromEnd == lit - 1;
        final a = isFront ? 1.0 : 0.7;
        final rad = isFront ? cell * 0.20 : cell * 0.13;
        canvas.drawCircle(
          center,
          rad * 1.8,
          Paint()
            ..color = gold.withValues(alpha: 0.5 * a)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
        );
        canvas.drawCircle(center, rad, Paint()..color = gold.withValues(alpha: a));
      }
    }

    // 2. Exit bloom — expands and fades over the whole celebration.
    final bloom = Curves.easeOut.transform(p.clamp(0.0, 1.0));
    for (var ring = 0; ring < 2; ring++) {
      final t = (bloom - ring * 0.15).clamp(0.0, 1.0);
      if (t <= 0) continue;
      canvas.drawCircle(
        exitCenter,
        cell * (0.35 + 2.4 * t),
        Paint()
          ..color = gold.withValues(alpha: (1 - t) * 0.40)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
      );
    }

    // 3. Sparkle burst from the exit.
    const count = 12;
    final life = (1 - p).clamp(0.0, 1.0);
    if (life > 0) {
      for (var k = 0; k < count; k++) {
        final ang = (k / count) * 2 * math.pi + k * 0.6;
        final speed = 1.0 + (k % 3) * 0.3;
        final dist = cell * (0.25 + 2.3 * p * speed);
        final pos = exitCenter + Offset(math.cos(ang), math.sin(ang)) * dist;
        _drawSparkle(canvas, pos, cell * 0.07 * (0.5 + life),
            gold.withValues(alpha: 0.9 * life));
      }
    }
  }

  void _drawSparkle(Canvas canvas, Offset center, double r, Color color) {
    final path = Path();
    for (var i = 0; i < 8; i++) {
      final ang = i * math.pi / 4;
      final radius = i.isEven ? r : r * 0.4;
      final pt = center + Offset(math.cos(ang), math.sin(ang)) * radius;
      if (i == 0) {
        path.moveTo(pt.dx, pt.dy);
      } else {
        path.lineTo(pt.dx, pt.dy);
      }
    }
    path.close();
    canvas.drawPath(path, Paint()..color = color);
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

    // Neighbor ripple: briefly scale the cell around its center.
    final pulse = cellPulse[r * geo.n + c];
    if (pulse != null) {
      canvas.save();
      canvas.translate(center.dx, center.dy);
      canvas.scale(pulseScale(pulse));
      canvas.translate(-center.dx, -center.dy);
    }

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

    if (pulse != null) canvas.restore();
  }

  void _paintPiece(Canvas canvas, GridGeometry geo, int key, ToolType tool,
      Direction? dir, double scale, double borderWidth) {
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
        ..strokeWidth = borderWidth
        ..color = color,
    );
    _drawGlyph(canvas, center, glyph, color, geo.cell * 0.42);
    canvas.restore();
  }

  /// A fixed arrow: light blue fill, dark "pinned" ink border, blue glyph.
  void _paintForced(Canvas canvas, GridGeometry geo, int key, Direction dir) {
    final r = key ~/ geo.n;
    final c = key % geo.n;
    final center = geo.center(r, c);
    final rrect = _cellRRect(geo, center);
    canvas.drawRRect(rrect, Paint()..color = _C.arrowFill);
    canvas.drawRRect(
      rrect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..color = AppColors.ink,
    );
    _drawGlyph(canvas, center, dir.glyph, _C.arrow, geo.cell * 0.42);
  }

  void _paintGlow(
      Canvas canvas, GridGeometry geo, int key, double intensity, Color color) {
    final i = intensity.clamp(0.0, 1.0);
    final r = key ~/ geo.n;
    final c = key % geo.n;
    final rrect = _cellRRect(geo, geo.center(r, c));
    // Brighter, more visible flash.
    canvas.drawRRect(rrect, Paint()..color = color.withValues(alpha: 0.30 * i));
    canvas.drawRRect(
      rrect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3 + 3 * i
        ..color = color.withValues(alpha: 0.92 * i)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, 2 + 4 * i),
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

  /// Bold pulsing arrow just outside the start cell, plus a few fading lead
  /// dots, so the dot's initial direction is unmistakable.
  void _paintStartHint(Canvas canvas, GridGeometry geo) {
    final s = level.start;
    final center = geo.center(s.r, s.c);
    final (dr, dc) = s.dir.delta;
    final dir = Offset(dc.toDouble(), dr.toDouble());
    final perp = Offset(-dir.dy, dir.dx);
    final cell = geo.cell;
    // Very gentle opacity breathe only (no scale pulse).
    final breathe = 0.85 + 0.15 * (0.5 + 0.5 * math.sin(glowTick * 2 * math.pi));

    // Lead dots tracing the initial path — small and faint.
    for (var k = 1; k <= 3; k++) {
      final nr = s.r + dr * k;
      final nc = s.c + dc * k;
      if (nr < 0 || nr >= geo.n || nc < 0 || nc >= geo.n) break;
      final p = geo.center(nr, nc);
      final fade = 1 - (k - 1) / 3.0; // 1 → .67 → .33
      canvas.drawCircle(
        p,
        cell * 0.07 * fade,
        Paint()..color = AppColors.accent.withValues(alpha: 0.22 * fade * breathe),
      );
    }

    // Small, soft arrowhead on the leading edge — a hint, not a focal point.
    // Gentle breathing scale 1.0 → 1.15 → 1.0 over the (~1.4s) glow cycle.
    final scale = 1.0 + 0.075 * (1 - math.cos(glowTick * 2 * math.pi));
    final anchor = center + dir * (cell * 0.5 + cell * 0.04);
    final tip = anchor + dir * (cell * 0.19 * scale);
    final b1 = anchor + perp * (cell * 0.15 * scale);
    final b2 = anchor - perp * (cell * 0.15 * scale);
    final head = Path()
      ..moveTo(tip.dx, tip.dy)
      ..lineTo(b1.dx, b1.dy)
      ..lineTo(b2.dx, b2.dy)
      ..close();
    canvas.drawPath(
      head,
      Paint()..color = AppColors.accent.withValues(alpha: 0.50 * breathe),
    );
  }

  /// Translucent ghost of the tool snapped to the hovered cell, gently
  /// "breathing" (scaling) to invite the drop.
  void _paintPreview(Canvas canvas, GridGeometry geo, int key, ToolType tool) {
    final r = key ~/ geo.n;
    final c = key % geo.n;
    final center = geo.center(r, c);
    final rrect = _cellRRect(geo, center);
    final breathe = 1 + 0.07 * (0.5 + 0.5 * math.sin(glowTick * 2 * math.pi));

    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.scale(breathe);
    canvas.translate(-center.dx, -center.dy);

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
    canvas.restore();
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
      old.winProgress != winProgress ||
      old.previewKey != previewKey ||
      old.previewTool != previewTool;
}
