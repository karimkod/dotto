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
  static const shield = Color(0xFF38BDF8);
  static const shieldFill = Color(0xFFE0F4FE);
}

/// Cyan used for the shield bubble and the shielded-dot aura.
const Color kShieldColor = _C.shield;

/// Solid accent color used when a tool's cell glows.
Color toolGlowColor(ToolType tool) {
  switch (tool.placedType) {
    case PlacedType.arrow:
      return _C.arrow;
    case PlacedType.pause:
      return _C.pause;
    case PlacedType.teleporter:
      return _C.tele;
    case PlacedType.shield:
      return _C.shield;
  }
}

/// Draws the shield "bubble" icon centered at [center] with the given [radius].
/// A glowing cyan ring with a translucent fill and a soft top highlight — used
/// on the board, in the toolbar tile and in the drag ghost so it reads the same
/// everywhere.
void paintShieldIcon(Canvas canvas, Offset center, double radius,
    {Color color = _C.shield, double opacity = 1.0}) {
  // Soft outer glow.
  canvas.drawCircle(
    center,
    radius,
    Paint()
      ..color = color.withValues(alpha: 0.25 * opacity)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
  );
  // Translucent bubble fill.
  canvas.drawCircle(
    center,
    radius,
    Paint()..color = color.withValues(alpha: 0.18 * opacity),
  );
  // Bright bubble rim.
  canvas.drawCircle(
    center,
    radius,
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = radius * 0.22
      ..color = color.withValues(alpha: opacity),
  );
  // Crescent highlight (top-left) for a glassy look.
  final hl = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = radius * 0.14
    ..strokeCap = StrokeCap.round
    ..color = Colors.white.withValues(alpha: 0.85 * opacity);
  final arcRect = Rect.fromCircle(center: center, radius: radius * 0.6);
  canvas.drawArc(arcRect, math.pi * 1.05, math.pi * 0.6, false, hl);
}

/// A standalone shield bubble for widget contexts (toolbar tile, drag ghost).
class ShieldGlyph extends StatelessWidget {
  const ShieldGlyph({super.key, required this.size, this.color = _C.shield});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _ShieldGlyphPainter(color)),
    );
  }
}

class _ShieldGlyphPainter extends CustomPainter {
  _ShieldGlyphPainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    paintShieldIcon(
        canvas, size.center(Offset.zero), size.width * 0.42, color: color);
  }

  @override
  bool shouldRepaint(covariant _ShieldGlyphPainter old) => old.color != color;
}

/// A spiky sea-mine destroyer icon, drawn centered in a cell of side [cell].
/// [tick] (0..1, looping) drives a subtle size pulse.
void paintMineIcon(Canvas canvas, Offset center, double cell, double tick) {
  final pulse = 1 + 0.06 * math.sin(tick * 2 * math.pi); // subtle breathing
  final body = cell * 0.19 * pulse;
  final spike = cell * 0.11 * pulse;
  const dark = Color(0xFF2D2D2D);

  // Eight spikes radiating from the body.
  final spikePaint = Paint()
    ..color = dark
    ..strokeWidth = cell * 0.055
    ..strokeCap = StrokeCap.round;
  for (var i = 0; i < 8; i++) {
    final a = i / 8 * 2 * math.pi;
    final dir = Offset(math.cos(a), math.sin(a));
    canvas.drawLine(
        center + dir * (body * 0.85), center + dir * (body + spike), spikePaint);
  }
  // Body.
  canvas.drawCircle(center, body, Paint()..color = dark);
  // Specular highlight (top-left) so it reads as a metal sphere.
  canvas.drawCircle(
    center - Offset(body * 0.32, body * 0.32),
    body * 0.30,
    Paint()..color = Colors.white.withValues(alpha: 0.65),
  );
}

/// One explosion in progress: a cell key, a [t] (0→1 over ~0.5s) advanced by
/// the host, a fixed set of flying fragments and a [tint] for its flash/ring
/// (warm for a destroyer, gray for a shattering wall).
class Explosion {
  Explosion(this.cell, this.frags, {this.tint = const Color(0xFFFF8A65)});
  final int cell;
  final List<Frag> frags;
  final Color tint;
  double t = 0;
}

