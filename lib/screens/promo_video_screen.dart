// The Play Store promo video, played by the game itself.
//
// Nothing here is a mock-up. The board is `GameGridPainter`, the ball is
// `GameDot`, the mines come from `paintMineIcon`, the blasts are `Explosion` /
// `Frag`, and the colours are `AppColors` — the same code the shipped game
// draws with. This file only adds a SCRIPT: which small levels to show, which
// pieces land when, and where the ball goes.
//
// Run:  flutter run -t lib/main_promo.dart -d chrome
// Then size the window 16:9 and screen-record it. The whole thing is authored
// against a fixed 1920×1080 canvas and scaled to fit, so the composition is the
// same whatever the recording window happens to be.
//
// The timeline is a PURE FUNCTION OF TIME. Every frame recomputes the board
// from one clock, so a dropped frame during recording costs a frame and never
// desynchronises the run. It loops forever, so the recorder can start anywhere
// and trim later.

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:google_fonts/google_fonts.dart';

import '../engine/simulator.dart' show buildForcedPieces;
import '../models/game_state.dart';
import '../models/grid_cell.dart';
import '../models/level_data.dart';
import '../theme/app_theme.dart';
import 'promo_store_badges.dart';
import '../widgets/game_grid.dart';

/// The canvas everything is authored against, scaled to fit the window. 9:16 —
/// the shape a store promo is actually watched in.
const Size kPromoSize = Size(1080, 1920);

// ---------------------------------------------------------------------------
// Script model
// ---------------------------------------------------------------------------

/// What happens as the ball ARRIVES at a hop.
enum _Ev {
  /// Picks up a shield here: the piece is spent and the aura comes on.
  shield,

  /// Runs into a mine unshielded. The blast kills the ball; the run ends.
  boomFatal,

  /// Runs into a mine WITH a shield. The mine goes up, the ball keeps going.
  boomSurvive,
}

/// One cell of the ball's route. [warp] means it got here through a portal
/// rather than by gliding, and [hold] is extra dwell time before the next step
/// (used to let a blast land).
class _Hop {
  const _Hop(this.r, this.c, {this.warp = false, this.event, this.hold = 0});
  final int r;
  final int c;
  final bool warp;
  final _Ev? event;
  final double hold;
}

/// A mine gliding back and forth along [row], between columns [from] and [to].
/// Pure decoration: it never meets the ball, it just makes the board feel alive.
class _Patrol {
  const _Patrol(this.row, this.from, this.to, this.period);
  final int row;
  final int from;
  final int to;

  /// Seconds for one there-and-back sweep.
  final double period;

  /// Column at time [t], ping-ponging between the two ends.
  double columnAt(double t) {
    final phase = (t % period) / period; // 0 → 1
    final tri = phase < 0.5 ? phase * 2 : (1 - phase) * 2; // 0 → 1 → 0
    return from + (to - from) * tri;
  }
}

/// A piece dropped onto the board by the script, in placement order.
class _Drop {
  const _Drop(this.r, this.c, this.piece);
  final int r;
  final int c;
  final PlacedElement piece;
}

/// Base class so the timeline can hold both kinds of scene in one list.
abstract class _Scene {
  const _Scene();
  double get duration;
}

/// A full-screen text beat between levels.
class _CardScene extends _Scene {
  const _CardScene({
    required this.duration,
    required this.line,
    this.wordmark = false,
    this.byline,
    this.sub,
    this.badges = false,
  });

  @override
  final double duration;

  /// The big line. When [wordmark] it is set in the Dotto title face.
  final String line;
  final bool wordmark;

  /// Small attribution set directly under the wordmark, above the rule, so it
  /// reads as part of the name rather than as another piece of copy.
  final String? byline;

  /// Optional smaller line under it.
  final String? sub;

  /// Show the two official store badges instead of a [sub] line.
  final bool badges;
}

/// One playable level: the board appears, pieces land, the ball runs, the
/// outcome plays out.
class _LevelScene extends _Scene {
  _LevelScene({
    required this.label,
    required this.blurb,
    required this.level,
    required this.drops,
    required this.path,
    required this.beat,
    this.callout,
    this.patrols = const [],
    this.tail = 1.5,
  });

  /// Short name of the mechanic, shown beside the board.
  final String label;

  /// One line under it describing the mechanic.
  final String blurb;

  /// Optional feature badge under the board. Kept to claims that are true of
  /// the shipped build and that grow rather than shrink, so the video does not
  /// go stale the next time content lands.
  final String? callout;

  final LevelData level;
  final List<_Drop> drops;
  final List<_Hop> path;

  /// Seconds the ball spends crossing one cell.
  final double beat;

  final List<_Patrol> patrols;

  /// Seconds held after the last hop, for the win wave or the final blast.
  final double tail;

