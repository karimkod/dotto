// The Play Store feature graphic (1024×500), drawn by the game itself.
//
// Nothing here is a mock-up: the board is `GameGridPainter`, the ball is
// `GameDot`, the toolkit strip is `GameToolbar`, and the colours all come from
// `AppColors`. The only thing this file adds is a composition — where the board
// sits, and what goes beside it — so the hero image can never drift away from
// what the game actually looks like.
//
// Run:  flutter run -t lib/main_feature_graphic.dart -d chrome
// The screen renders itself, exports a pixel-exact 1024×500 PNG through a
// RepaintBoundary and reports where it landed.

import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/game_state.dart';
import '../models/grid_cell.dart';
import '../models/level_data.dart';
import '../theme/app_theme.dart';
import '../widgets/game_grid.dart';
import '../widgets/game_toolbar.dart';
import 'feature_graphic_saver.dart';

/// Exact output size demanded by the Play Console.
const Size kFeatureGraphicSize = Size(1024, 500);

/// File name of the exported PNG.
const String kFeatureGraphicFile = 'dotto_feature_graphic.png';

/// The board shown in the hero image: a 6×6 with the start bottom-left, the
/// goal top-right and a route already half-built across it — the exact state a
/// player is in a few seconds into a level, which is what the graphic should be
/// selling.
///
/// Hazards sit just off the drawn route (a mine one cell from the path, a wall
/// beside the last leg) so the picture reads as "this is a puzzle" rather than
/// "this is a maze".
const LevelData _heroLevel = LevelData(
  id: 0,
  size: 6,
  title: 'Dotto',
  tip: '',
  start: StartSpec(5, 0, Direction.right),
  exit: Pos(0, 5),
  walls: [Pos(1, 1), Pos(3, 1), Pos(4, 5)],
  destroyers: [Pos(0, 2), Pos(4, 4)],
  forcedArrows: [ForcedArrow(3, 4, Direction.left)],
  toolkit: [
    ToolkitEntry(ToolType.arrowUp, 2),
    ToolkitEntry(ToolType.arrowRight, 1),
    ToolkitEntry(ToolType.shield, 1),
    ToolkitEntry(ToolType.teleporter, 2),
  ],
);

int _key(int r, int c) => r * _heroLevel.size + c;

/// The pieces the player has "already placed", forming the route
/// (5,0) → right → up column 3 → right → up column 5 → goal.
final Map<int, PlacedElement> _heroPlaced = {
  _key(5, 2): const PlacedElement(
      type: PlacedType.shield, tool: ToolType.shield),
  _key(5, 3): const PlacedElement(
      type: PlacedType.arrow,
      tool: ToolType.arrowUp,
      direction: Direction.up),
  _key(2, 3): const PlacedElement(
      type: PlacedType.arrow,
      tool: ToolType.arrowRight,
      direction: Direction.right),
  _key(2, 5): const PlacedElement(
      type: PlacedType.arrow,
      tool: ToolType.arrowUp,
      direction: Direction.up),
};

/// The level's own fixed arrow, in the shape the painter wants it.
final Map<int, PlacedElement> _heroForced = {
  for (final a in _heroLevel.forcedArrows)
    _key(a.r, a.c): PlacedElement(
      type: PlacedType.arrow,
      tool: a.dir.arrowTool,
      direction: a.dir,
    ),
};

/// Frozen phase of every looping animation on the board. Picked rather than
/// left at zero: at a quarter turn the start-direction arrowhead is at the top
/// of its breathe and the mines are at the top of their pulse, so the still
/// catches the board at its liveliest.
const double _kGlowTick = 0.25;

class FeatureGraphicScreen extends StatefulWidget {
  const FeatureGraphicScreen({super.key, this.autoExport = true});

  /// Whether to write the PNG out as soon as the first frame has settled.
  final bool autoExport;

  @override
  State<FeatureGraphicScreen> createState() => _FeatureGraphicScreenState();
}