/// A single explosion fragment, described by a launch [angle], [speed] (in cell
/// widths), [color] and relative [sizeMul].
class Frag {
  const Frag(this.angle, this.speed, this.color, this.sizeMul);
  final double angle;
  final double speed;
  final Color color;
  final double sizeMul;
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
      case PlacedType.shield:
        fill = _C.shieldFill;
        color = _C.shield;
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
          child: tool.placedType == PlacedType.shield
              ? ShieldGlyph(size: size * 0.7, color: color)
              : Text(
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
    required this.explosions,
    required this.destroyedCells,
    required this.glowTick,
    required this.showStartHint,
    required this.winProgress,
    this.previewKey,
    this.previewTool,
    this.movers = const [],
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

  /// Destroyer explosions currently animating (drawn above the cells).
  final List<Explosion> explosions;

  /// Destroyer cells that have been blown up (by a shielded dot) — drawn as
  /// cleared/empty so the mine doesn't reappear after the blast.
  final Set<int> destroyedCells;

  /// Continuously-changing value so the painter repaints every frame while
  /// effects are running.
  final double glowTick;

  /// Whether to draw the pulsing start-direction indicator (planning phase).
  final bool showStartHint;

  /// 0 = none; 0→1 drives the win ripple wave spreading out from the exit.
  final double winProgress;

  final int? previewKey;
  final ToolType? previewTool;

  /// Static preview of moving destroyers (designer only). The live game draws
  /// these as gliding overlay widgets, so it passes an empty list.
  final List<MovingDestroyer> movers;

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

    if (winProgress > 0) _paintWinWave(canvas, geo, winProgress);

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

    // Explosions on top of everything (the dot overlay is hidden while one of
    // these plays for a fatal hit).
    for (final e in explosions) {
      _paintExplosion(canvas, geo, e);
    }

    // Moving destroyers (designer preview): a mine with a patrol-axis hint.
    for (final m in movers) {
      _paintMover(canvas, geo, m);
    }

    // The start-direction indicator renders last so it is never hidden behind
    // an adjacent forced arrow or placed piece.
    if (showStartHint) _paintStartHint(canvas, geo);
  }

  /// A moving destroyer as it appears in the editor: a red danger halo, the
  /// mine icon, and a double-headed arrow showing the patrol axis.
  void _paintMover(Canvas canvas, GridGeometry geo, MovingDestroyer m) {
    final center = geo.center(m.r, m.c);
    final cell = geo.cell;
    canvas.drawCircle(
      center,
      cell * 0.36,
      Paint()
        ..color = const Color(0xFFE53935).withValues(alpha: 0.20)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
    );
    paintMineIcon(canvas, center, cell, glowTick);
    // Patrol indicator: the axis line, with a single bold arrowhead on the end
    // the mine STARTS moving toward (dir>0 → right/down, dir<0 → left/up).
    final stroke = Paint()
      ..color = const Color(0xFFE53935)
      ..strokeWidth = cell * 0.05
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final axisVec = m.horizontal ? const Offset(1, 0) : const Offset(0, 1);
    final perp = m.horizontal ? const Offset(0, 1) : const Offset(1, 0);
    final len = cell * 0.40;
    canvas.drawLine(center - axisVec * len, center + axisVec * len, stroke);

    // Start-direction arrowhead (bigger, so it reads at a glance).
    final startVec = axisVec * m.dir.toDouble();
    final tip = center + startVec * len;
    final head = cell * 0.13;
    final back = startVec * head;
    canvas.drawLine(tip, tip - back + perp * head, stroke);
    canvas.drawLine(tip, tip - back - perp * head, stroke);
  }

  /// A destroyer blowing up: a white-hot flash, an expanding shock ring and a
  /// burst of red/orange fragments that fly out, decelerate, fall and fade.
  void _paintExplosion(Canvas canvas, GridGeometry geo, Explosion e) {
    final r = e.cell ~/ geo.n;
    final c = e.cell % geo.n;
    final center = geo.center(r, c);
    final cell = geo.cell;
    final t = e.t.clamp(0.0, 1.0);

    // 1) White-hot core flash, fading over the first ~35%.
    final flashT = (t / 0.35).clamp(0.0, 1.0);
    if (flashT < 1) {
      final fr = cell * (0.32 + 0.55 * flashT);
      canvas.drawCircle(
        center,
        fr,
        Paint()
          ..color = Color.lerp(Colors.white, e.tint, flashT)!
              .withValues(alpha: (1 - flashT) * 0.9)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
      );
    }

    // 2) Expanding shock ring.
    final ringR = cell * (0.18 + 0.85 * t);
    canvas.drawCircle(
      center,
      ringR,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = (1 - t) * 5 + 1
        ..color = e.tint.withValues(alpha: (1 - t) * 0.8),
    );

    // 3) Fragments: decelerate (easeOut) outward, with a little gravity.
    final out = 1 - (1 - t) * (1 - t);
    for (final f in e.frags) {
      final dist = f.speed * cell * out;
      final px = center.dx + math.cos(f.angle) * dist;
      final py = center.dy + math.sin(f.angle) * dist + cell * 0.4 * t * t;
      final sz = cell * 0.09 * f.sizeMul * (1 - t);
      if (sz <= 0) continue;
      canvas.drawCircle(
        Offset(px, py),
        sz,
        Paint()..color = f.color.withValues(alpha: (1 - t).clamp(0.0, 1.0)),
      );
    }
  }