  /// The level's own fixed pieces, built the way the game builds them.
  late final Map<int, PlacedElement> forced = buildForcedPieces(level);

  int keyOf(int r, int c) => r * level.size + c;

  /// The scripted piece for a cell, whether or not it is still on the board.
  late final Map<int, PlacedElement> _byCell = {
    for (final d in drops) keyOf(d.r, d.c): d.piece,
  };

  PlacedElement? pieceAt(int key) => _byCell[key];

  /// When each piece lands.
  double dropTime(int i) => _kDropStart + i * _kDropGap;

  /// When the ball leaves the start cell.
  late final double runStart =
      _kDropStart + drops.length * _kDropGap + _kSettle;

  /// Arrival time of every hop, including any dwell an earlier hop asked for.
  late final List<double> hopTimes = () {
    final out = <double>[runStart];
    for (var i = 1; i < path.length; i++) {
      out.add(out[i - 1] + beat + path[i - 1].hold);
    }
    return out;
  }();

  /// Explosion debris, generated once so it does not reshuffle every frame.
  late final Map<int, List<Frag>> frags = {
    for (var i = 0; i < path.length; i++)
      if (path[i].event == _Ev.boomFatal || path[i].event == _Ev.boomSurvive)
        i: _makeFrags(level.id * 100 + i),
  };

  /// True when the run ends in a blast rather than at the goal.
  bool get fatal => path.last.event == _Ev.boomFatal;

  @override
  double get duration => hopTimes.last + tail;
}

/// Board fade/scale in, and how long before it fades out again.
const double _kBoardIn = 0.45;
const double _kBoardOut = 0.40;

/// Piece placement: when the first one lands, the gap between them, and the
/// beat of stillness before the ball goes.
const double _kDropStart = 0.55;
const double _kDropGap = 0.40;
const double _kSettle = 0.35;

/// How long a piece's pop-in and a collected shield's shrink-out run for.
const double _kPop = 0.60;
const double _kShrink = 0.40;

/// A destroyer blast, matching the game's ~0.5s explosion.
const double _kBoom = 0.50;

/// How long a cell stays lit after the ball passes through a piece.
const double _kCellFlash = 0.40;

/// The win ripple's full spread.
const double _kWinWave = 1.60;

List<Frag> _makeFrags(int seed) {
  final rng = math.Random(seed);
  const colors = [
    Color(0xFFEF5350), // red
    Color(0xFFFF8A65), // orange
    Color(0xFFFFD54F), // yellow
  ];
  return [
    for (var i = 0; i < 14; i++)
      Frag(
        i / 14 * 2 * math.pi + rng.nextDouble() * 0.5,
        0.6 + rng.nextDouble() * 1.0,
        colors[rng.nextInt(colors.length)],
        0.7 + rng.nextDouble() * 0.8,
      ),
  ];
}

PlacedElement _arrow(Direction d) =>
    PlacedElement(type: PlacedType.arrow, tool: d.arrowTool, direction: d);

const PlacedElement _shield =
    PlacedElement(type: PlacedType.shield, tool: ToolType.shield);

// ---------------------------------------------------------------------------
// The four levels
// ---------------------------------------------------------------------------
//
// Written for the camera, not for the level list: small boards, one idea each,
// and a route that reads at a glance from across a room.

/// 1. Arrows. Two pieces, one clean run to the goal. The core loop, nothing else.
final _LevelScene _sceneArrows = _LevelScene(
  label: 'Arrows',
  blurb: 'Place an arrow. The ball turns.',
  // True of the shipped build: level_definitions.dart holds 110. Phrased as a
  // floor so more content can only make it truer.
  callout: 'More than 100 levels',
  beat: 0.28,
  level: const LevelData(
    id: 1,
    size: 5,
    title: 'Arrows',
    tip: '',
    start: StartSpec(4, 0, Direction.right),
    exit: Pos(0, 4),
    walls: [Pos(4, 3), Pos(2, 1)],
    toolkit: [
      ToolkitEntry(ToolType.arrowUp, 1),
      ToolkitEntry(ToolType.arrowRight, 1),
    ],
  ),
  drops: [
    _Drop(4, 2, _arrow(Direction.up)),
    _Drop(0, 2, _arrow(Direction.right)),
  ],
  path: const [
    _Hop(4, 0),
    _Hop(4, 1),
    _Hop(4, 2),
    _Hop(3, 2),
    _Hop(2, 2),
    _Hop(1, 2),
    _Hop(0, 2),
    _Hop(0, 3),
    _Hop(0, 4),
  ],
);