class _FeatureGraphicScreenState extends State<FeatureGraphicScreen> {
  final GlobalKey _boundaryKey = GlobalKey();
  String _status = 'rendering…';

  @override
  void initState() {
    super.initState();
    if (widget.autoExport) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _export());
    }
  }

  /// Renders the boundary at exactly 1024×500 device pixels and writes it out.
  ///
  /// `pixelRatio: 1.0` against a 1024×500 logical box is what makes the export
  /// exact — a plain device screenshot would come back at whatever density the
  /// emulator happens to run at.
  Future<void> _export() async {
    try {
      // Two separate font waits, and both matter.
      //
      // `pendingFonts` covers the Google Fonts the layout asks for by name —
      // the Poppins wordmark and the Nunito body. It does NOT cover the
      // board's symbol glyphs (the goal's ⚑, the start cell's chevron): on web
      // those codepoints are missing from the bundled face, so the engine only
      // discovers it needs a fallback font once it has tried to lay them out,
      // and then fetches one asynchronously. Capture too early and the goal
      // exports as a tofu box. Hence the settle delay on top.
      await GoogleFonts.pendingFonts();
      await Future<void>.delayed(const Duration(seconds: 4));
      if (!mounted) return;

      final boundary = _boundaryKey.currentContext!.findRenderObject()
          as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 1.0);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      if (bytes == null) throw StateError('encode returned null');

      final where = await saveFeatureGraphic(
          bytes.buffer.asUint8List(), kFeatureGraphicFile);
      debugPrint('FEATURE_GRAPHIC_OK ${image.width}x${image.height} -> $where');
      if (mounted) {
        setState(() => _status = '${image.width}×${image.height} → $where');
      }
    } catch (e, st) {
      debugPrint('FEATURE_GRAPHIC_FAIL $e\n$st');
      if (mounted) setState(() => _status = 'export failed: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1B1B1B),
      body: Column(
        children: [
          Expanded(
            child: Center(
              // Scaled to fit the device, but the boundary inside keeps its
              // true 1024×500 logical size — which is what gets exported.
              child: FittedBox(
                child: RepaintBoundary(
                  key: _boundaryKey,
                  child: MediaQuery(
                    // Pins the render against whatever accessibility text scale
                    // the device is set to, so the export is reproducible.
                    data: MediaQuery.of(context).copyWith(
                      textScaler: TextScaler.noScaling,
                    ),
                    child: const FeatureGraphic(),
                  ),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(10),
            child: Text(
              _status,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70, fontSize: 11),
            ),
          ),
        ],
      ),
    );
  }
}

/// The graphic itself: exactly [kFeatureGraphicSize], board on the left,
/// wordmark and toolkit on the right.
class FeatureGraphic extends StatelessWidget {
  const FeatureGraphic({super.key});

  static const double _boardSide = 424;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: kFeatureGraphicSize.width,
      height: kFeatureGraphicSize.height,
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: Material(
          color: AppColors.background,
          child: Stack(
            children: [
              // The same faint graph paper the menu and the game screen sit on.
              const Positioned.fill(
                child: CustomPaint(painter: _BgGridPainter()),
              ),
              // Warmth under the board and a coral breath behind the wordmark,
              // so the cream field is not perfectly flat across a metre of
              // store banner.
              const Positioned.fill(child: CustomPaint(painter: _GlowPainter())),
              Positioned(
                left: 52,
                top: (kFeatureGraphicSize.height - _boardSide) / 2,
                child: _board(),
              ),
              Positioned(
                left: 540,
                right: 56,
                top: 0,
                bottom: 0,
                child: const _Pitch(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// The real board painter, lifted straight out of the game, with the ball
  /// sitting on its start cell exactly as it does before you press Play.
  Widget _board() {
    final geo = GridGeometry(_boardSide, _heroLevel.size);
    final dot = geo.cell * 0.46;
    final start = geo.center(_heroLevel.start.r, _heroLevel.start.c);

    return Container(
      width: _boardSide,
      height: _boardSide,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: AppColors.ink.withValues(alpha: 0.16),
            blurRadius: 34,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: Stack(
        children: [
          CustomPaint(
            size: const Size.square(_boardSide),
            painter: GameGridPainter(
              level: _heroLevel,
              placed: _heroPlaced,
              forced: _heroForced,
              rotations: const {},
              trail: const [],
              revision: 0,
              placeAnim: const {},
              removing: const [],
              cellGlow: const {},
              cellGlowColor: const {},
              cellPulse: const {},
              explosions: const [],
              destroyedCells: const {},
              glowTick: _kGlowTick,
              // The planning phase: the route is laid out, the ball has not
              // left yet, and the start cell is still advertising its heading.
              showStartHint: true,
              winProgress: 0,
            ),
          ),
          Positioned(
            left: start.dx - dot / 2,
            top: start.dy - dot / 2,
            child: GameDot(size: dot, paused: false, glow: 0.85),
          ),
        ],
      ),
    );
  }
}

/// Everything to the right of the board: wordmark, promise, pieces.
class _Pitch extends StatelessWidget {
  const _Pitch();

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // The menu's wordmark style, just at hero size.
        Text('Dotto', style: AppTheme.title.copyWith(fontSize: 106, height: 1)),
        const SizedBox(height: 16),
        Container(
          width: 132,
          height: 10,
          decoration: BoxDecoration(
            gradient: AppColors.playGradient,
            borderRadius: BorderRadius.circular(6),
          ),
        ),
        const SizedBox(height: 28),
        // Deliberately evergreen: no level counts, no world counts, nothing
        // that a future release could make untrue. A store banner outlives the
        // build it was cut from.
        Text(
          'Place arrows.\nGuide the ball.\nSolve the puzzle.',
          style: GoogleFonts.nunito(
            fontSize: 33,
            fontWeight: FontWeight.w800,
            color: AppColors.text,
            height: 1.28,
          ),
        ),
        const SizedBox(height: 34),
        // The actual toolkit strip from the game, with selection wired to
        // nothing — a still of the row the player picks pieces from.
        GameToolbar(
          tools: const [
            ToolType.arrowUp,
            ToolType.arrowRight,
            ToolType.shield,
            ToolType.teleporter,
          ],
          counts: const {
            ToolType.arrowUp: 2,
            ToolType.arrowRight: 1,
            ToolType.shield: 1,
            ToolType.teleporter: 2,
          },
          selected: ToolType.shield,
          onSelect: (_) {},
          enabled: true,
          tileKeys: const {},
        ),
      ],
    );
  }
}

/// Faint background grid — the same 28px pitch the menu and game screens use.
class _BgGridPainter extends CustomPainter {
  const _BgGridPainter();

  static const _cell = 28.0;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppColors.grid
      ..strokeWidth = 1;
    for (var x = 0.0; x <= size.width; x += _cell) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (var y = 0.0; y <= size.height; y += _cell) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _BgGridPainter oldDelegate) => false;
}

/// Two very soft washes of the game's own accents — warm under the board,
/// coral behind the wordmark. Barely there; they exist so the cream reads as
/// lit rather than as blank paper at banner size.
class _GlowPainter extends CustomPainter {
  const _GlowPainter();

  @override
  void paint(Canvas canvas, Size size) {
    void wash(Offset c, double r, Color color, double alpha) {
      canvas.drawCircle(
        c,
        r,
        Paint()
          ..shader = ui.Gradient.radial(c, r, [
            color.withValues(alpha: alpha),
            color.withValues(alpha: 0),
          ]),
      );
    }

    wash(Offset(size.width * 0.24, size.height * 0.52), 330,
        AppColors.accent, 0.16);
    wash(Offset(size.width * 0.78, size.height * 0.24), 300,
        AppColors.coral, 0.11);
  }

  @override
  bool shouldRepaint(covariant _GlowPainter oldDelegate) => false;
}