  /// A gold ripple that expands outward from the exit cell, lighting cells as
  /// the wave front passes over them. The grid itself stays put.
  void _paintWinWave(Canvas canvas, GridGeometry geo, double p) {
    const gold = AppColors.star;
    final n = geo.n;
    final ex = level.exit.c.toDouble();
    final ey = level.exit.r.toDouble();
    final maxD = n * 1.5;
    const width = 1.4; // wave-front thickness, in cells
    // The wave finishes spreading by ~55% of the celebration.
    final waveR = (p / 0.55).clamp(0.0, 1.0) * (maxD + 1.0);

    for (var r = 0; r < n; r++) {
      for (var c = 0; c < n; c++) {
        final d = math.sqrt(
            (c - ex) * (c - ex) + (r - ey) * (r - ey));
        final delta = waveR - d;
        if (delta < 0 || delta > width) continue;
        final intensity = math.sin(math.pi * (delta / width));
        if (intensity <= 0) continue;
        final rrect = _cellRRect(geo, geo.center(r, c));
        canvas.drawRRect(
            rrect, Paint()..color = gold.withValues(alpha: 0.32 * intensity));
        canvas.drawRRect(
          rrect,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2.5 + 2 * intensity
            ..color = gold.withValues(alpha: 0.8 * intensity)
            ..maskFilter = MaskFilter.blur(BlurStyle.normal, 2 + 3 * intensity),
        );
      }
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
    var base = level.baseTypeAt(r, c);
    // A destroyer or wall cleared by a chain explosion renders as empty.
    if (destroyedCells.contains(r * geo.n + c)) {
      base = CellType.empty;
    }

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
    bool mine = false;

    switch (base) {
      case CellType.start:
        // The start cell is a permanent redirector, so it shows its direction.
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
        mine = true; // a spiky mine icon instead of the old "✕"
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
    if (mine) {
      paintMineIcon(canvas, center, geo.cell, glowTick);
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
    if (tool.placedType == PlacedType.shield) {
      paintShieldIcon(canvas, center, geo.cell * 0.28, color: color);
    } else {
      _drawGlyph(canvas, center, glyph, color, geo.cell * 0.42);
    }
    canvas.restore();
  }

  /// A fixed arrow: solid blue-gray fill (wall family) with a white glyph, so
  /// it reads as part of the level rather than a piece the player placed.
  /// A fixed arrow shares the wall's colour, so the MARK has to carry the whole
  /// difference: a solid filled arrow and a heavier border, instead of the thin
  /// text chevron that used to read as "wall with something on it" at a glance.
  void _paintForced(Canvas canvas, GridGeometry geo, int key, Direction dir) {
    final r = key ~/ geo.n;
    final c = key % geo.n;
    final center = geo.center(r, c);
    final rrect = _cellRRect(geo, center);
    canvas.drawRRect(rrect, Paint()..color = _C.wall);
    canvas.drawRRect(
      rrect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4 // heavier than a wall's 2px edge
        ..color = const Color(0xFF5C6B73),
    );
    _drawSolidArrow(canvas, center, dir, geo.cell);
  }

  /// A chunky filled arrow — shaft plus a broad head — pointing [dir]. Drawn as
  /// geometry rather than a font glyph so its weight does not depend on the
  /// platform's font rendering.
  void _drawSolidArrow(
      Canvas canvas, Offset center, Direction dir, double cell) {
    final (dr, dc) = dir.delta;
    // Canvas x comes from the column delta, y from the row delta.
    final v = Offset(dc.toDouble(), dr.toDouble());
    final perp = Offset(-v.dy, v.dx);

    final tip = center + v * (cell * 0.34);
    final headBase = center + v * (cell * 0.04);
    final tail = center - v * (cell * 0.30);
    final halfWidth = cell * 0.21;
    final white = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;

    canvas.drawLine(
      tail,
      headBase,
      Paint()
        ..color = Colors.white
        ..strokeWidth = cell * 0.15
        ..strokeCap = StrokeCap.round,
    );

    final head = Path()
      ..moveTo(tip.dx, tip.dy)
      ..lineTo(headBase.dx + perp.dx * halfWidth,
          headBase.dy + perp.dy * halfWidth)
      ..lineTo(headBase.dx - perp.dx * halfWidth,
          headBase.dy - perp.dy * halfWidth)
      ..close();
    canvas.drawPath(head, white);
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
    if (tool.placedType == PlacedType.shield) {
      paintShieldIcon(canvas, center, geo.cell * 0.28,
          color: color, opacity: 0.85);
    } else {
      _drawGlyph(canvas, center, glyph,
          color.withValues(alpha: 0.85), geo.cell * 0.42);
    }
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
      case PlacedType.shield:
        return (_C.shieldFill, _C.shield, ''); // icon drawn separately
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