/// 2. Danger. The same shape of plan, one mine in the way. The run just ends.
final _LevelScene _sceneDanger = _LevelScene(
  label: 'Danger',
  blurb: 'A mine ends the run.',
  // Counted off what the shipped levels actually use: arrow, one-shot arrow,
  // pause, portal, shield, wall, mine, patrol mine, rotating arrow.
  callout: '9 puzzle elements',
  beat: 0.30,
  tail: 1.40,
  level: const LevelData(
    id: 2,
    size: 5,
    title: 'Danger',
    tip: '',
    start: StartSpec(4, 0, Direction.right),
    exit: Pos(0, 4),
    walls: [Pos(4, 3)],
    destroyers: [Pos(2, 2)],
    toolkit: [
      ToolkitEntry(ToolType.arrowUp, 1),
      ToolkitEntry(ToolType.arrowRight, 1),
    ],
  ),
  drops: [
    _Drop(4, 2, _arrow(Direction.up)),
    // Placed above the mine, so the plan visibly carries on past the point
    // where the ball never gets to.
    _Drop(1, 2, _arrow(Direction.right)),
  ],
  path: const [
    _Hop(4, 0),
    _Hop(4, 1),
    _Hop(4, 2),
    _Hop(3, 2),
    _Hop(2, 2, event: _Ev.boomFatal),
  ],
);

/// 3. Warp. A fixed portal pair carries the ball clean across the board.
final _LevelScene _sceneWarp = _LevelScene(
  label: 'Warp',
  blurb: 'Portals link two cells.',
  callout: 'Weekly challenges',
  beat: 0.28,
  level: const LevelData(
    id: 3,
    size: 6,
    title: 'Warp',
    tip: '',
    start: StartSpec(5, 0, Direction.right),
    exit: Pos(0, 5),
    walls: [Pos(3, 2), Pos(4, 4)],
    destroyers: [Pos(2, 4)],
    teleporters: [TeleporterPair(Pos(5, 3), Pos(1, 1))],
    toolkit: [ToolkitEntry(ToolType.arrowUp, 1)],
  ),
  drops: [_Drop(1, 5, _arrow(Direction.up))],
  path: const [
    _Hop(5, 0),
    _Hop(5, 1),
    _Hop(5, 2),
    _Hop(5, 3),
    _Hop(1, 1, warp: true),
    _Hop(1, 2),
    _Hop(1, 3),
    _Hop(1, 4),
    _Hop(1, 5),
    _Hop(0, 5),
  ],
);

/// 4. Shield. The advanced beat: collect a bubble, walk straight into a mine,
/// blow it up instead of dying, and carry on to the goal.
final _LevelScene _sceneShield = _LevelScene(
  label: 'Shield',
  blurb: 'A shield clears the way.',
  beat: 0.28,
  tail: 1.30,
  level: const LevelData(
    id: 4,
    size: 6,
    title: 'Shield',
    tip: '',
    start: StartSpec(5, 0, Direction.right),
    exit: Pos(0, 5),
    walls: [Pos(5, 5), Pos(0, 1)],
    destroyers: [Pos(2, 3)],
    toolkit: [
      ToolkitEntry(ToolType.shield, 1),
      ToolkitEntry(ToolType.arrowUp, 1),
      ToolkitEntry(ToolType.arrowRight, 1),
    ],
  ),
  drops: [
    _Drop(5, 2, _shield),
    _Drop(5, 3, _arrow(Direction.up)),
    _Drop(0, 3, _arrow(Direction.right)),
  ],
  patrols: const [_Patrol(3, 0, 2, 2.4)],
  path: const [
    _Hop(5, 0),
    _Hop(5, 1),
    _Hop(5, 2, event: _Ev.shield),
    _Hop(5, 3),
    _Hop(4, 3),
    _Hop(3, 3),
    _Hop(2, 3, event: _Ev.boomSurvive, hold: 0.45),
    _Hop(1, 3),
    _Hop(0, 3),
    _Hop(0, 4),
    _Hop(0, 5),
  ],
);

/// The whole 30-second cut, in order.
final List<_Scene> _kTimeline = [
  const _CardScene(
    // A touch longer than before: the byline adds a line to read.
    duration: 2.9,
    line: 'Dotto',
    wordmark: true,
    byline: 'by Reshaped',
    sub: 'Place arrows. Guide the ball.',
  ),
  _sceneArrows,
  const _CardScene(duration: 1.3, line: 'Think ahead.'),
  _sceneDanger,
  const _CardScene(duration: 1.3, line: 'One wrong move...'),
  _sceneWarp,
  const _CardScene(duration: 1.3, line: 'Find the path.'),
  _sceneShield,
  const _CardScene(
    // Longer than the opening card: the badges are the call to action and the
    // viewer needs a beat to recognise both of them.
    duration: 3.4,
    line: 'Dotto',
    wordmark: true,
    byline: 'by Reshaped',
    badges: true,
  ),
];

/// Total runtime of the cut, in seconds. Also the loop point.
double get kPromoLength => _kTimeline.fold(0.0, (a, s) => a + s.duration);

// ---------------------------------------------------------------------------
// The screen
// ---------------------------------------------------------------------------

class PromoVideoScreen extends StatefulWidget {
  const PromoVideoScreen({super.key, this.frozenAt});

  /// Renders one instant of the timeline and stands still there, instead of
  /// playing. Only for inspecting a frame — the recorded screen leaves it null.
  final double? frozenAt;

  @override
  State<PromoVideoScreen> createState() => _PromoVideoScreenState();
}

class _PromoVideoScreenState extends State<PromoVideoScreen>
    with SingleTickerProviderStateMixin {
  Ticker? _ticker;

  /// Seconds into the timeline while playing. Unused when frozen.
  double _t = 0;

  /// The instant to draw. Read straight off the widget when frozen rather than
  /// copied into state in initState: Flutter reuses a State when the widget
  /// type at a position is unchanged, so a copy would never see a new
  /// `frozenAt` and every frame of a render would come out identical.
  double get _time =>
      widget.frozenAt == null ? _t : widget.frozenAt! % kPromoLength;

  @override
  void initState() {
    super.initState();
    if (widget.frozenAt != null) return;
    _ticker = createTicker((elapsed) {
      final t = elapsed.inMicroseconds / 1e6 % kPromoLength;
      setState(() => _t = t);
    })..start();
  }

  @override
  void dispose() {
    // Stopped before it is disposed: the ticker runs for the life of the
    // screen, and SingleTickerProviderStateMixin asserts against tearing one
    // down while it is still running.
    _ticker
      ?..stop(canceled: true)
      ..dispose();
    super.dispose();
  }

  /// The scene covering [_time], and how far into it we are.
  (_Scene, double) _resolve() {
    final t = _time;
    var acc = 0.0;
    for (final s in _kTimeline) {
      if (t < acc + s.duration) return (s, t - acc);
      acc += s.duration;
    }
    final last = _kTimeline.last;
    return (last, last.duration);
  }

  @override
  Widget build(BuildContext context) {
    final (scene, local) = _resolve();

    // Everything fades at its own edges, so consecutive scenes cross softly
    // rather than cutting.
    final fade = _edgeFade(local, scene.duration,
        inSecs: _kBoardIn, outSecs: _kBoardOut);

    return Scaffold(
      backgroundColor: const Color(0xFF101010),
      body: Center(
        child: FittedBox(
          child: MediaQuery(
            // Pinned against the device's text scale, so a recording made on
            // one machine matches one made on another.
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.noScaling),
            child: SizedBox(
              width: kPromoSize.width,
              height: kPromoSize.height,
              child: Material(
                color: AppColors.background,
                child: Stack(
                  children: [
                    // The same faint graph paper the menu and game sit on.
                    const Positioned.fill(
                      child: CustomPaint(painter: _BgGridPainter()),
                    ),
                    const Positioned.fill(
                      child: CustomPaint(painter: _WashPainter()),
                    ),
                    Positioned.fill(
                      child: Opacity(
                        opacity: fade,
                        child: switch (scene) {
                          _CardScene s => _Card(scene: s, t: local),
                          _LevelScene s => _LevelStage(scene: s, t: local),
                          _ => const SizedBox.shrink(),
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 0 at both edges of a scene, 1 through the middle.
double _edgeFade(double local, double duration,
    {required double inSecs, required double outSecs}) {
  final rise = (local / inSecs).clamp(0.0, 1.0);
  final fall = ((duration - local) / outSecs).clamp(0.0, 1.0);
  return Curves.easeOut.transform(rise) * Curves.easeOut.transform(fall);
}

// ---------------------------------------------------------------------------
// Text beats
// ---------------------------------------------------------------------------

/// A full-screen line. The wordmark cards also carry the play-button gradient
/// bar, so the title beats look like the app's own front door.
class _Card extends StatelessWidget {
  const _Card({required this.scene, required this.t});

  final _CardScene scene;
  final double t;

  @override
  Widget build(BuildContext context) {
    // A small settling rise, so the words arrive rather than appear.
    final rise = Curves.easeOutCubic.transform((t / 0.55).clamp(0.0, 1.0));
    final lift = (1 - rise) * 26;

    return Center(
      child: Padding(
        // Keeps the longest line clear of the edges at 1080 wide.
        padding: const EdgeInsets.symmetric(horizontal: 70),
        child: Transform.translate(
          offset: Offset(0, lift),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                scene.line,
                textAlign: TextAlign.center,
                style: scene.wordmark
                    ? AppTheme.title.copyWith(fontSize: 168, height: 1)
                    : GoogleFonts.nunito(
                        fontSize: 88,
                        fontWeight: FontWeight.w800,
                        color: AppColors.text,
                        height: 1.15,
                      ),
              ),
              if (scene.byline != null) ...[
                const SizedBox(height: 18),
                Text(
                  scene.byline!,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.nunito(
                    fontSize: 36,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textSoft,
                    letterSpacing: 0.6,
                    height: 1,
                  ),
                ),
              ],
              if (scene.wordmark) ...[
                SizedBox(height: scene.byline == null ? 30 : 26),
                Container(
                  width: 214,
                  height: 14,
                  decoration: BoxDecoration(
                    gradient: AppColors.playGradient,
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ],
              if (scene.sub != null) ...[
                SizedBox(height: scene.wordmark ? 36 : 24),
                Text(
                  scene.sub!,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.nunito(
                    fontSize: 46,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textSoft,
                    height: 1.35,
                  ),
                ),
              ],
              if (scene.badges) ...[
                const SizedBox(height: 56),
                // Slightly behind the wordmark, so the eye lands on the name
                // first and the badges arrive as the answer to it.
                Opacity(
                  opacity: Curves.easeOut
                      .transform(((t - 0.35) / 0.6).clamp(0.0, 1.0)),
                  child: const _StoreBadges(),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// The two official store badges, side by side.
///
/// Both are sized from [_button], the height the BUTTON should end up, not the
/// height of the file: Google's asset carries its required clear space inside
/// the image and Apple's does not, so matching image heights would leave the
/// Play button looking a size smaller than it is.
class _StoreBadges extends StatelessWidget {
  const _StoreBadges();

  /// Height of the badge artwork itself, in promo canvas pixels.
  static const double _button = 118;

  @override
  Widget build(BuildContext context) {
    final playH = _button / kPlayButtonFraction;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Image(
          image: kPlayBadge,
          height: playH,
          width: playH * kPlayAspect,
          filterQuality: FilterQuality.high,
        ),
        // Apple asks for clear space around its badge; Google's is baked in,
        // which is why the gap sits off-centre in the source but even on screen.
        const SizedBox(width: 16),
        Image(
          image: kAppStoreBadge,
          height: _button,
          width: _button * kAppStoreAspect,
          filterQuality: FilterQuality.high,
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// A level playing
// ---------------------------------------------------------------------------

/// The mechanic's name and line, with the live board under them. Stacked rather
/// than side by side: in 9:16 the board wants the full width, and a caption
/// above it is the only place a reader's eye is already going.
class _LevelStage extends StatelessWidget {
  const _LevelStage({required this.scene, required this.t});

  final _LevelScene scene;
  final double t;

  static const double _boardSide = 900;

  @override
  Widget build(BuildContext context) {
    // The caption arrives just behind the board.
    final textIn =
        Curves.easeOutCubic.transform(((t - 0.15) / 0.5).clamp(0.0, 1.0));

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Opacity(
          opacity: textIn,
          child: Transform.translate(
            offset: Offset(0, (1 - textIn) * -30),
            child: Column(
              children: [
                Text(
                  scene.label,
                  style: AppTheme.title.copyWith(fontSize: 104, height: 1),
                ),
                const SizedBox(height: 22),
                Container(
                  width: 132,
                  height: 12,
                  decoration: BoxDecoration(
                    gradient: AppColors.playGradient,
                    borderRadius: BorderRadius.circular(6),
                  ),
                ),
                const SizedBox(height: 30),
                Text(
                  scene.blurb,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.nunito(
                    fontSize: 46,
                    fontWeight: FontWeight.w700,
                    color: AppColors.text,
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 68),
        _PromoBoard(scene: scene, t: t, side: _boardSide),
        // The slot is always reserved, badge or not, so the board sits at the
        // same height in every level scene and does not jump between them.
        const SizedBox(height: 46),
        scene.callout == null
            ? const SizedBox(height: _Callout.height)
            : _Callout(text: scene.callout!, t: t),
      ],
    );
  }
}

/// The feature badge under the board: the play button's own gradient, in a
/// pill. Arrives after the pieces have landed, so it never competes with the
/// board for attention at the moment the ball sets off.
class _Callout extends StatelessWidget {
  const _Callout({required this.text, required this.t});

  final String text;
  final double t;

  /// Fixed slot height, so a scene without a badge lays out identically.
  static const double height = 96;

  /// Seconds into the scene before the badge appears.
  static const double _in = 1.35;

  @override
  Widget build(BuildContext context) {
    final rise =
        Curves.easeOutCubic.transform(((t - _in) / 0.45).clamp(0.0, 1.0));
    if (rise <= 0) return const SizedBox(height: height);

    return SizedBox(
      height: height,
      child: Opacity(
        opacity: rise,
        child: Transform.translate(
          offset: Offset(0, (1 - rise) * 22),
          child: Transform.scale(
            scale: 0.94 + 0.06 * rise,
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 46, vertical: 22),
              decoration: BoxDecoration(
                gradient: AppColors.playGradient,
                borderRadius: BorderRadius.circular(999),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.coral.withValues(alpha: 0.30),
                    blurRadius: 26,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: Text(
                text,
                style: GoogleFonts.nunito(
                  fontSize: 44,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                  height: 1,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The board itself: the game's own painter, driven entirely from the clock.
class _PromoBoard extends StatelessWidget {
  const _PromoBoard({
    required this.scene,
    required this.t,
    required this.side,
  });

  final _LevelScene scene;
  final double t;
  final double side;

  @override
  Widget build(BuildContext context) {
    final s = scene;
    final geo = GridGeometry(side, s.level.size);

    // --- pieces on the board, and their pop-in progress ---------------------
    final placed = <int, PlacedElement>{};
    final placeAnim = <int, double>{};
    for (var i = 0; i < s.drops.length; i++) {
      final d = s.drops[i];
      final at = s.dropTime(i);
      if (t < at) continue;
      placed[s.keyOf(d.r, d.c)] = d.piece;
      final p = (t - at) / _kPop;
      if (p < 1) placeAnim[s.keyOf(d.r, d.c)] = p;
    }

    // --- where the ball is, and what has happened to it so far -------------
    final run = _runStateAt(s, t);

    // A collected shield leaves the board, shrinking out the way the game
    // shrinks it out.
    final removing = <FadingPiece>[];
    if (run.shieldTakenAt != null) {
      final key = run.shieldKey!;
      final piece = placed.remove(key);
      final p = (t - run.shieldTakenAt!) / _kShrink;
      if (piece != null && p < 1) {
        removing.add(FadingPiece(key, piece.tool, piece.direction)
          ..progress = p.clamp(0.0, 1.0));
      }
    }

    // --- blasts -------------------------------------------------------------
    final explosions = <Explosion>[];
    final destroyed = <int>{};
    final cellGlow = <int, double>{};
    final cellGlowColor = <int, Color>{};
    s.frags.forEach((hopIndex, frags) {
      final at = s.hopTimes[hopIndex];
      if (t < at) return;
      final hop = s.path[hopIndex];
      final key = s.keyOf(hop.r, hop.c);
      destroyed.add(key);
      final p = (t - at) / _kBoom;
      if (p <= 1) {
        explosions.add(Explosion(key, frags)..t = p);
        cellGlow[key] = 1 - p;
        cellGlowColor[key] = const Color(0xFFEF5350);
      }
    });

    // --- a cell lights up as the ball uses the piece on it ------------------
    // Looked up against the SCRIPT rather than against `placed`, so a shield
    // still flashes on the beat it is collected and taken off the board.
    for (var i = 0; i < s.path.length; i++) {
      final at = s.hopTimes[i];
      if (t < at || t > at + _kCellFlash) continue;
      final key = s.keyOf(s.path[i].r, s.path[i].c);
      final piece = s.pieceAt(key) ?? s.forced[key];
      if (piece == null) continue;
      if (cellGlow.containsKey(key)) continue; // a blast owns the cell
      cellGlow[key] = 1 - (t - at) / _kCellFlash;
      cellGlowColor[key] = toolGlowColor(piece.tool);
    }

    final trail = [
      for (var i = 0; i <= run.hopIndex && i < s.path.length; i++)
        s.keyOf(s.path[i].r, s.path[i].c),
    ];

    // Win ripple, once a surviving ball has reached the goal.
    final winProgress = (!s.fatal && run.finished)
        ? ((t - s.hopTimes.last) / _kWinWave).clamp(0.0, 1.0)
        : 0.0;

    // Board fade/scale in, matched to the scene's own edges.
    final rise = Curves.easeOutBack.transform(
        (t / _kBoardIn).clamp(0.0, 1.0));

    return Transform.scale(
      scale: 0.94 + 0.06 * rise,
      child: SizedBox(
        width: side,
        height: side,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(22),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.ink.withValues(alpha: 0.16),
                    blurRadius: 40,
                    offset: const Offset(0, 16),
                  ),
                ],
              ),
              child: CustomPaint(
                size: Size.square(side),
                painter: GameGridPainter(
                  level: s.level,
                  placed: placed,
                  forced: s.forced,
                  rotations: const {},
                  trail: trail,
                  // The clock already forces a repaint every frame through
                  // glowTick; the revision just keeps the contract honest.
                  revision: run.hopIndex,
                  placeAnim: placeAnim,
                  removing: removing,
                  cellGlow: cellGlow,
                  cellGlowColor: cellGlowColor,
                  cellPulse: const {},
                  explosions: explosions,
                  destroyedCells: destroyed,
                  glowTick: (t / 1.4) % 1.0,
                  // The start cell advertises its heading right up until the
                  // ball actually leaves it.
                  showStartHint: t < s.runStart,
                  winProgress: winProgress,
                ),
              ),
            ),
            // Portal rings, drawn on the two ends while a warp is in flight.
            if (run.warp != null)
              Positioned.fill(
                child: CustomPaint(
                  painter: _WarpRingPainter(
                    geo: geo,
                    from: run.warp!.from,
                    to: run.warp!.to,
                    progress: run.warp!.progress,
                    color: GameGridPainter.telePairColors[0].$2,
                  ),
                ),
              ),
            // Patrolling mines, drawn with the game's own mine icon.
            if (s.patrols.isNotEmpty)
              Positioned.fill(
                child: CustomPaint(
                  painter: _PatrolPainter(
                    geo: geo,
                    patrols: s.patrols,
                    t: t,
                    glowTick: (t / 1.4) % 1.0,
                  ),
                ),
              ),
            // The ball.
            if (!run.gone) Positioned.fill(child: _ball(geo, run)),
          ],
        ),
      ),
    );
  }

  Widget _ball(GridGeometry geo, _RunState run) {
    final d = geo.cell * 0.46;
    final pos = Offset(
      geo.pad + run.col * geo.cell + geo.cell / 2,
      geo.pad + run.row * geo.cell + geo.cell / 2,
    );
    final glow = 0.5 + 0.5 * math.sin((t / 1.4) * 2 * math.pi);
    return Transform.translate(
      offset: Offset(pos.dx - d / 2, pos.dy - d / 2),
      child: Align(
        alignment: Alignment.topLeft,
        child: Opacity(
          opacity: run.opacity.clamp(0.0, 1.0),
          child: Transform.scale(
            scale: run.scale,
            child: GameDot(
              size: d,
              paused: false,
              glow: glow,
              shielded: run.shielded,
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// The ball, as a function of time
// ---------------------------------------------------------------------------

/// Where the ball is mid-warp: the two cells and how far through the hop it is.
class _WarpState {
  const _WarpState(this.from, this.to, this.progress);
  final (int r, int c) from;
  final (int r, int c) to;
  final double progress;
}

/// Everything about the ball at one instant, derived from the script.
class _RunState {
  const _RunState({
    required this.row,
    required this.col,
    required this.hopIndex,
    required this.shielded,
    required this.gone,
    required this.finished,
    this.scale = 1,
    this.opacity = 1,
    this.warp,
    this.shieldKey,
    this.shieldTakenAt,
  });

  /// Fractional cell coordinates, so a mid-glide ball lands between cells.
  final double row;
  final double col;

  /// The last hop the ball has actually reached.
  final int hopIndex;

  final bool shielded;

  /// True once a fatal blast has taken the ball off the board.
  final bool gone;

  /// True once the ball has arrived at the final hop.
  final bool finished;

  final double scale;
  final double opacity;
  final _WarpState? warp;

  /// The shield piece the ball has collected, and when.
  final int? shieldKey;
  final double? shieldTakenAt;
}

_RunState _runStateAt(_LevelScene s, double t) {
  final path = s.path;
  final times = s.hopTimes;

  // The last hop the ball has reached.
  var i = 0;
  while (i + 1 < path.length && t >= times[i + 1]) {
    i++;
  }

  // A shield stays on from the hop that grants it until a blast spends it.
  int? shieldKey;
  double? shieldTakenAt;
  var shielded = false;
  for (var k = 0; k <= i; k++) {
    switch (path[k].event) {
      case _Ev.shield:
        shielded = true;
        shieldKey = s.keyOf(path[k].r, path[k].c);
        shieldTakenAt = times[k];
      case _Ev.boomSurvive:
        shielded = false;
      case _Ev.boomFatal:
      case null:
        break;
    }
  }

  // Killed: the ball poofs into the blast at the fatal hop.
  if (path[i].event == _Ev.boomFatal) {
    return _RunState(
      row: path[i].r.toDouble(),
      col: path[i].c.toDouble(),
      hopIndex: i,
      shielded: false,
      gone: true,
      finished: true,
      shieldKey: shieldKey,
      shieldTakenAt: shieldTakenAt,
    );
  }

  final atLast = i == path.length - 1;
  final here = path[i];

  // Standing still: before the run, during a hold, or after the finish.
  final next = atLast ? null : path[i + 1];
  final glideStart = atLast ? double.infinity : times[i + 1] - s.beat;
  if (next == null || t < glideStart) {
    return _RunState(
      row: here.r.toDouble(),
      col: here.c.toDouble(),
      hopIndex: i,
      shielded: shielded,
      gone: false,
      finished: atLast,
      shieldKey: shieldKey,
      shieldTakenAt: shieldTakenAt,
    );
  }

  final p = ((t - glideStart) / s.beat).clamp(0.0, 1.0);

  // A warp is not a glide: the ball collapses into the near portal and swells
  // back out of the far one.
  if (next.warp) {
    final half = p < 0.5;
    final leg = half ? p / 0.5 : (p - 0.5) / 0.5;
    final cell = half ? here : next;
    return _RunState(
      row: cell.r.toDouble(),
      col: cell.c.toDouble(),
      hopIndex: i,
      shielded: shielded,
      gone: false,
      finished: false,
      scale: half ? 1 - 0.78 * leg : 0.22 + 0.78 * leg,
      opacity: half ? 1 - leg : leg,
      warp: _WarpState(
        (here.r, here.c),
        (next.r, next.c),
        p,
      ),
      shieldKey: shieldKey,
      shieldTakenAt: shieldTakenAt,
    );
  }

  final e = Curves.easeInOutCubic.transform(p);
  return _RunState(
    row: here.r + (next.r - here.r) * e,
    col: here.c + (next.c - here.c) * e,
    hopIndex: i,
    shielded: shielded,
    gone: false,
    finished: false,
    shieldKey: shieldKey,
    shieldTakenAt: shieldTakenAt,
  );
}

// ---------------------------------------------------------------------------
// Overlay painters
// ---------------------------------------------------------------------------

/// Rings at both ends of a warp: one collapsing into the entrance, one blooming
/// out of the exit.
class _WarpRingPainter extends CustomPainter {
  const _WarpRingPainter({
    required this.geo,
    required this.from,
    required this.to,
    required this.progress,
    required this.color,
  });

  final GridGeometry geo;
  final (int r, int c) from;
  final (int r, int c) to;
  final double progress;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    void ring(Offset c, double radius, double alpha, double width) {
      if (alpha <= 0) return;
      canvas.drawCircle(
        c,
        radius,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = width
          ..color = color.withValues(alpha: alpha.clamp(0.0, 1.0))
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
      );
    }

    final half = progress < 0.5;
    final leg = half ? progress / 0.5 : (progress - 0.5) / 0.5;
    final cell = geo.cell;

    if (half) {
      // Collapsing into the way in.
      final c = geo.center(from.$1, from.$2);
      ring(c, cell * (0.55 - 0.35 * leg), 0.9 * (1 - leg * 0.4), 5 - 2 * leg);
    } else {
      // Blooming out of the way out.
      final c = geo.center(to.$1, to.$2);
      ring(c, cell * (0.20 + 0.55 * leg), 0.9 * (1 - leg), 5 - 2 * leg);
      ring(c, cell * (0.10 + 0.32 * leg), 0.6 * (1 - leg), 3);
    }
  }

  @override
  bool shouldRepaint(covariant _WarpRingPainter old) =>
      old.progress != progress || old.from != from || old.to != to;
}

/// Mines patrolling their lane, drawn with the board's own mine icon so a
/// patrol looks like exactly what it is.
class _PatrolPainter extends CustomPainter {
  const _PatrolPainter({
    required this.geo,
    required this.patrols,
    required this.t,
    required this.glowTick,
  });

  final GridGeometry geo;
  final List<_Patrol> patrols;
  final double t;
  final double glowTick;

  @override
  void paint(Canvas canvas, Size size) {
    for (final p in patrols) {
      final col = p.columnAt(t);
      final center = Offset(
        geo.pad + col * geo.cell + geo.cell / 2,
        geo.pad + p.row * geo.cell + geo.cell / 2,
      );
      // The same red danger halo the editor draws under a mover.
      canvas.drawCircle(
        center,
        geo.cell * 0.36,
        Paint()
          ..color = const Color(0xFFE53935).withValues(alpha: 0.20)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
      );
      paintMineIcon(canvas, center, geo.cell, glowTick);
    }
  }

  @override
  bool shouldRepaint(covariant _PatrolPainter old) =>
      old.t != t || old.glowTick != glowTick;
}

/// The faint 28px graph paper the whole app sits on.
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
  bool shouldRepaint(covariant _BgGridPainter old) => false;
}

/// Two very soft washes of the game's own accents, so a metre of cream reads as
/// lit rather than as blank paper.
class _WashPainter extends CustomPainter {
  const _WashPainter();

  @override
  void paint(Canvas canvas, Size size) {
    void wash(Offset c, double r, Color color, double alpha) {
      canvas.drawCircle(
        c,
        r,
        Paint()
          ..shader = RadialGradient(
            colors: [
              color.withValues(alpha: alpha),
              color.withValues(alpha: 0),
            ],
          ).createShader(Rect.fromCircle(center: c, radius: r)),
      );
    }

    wash(Offset(size.width * 0.68, size.height * 0.56), 700,
        AppColors.accent, 0.15);
    wash(Offset(size.width * 0.24, size.height * 0.22), 620,
        AppColors.coral, 0.11);
  }

  @override
  bool shouldRepaint(covariant _WashPainter old) => false;
}
