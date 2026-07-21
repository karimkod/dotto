import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../audio/sfx.dart';
import '../data/level_definitions.dart';
import '../engine/simulator.dart'
    show
        adjacentWallKeys,
        buildForcedPieces,
        buildMovers,
        buildTeleportLinks,
        DeathCause,
        MoverState,
        moversCrossed;
import '../models/game_state.dart';
import '../models/grid_cell.dart';
import '../models/level.dart';
import '../models/level_data.dart';
import '../progress/progress_store.dart';
import '../theme/app_theme.dart';
import '../utils/dev_mode.dart';
import '../widgets/bouncy_button.dart';
import '../widgets/feedback_dialog.dart';
import '../widgets/game_grid.dart';
import '../widgets/game_toolbar.dart';
import '../widgets/top_bar.dart';
import 'level_designer_screen.dart';

/// Milliseconds between dot movement ticks.
const _tickMs = 400;

/// Fixed height reserved for the bottom button area (the hint line + Play, the
/// win pause, or Continue/Back to Menu). Pinning it keeps the grid above from
/// shifting as the footer swaps between these states.
const double _kFooterHeight = 82;

/// The core game screen. For levels with a definition it is fully playable;
/// otherwise it shows a "coming soon" placeholder.
///
/// Drag-and-drop is implemented manually with pan gestures on a top-level
/// [GestureDetector] (no [DragTarget]) so all coordinate math is under our
/// control — reliable across platforms including web.
class GameScreen extends StatefulWidget {
  const GameScreen({super.key, required this.level, this.levelOverride});

  final Level level;

  /// When set (used by the dev level designer), the screen plays this level
  /// definition directly instead of looking it up by number. Progress is not
  /// recorded and there is no "next level".
  final LevelData? levelOverride;

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen>
    with TickerProviderStateMixin {
  LevelData? _level;

  final Map<int, PlacedElement> _placed = {};

  /// Immovable, level-defined arrows (rendered + simulated, never interactive).
  final Map<int, PlacedElement> _forced = {};

  Map<ToolType, int> _kit = {};
  ToolType? _selected;

  GameStatus _status = GameStatus.planning;
  late DotState _dot;

  /// Ordered list of visited cells (most recent last) for the fading trail.
  final List<int> _trail = [];

  /// Why the dot died, shown prominently on the fail overlay.
  DeathCause? _deathCause;

  Timer? _timer;
  late final AnimationController _dotCtrl; // per-step glide + squish
  late final Animation<double> _dotScale; // arrival squish
  late final AnimationController _moverCtrl; // patrol glide (every beat)
  late final AnimationController _glowCtrl; // continuous fx driver
  (int, int) _animFrom = (0, 0);
  (int, int) _animTo = (0, 0);

  // Visual effect state, advanced each frame in [_onFxTick].
  final Map<int, double> _placeAnim = {}; // cell → pop-in progress
  final List<FadingPiece> _removing = []; // shrinking-away pieces
  final Map<int, double> _cellGlow = {}; // cell → glow intensity
  final Map<int, Color> _cellGlowColor = {};
  final Map<int, double> _cellPulse = {}; // cell → neighbor ripple progress
  final List<Explosion> _explosions = []; // destroyer blasts in progress
  final Set<int> _destroyedCells = {}; // destroyers cleared by a shielded dot
  final Set<int> _consumedShields = {}; // shield cells picked up this run

  /// True once the dot has the protective shield aura (consumed by a destroyer).
  bool _dotShielded = false;

  /// True once the dot has been blown up (hidden during the fatal explosion).
  bool _dotGone = false;

  /// Runtime patrol (moving destroyer) state + their pre-step cells (for glide).
  List<MoverState> _movers = [];
  List<(int, int)> _moverFrom = [];

  // Win celebration: grid fades out, a full celebration screen fades in.
  late final AnimationController _winCtrl;
  bool _celebrationDone = false;
  String _winMessage = '';

  // Level-2 tutorial: a ghost hand that drags the Up arrow onto the cell.
  late final AnimationController _handCtrl;
  Timer? _handTimer;
  bool _showHand = false;
  static const _tutorialCell = (2, 2); // solution cell for level 2

  static const _winMessages = [
    'Nailed it!',
    'Perfect!',
    'Well done!',
    'Brilliant!',
    'Smooth!',
    'Nice one!',
  ];

  // "Magnet snap": the dropped ghost flies into the target cell, then pops in.
  late final AnimationController _snapCtrl;
  ToolType? _snapTool; // tool to place when the snap finishes
  PlacedElement? _snapPiece; // moved piece to drop when the snap finishes
  int? _snapKey; // target cell
  Offset? _snapFrom; // drop position (global)
  Offset? _snapTo; // target cell center (global)

  /// Board Stack render key, for global<->local coordinate conversion.
  final GlobalKey _boardKey = GlobalKey();

  /// Root Stack key, for positioning the floating drag ghost.
  final GlobalKey _rootKey = GlobalKey();

  /// One key per toolkit tile, so a pan can be matched to the tile it began on.
  final Map<ToolType, GlobalKey> _toolKeys = {};

  // Manual-drag state.
  ToolType? _dragTool; // tool being dragged from the toolbar (place new)
  PlacedElement? _dragPiece; // a placed piece picked up off the grid (move)
  int? _dragOriginKey; // the cell the picked-up piece came from
  Offset? _dragGlobal; // current pointer position (global)

  // Live placement preview (valid empty cell under the pointer).
  (int, int)? _hoverCell;
  ToolType? _hoverTool;

  @override
  void initState() {
    super.initState();
    _dotCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 320),
    );
    _moverCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 320),
    )..value = 1;
    // Brief squish: stays at 1.0, then pops to 1.15 and settles on arrival.
    _dotScale = TweenSequence<double>([
      TweenSequenceItem(tween: ConstantTween(1.0), weight: 60),
      TweenSequenceItem(
        tween: Tween(begin: 1.0, end: 1.15).chain(
          CurveTween(curve: Curves.easeOut),
        ),
        weight: 18,
      ),
      TweenSequenceItem(
        tween: Tween(begin: 1.15, end: 1.0).chain(
          CurveTween(curve: Curves.easeIn),
        ),
        weight: 22,
      ),
    ]).animate(_dotCtrl);
    // Always-running driver for the dot's glow pulse and cell effect decay.
    _glowCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat();
    _glowCtrl.addListener(_onFxTick);
    // Quick magnet-snap of the dropped ghost into the cell.
    _snapCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 110),
    );
    _snapCtrl.addStatusListener((s) {
      if (s == AnimationStatus.completed) _finishSnap();
    });
    _winCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    );
    _winCtrl.addStatusListener((s) {
      if (s == AnimationStatus.completed && mounted) {
        setState(() => _celebrationDone = true);
      }
    });
    // ~3 loops of the tutorial hand, then a fade.
    _handCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 5400),
    );
    _handCtrl.addStatusListener((s) {
      if (s == AnimationStatus.completed && mounted) {
        setState(() => _showHand = false);
      }
    });
    _level = widget.levelOverride ?? levelDataFor(widget.level.number);
    if (_level != null) {
      _kit = {for (final e in _level!.toolkit) e.type: e.count};
      for (final e in _level!.toolkit) {
        _toolKeys[e.type] = GlobalKey();
      }
      // Fixed arrows, shields and pauses alike — _canPlace/_canDropAt already
      // refuse any cell in _forced, so they all become undroppable for free.
      _forced.addAll(buildForcedPieces(_level!));
      _selected = _level!.toolkit.isNotEmpty ? _level!.toolkit.first.type : null;
      _resetDot();
      // Level 2 teaches drag-and-drop: show the hint hand after a beat.
      if (_level!.id == 2) {
        _handTimer = Timer(const Duration(seconds: 2), _startHand);
      }
    }
  }

  void _startHand() {
    if (!mounted || _placed.isNotEmpty || _status != GameStatus.planning) return;
    setState(() => _showHand = true);
    _handCtrl.forward(from: 0);
  }

  /// Stop the tutorial hand for good once the player interacts.
  void _stopHand() {
    _handTimer?.cancel();
    _handTimer = null;
    if (_showHand) {
      _handCtrl.stop();
      setState(() => _showHand = false);
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _handTimer?.cancel();
    _dotCtrl.dispose();
    _moverCtrl.dispose();
    _glowCtrl.dispose();
    _snapCtrl.dispose();
    _winCtrl.dispose();
    _handCtrl.dispose();
    super.dispose();
  }

  int _idx(int r, int c) => r * _level!.size + c;

  /// The cell's type accounting for chain-exploded cells (cleared walls and
  /// destroyers read as empty/passable).
  CellType _effBase(int r, int c) => _destroyedCells.contains(_idx(r, c))
      ? CellType.empty
      : _level!.baseTypeAt(r, c);

  int get _revision => _placed.length * 10000 + _trail.length;

  /// Number of toolkit pieces not yet placed (0 once the kit is fully used).
  int get _remainingPieces => _kit.values.fold(0, (sum, c) => sum + c);

  /// Advance per-frame visual effects (called on every [_glowCtrl] tick).
  void _onFxTick() {
    const dt = 1 / 60;
    if (_placeAnim.isNotEmpty) {
      final done = <int>[];
      _placeAnim.updateAll((k, v) => v + dt / 0.60); // ~600ms leisurely bounce
      _placeAnim.forEach((k, v) {
        if (v >= 1) done.add(k);
      });
      for (final k in done) {
        _placeAnim.remove(k);
      }
    }
    if (_cellPulse.isNotEmpty) {
      final done = <int>[];
      _cellPulse.updateAll((k, v) => v + dt / 0.40); // ~400ms ripple
      _cellPulse.forEach((k, v) {
        if (v >= 1) done.add(k);
      });
      for (final k in done) {
        _cellPulse.remove(k);
      }
    }
    if (_removing.isNotEmpty) {
      for (final f in _removing) {
        f.progress += dt / 0.15;
      }
      _removing.removeWhere((f) => f.progress >= 1);
    }
    if (_cellGlow.isNotEmpty) {
      final gone = <int>[];
      _cellGlow.updateAll((k, v) => v - 0.022); // ~500ms lingering flash
      _cellGlow.forEach((k, v) {
        if (v <= 0) gone.add(k);
      });
      for (final k in gone) {
        _cellGlow.remove(k);
        _cellGlowColor.remove(k);
      }
    }
    if (_explosions.isNotEmpty) {
      // ~0.5s blast. The board AnimatedBuilder repaints every frame (glowTick),
      // so mutating progress here is enough — no setState needed.
      _explosions.removeWhere((e) {
        e.t += dt / 0.5;
        return e.t >= 1;
      });
    }
  }

  void _glow(int key, Color color, [double intensity = 0.85]) {
    _cellGlow[key] = intensity;
    _cellGlowColor[key] = color;
  }

  /// Kick a ripple pulse on the cells orthogonally adjacent to [key].
  void _rippleNeighbors(int key) {
    final n = _level!.size;
    final r = key ~/ n;
    final c = key % n;
    for (final (dr, dc) in const [(-1, 0), (1, 0), (0, -1), (0, 1)]) {
      final nr = r + dr, nc = c + dc;
      if (nr >= 0 && nr < n && nc >= 0 && nc < n) {
        _cellPulse[nr * n + nc] = 0;
      }
    }
  }

  // ----- dot / animation -----

  void _resetDot() {
    _timer?.cancel();
    _timer = null;
    final s = _level!.start;
    _status = GameStatus.planning;
    _dot = DotState(r: s.r, c: s.c, dir: s.dir);
    _trail
      ..clear()
      ..add(_idx(s.r, s.c));
    _cellGlow.clear();
    _cellGlowColor.clear();
    _cellPulse.clear();
    _removing.clear();
    _explosions.clear();
    _destroyedCells.clear();
    _consumedShields.clear();
    _dotShielded = false;
    _dotGone = false;
    _movers = buildMovers(_level!);
    _moverFrom = [for (final m in _movers) (m.row, m.col)];
    _moverCtrl.value = 1;
    _winCtrl.value = 0;
    _celebrationDone = false;
    _animFrom = (s.r, s.c);
    _animTo = (s.r, s.c);
    _dotCtrl.value = 1;
  }

  void _glide(int fromR, int fromC, int toR, int toC) {
    _animFrom = (fromR, fromC);
    _animTo = (toR, toC);
    _dotCtrl.forward(from: 0);
  }

  void _jump(int r, int c) {
    _animFrom = (r, c);
    _animTo = (r, c);
    _dotCtrl.value = 1;
  }

  // ----- coordinate helpers -----

  /// The board cell under a global position, or null if off-grid.
  (int, int)? _cellAt(Offset global) {
    final box = _boardKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return null;
    final local = box.globalToLocal(global);
    final side = box.size.width;
    if (local.dx < 0 || local.dy < 0 || local.dx >= side || local.dy >= side) {
      return null;
    }
    return GridGeometry(side, _level!.size).cellAt(local);
  }

  /// The toolkit tool whose tile contains a global position, or null.
  ToolType? _toolAt(Offset global) {
    for (final entry in _toolKeys.entries) {
      final box = entry.value.currentContext?.findRenderObject() as RenderBox?;
      if (box == null) continue;
      final rect = box.localToGlobal(Offset.zero) & box.size;
      if (rect.contains(global)) return entry.key;
    }
    return null;
  }

  /// The piece occupying [key] — a player piece or a fixed (forced) arrow.
  PlacedElement? _pieceAt(int key) => _placed[key] ?? _forced[key];

  bool _canPlace((int, int) cell, ToolType tool) {
    if (_status != GameStatus.planning) return false;
    final (r, c) = cell;
    if (_level!.baseTypeAt(r, c) != CellType.empty) return false;
    if (_placed.containsKey(_idx(r, c)) || _forced.containsKey(_idx(r, c))) {
      return false;
    }
    return (_kit[tool] ?? 0) > 0;
  }

  /// The tool currently in hand, whether dragged from the toolbar (place new)
  /// or picked up off the grid (move).
  ToolType? get _activeDragTool => _dragTool ?? _dragPiece?.tool;

  /// Whether the in-hand drag can drop on [cell]. The picked-up piece's origin
  /// cell is already empty (removed on pick-up), so dropping back is allowed.
  bool _canDropAt((int, int) cell) {
    if (_status != GameStatus.planning) return false;
    final (r, c) = cell;
    if (_level!.baseTypeAt(r, c) != CellType.empty) return false;
    if (_placed.containsKey(_idx(r, c)) || _forced.containsKey(_idx(r, c))) {
      return false;
    }
    // Toolkit drag needs stock; a picked-up piece is already in hand.
    if (_dragTool != null) return (_kit[_dragTool] ?? 0) > 0;
    return _dragPiece != null;
  }

  /// Recompute the placement preview for a pointer position (no setState).
  void _refreshHover(Offset global) {
    final cell = _activeDragTool == null ? null : _cellAt(global);
    final valid = cell != null && _canDropAt(cell);
    _hoverCell = valid ? cell : null;
    _hoverTool = valid ? _activeDragTool : null;
  }

  // ----- tap (fallback) -----

  void _onTapUp(TapUpDetails d) {
    if (_status != GameStatus.planning) return;
    final g = d.globalPosition;

    // Tap on a toolkit tile → select it.
    final tool = _toolAt(g);
    if (tool != null) {
      setState(() => _selected = tool);
      return;
    }

    final cell = _cellAt(g);
    if (cell == null) return;
    final key = _idx(cell.$1, cell.$2);

    // Tap a placed piece → remove it.
    if (_placed.containsKey(key)) {
      _removeAt(key);
      return;
    }

    // Tap an empty cell → place the selected tool.
    final sel = _selected;
    if (sel != null && _canPlace(cell, sel)) {
      _placeTool(cell, sel);
    }
  }

  // ----- manual drag -----

  void _onPanStart(DragStartDetails d) {
    if (_status != GameStatus.planning) return;
    _stopHand();
    final g = d.globalPosition;

    // Start dragging a tool out of the toolbar.
    final tool = _toolAt(g);
    if (tool != null && (_kit[tool] ?? 0) > 0) {
      setState(() {
        _dragTool = tool;
        _selected = tool;
        _dragGlobal = g;
        _refreshHover(g);
      });
      return;
    }

    // Otherwise, pick up a placed piece to move it (removed from its cell
    // during the drag; returned/relocated/removed on drop).
    final cell = _cellAt(g);
    if (cell != null) {
      final key = _idx(cell.$1, cell.$2);
      final piece = _placed[key];
      if (piece != null) {
        setState(() {
          _placed.remove(key);
          _dragPiece = piece;
          _dragOriginKey = key;
          _dragGlobal = g;
          _refreshHover(g);
        });
      }
    }
  }

  void _onPanUpdate(DragUpdateDetails d) {
    if (_dragTool == null && _dragPiece == null) return;
    setState(() {
      _dragGlobal = d.globalPosition;
      _refreshHover(d.globalPosition);
    });
  }

  void _onPanEnd(DragEndDetails d) {
    // Use the end position directly (robust even if no update fired).
    final g = d.globalPosition;
    final cell = _cellAt(g);

    if (_dragTool != null) {
      // Toolkit drag → snap then place if valid.
      if (cell != null && _canDropAt(cell)) {
        _startSnap(tool: _dragTool!, cell: cell, from: g);
        return;
      }
    } else if (_dragPiece != null) {
      final piece = _dragPiece!;
      if (cell != null && _canDropAt(cell)) {
        _startSnap(piece: piece, cell: cell, from: g);
        return;
      } else if (cell == null) {
        // Dropped off the grid → remove, returning it to the toolkit.
        setState(() => _kit[piece.tool] = (_kit[piece.tool] ?? 0) + 1);
        Sfx.remove();
        HapticFeedback.lightImpact();
      } else {
        // Dropped on an occupied/invalid cell → return to its origin.
        setState(() => _placed[_dragOriginKey!] = piece);
      }
    }
    _clearDrag();
  }

  void _clearDrag() {
    setState(() {
      _dragTool = null;
      _dragPiece = null;
      _dragOriginKey = null;
      _dragGlobal = null;
      _hoverCell = null;
      _hoverTool = null;
    });
  }

  Offset? _cellCenterGlobal((int, int) cell) {
    final box = _boardKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return null;
    final geo = GridGeometry(box.size.width, _level!.size);
    return box.localToGlobal(geo.center(cell.$1, cell.$2));
  }

  /// Begin the magnet-snap: the ghost flies from [from] into [cell], and the
  /// piece is committed (with the weighty pop) when the snap completes.
  void _startSnap({
    ToolType? tool,
    PlacedElement? piece,
    required (int, int) cell,
    required Offset from,
  }) {
    final key = _idx(cell.$1, cell.$2);
    final to = _cellCenterGlobal(cell);
    setState(() {
      _snapTool = tool;
      _snapPiece = piece;
      _snapKey = key;
      _snapFrom = from;
      _snapTo = to ?? from;
      // The snap ghost takes over; clear the active drag.
      _dragTool = null;
      _dragPiece = null;
      _dragOriginKey = null;
      _dragGlobal = null;
      _hoverCell = null;
      _hoverTool = null;
    });
    if (to == null) {
      _finishSnap();
    } else {
      _snapCtrl.forward(from: 0);
    }
  }

  void _finishSnap() {
    final key = _snapKey;
    final tool = _snapTool;
    final piece = _snapPiece;
    if (key != null) {
      if (tool != null) {
        _commitPlace(key, _newPiece(tool), decrementKit: true);
      } else if (piece != null) {
        _commitPlace(key, piece, decrementKit: false);
      }
    }
    setState(() {
      _snapTool = null;
      _snapPiece = null;
      _snapKey = null;
      _snapFrom = null;
      _snapTo = null;
    });
  }

  /// Drop a piece onto a cell with the full landing reaction.
  void _commitPlace(int key, PlacedElement el, {required bool decrementKit}) {
    _stopHand();
    setState(() {
      _placed[key] = el;
      if (decrementKit) _kit[el.tool] = (_kit[el.tool] ?? 1) - 1;
      _placeAnim[key] = 0; // weighty pop-in
      _glow(key, toolGlowColor(el.tool), 1.0); // bright flash
      _rippleNeighbors(key); // neighbors react
    });
    Sfx.place();
    HapticFeedback.mediumImpact();
  }

  void _placeTool((int, int) cell, ToolType tool) {
    _commitPlace(_idx(cell.$1, cell.$2), _newPiece(tool), decrementKit: true);
  }

  void _removeAt(int key) {
    final piece = _placed[key];
    if (piece == null) return;
    setState(() {
      _placed.remove(key);
      _placeAnim.remove(key);
      _removing.add(FadingPiece(key, piece.tool, piece.direction)); // shrink-out
      _kit[piece.tool] = (_kit[piece.tool] ?? 0) + 1;
      if (piece.type == PlacedType.teleporter) _reindexPortals();
    });
    Sfx.remove();
    HapticFeedback.lightImpact();
  }

  /// Teleporters already on the board, which is also the index the next one
  /// gets — so placements alternate entrance, exit, entrance, exit…
  int get _portalsPlaced =>
      _placed.values.where((p) => p.type == PlacedType.teleporter).length;

  /// True when the next teleporter dropped will be an ENTRANCE. Drives the
  /// toolkit tile's icon so the player can see which end they are holding.
  bool get _nextPortalIsEntrance => _portalsPlaced.isEven;

  /// Close the gap after a portal is taken back, so indices stay 0..n-1 and
  /// pairs do not silently re-partner.
  void _reindexPortals() {
    final portals = _placed.entries
        .where((e) => e.value.type == PlacedType.teleporter)
        .toList()
      ..sort((a, b) =>
          (a.value.portalIndex ?? 0).compareTo(b.value.portalIndex ?? 0));
    for (var i = 0; i < portals.length; i++) {
      _placed[portals[i].key] = portals[i].value.withPortalIndex(i);
    }
  }

  /// A fresh piece for [tool]. Teleporters get the next placement index, which
  /// carries entrance/exit, pair and partner all at once.
  PlacedElement _newPiece(ToolType tool) {
    final el = PlacedElement(
        type: tool.placedType, tool: tool, direction: tool.direction);
    return tool.placedType == PlacedType.teleporter
        ? el.withPortalIndex(_portalsPlaced)
        : el;
  }

  // ----- run loop -----

  void _play() {
    if (_status == GameStatus.running) return;
    setState(() {
      _resetDot();
      _status = GameStatus.running;
    });
    _timer =
        Timer.periodic(const Duration(milliseconds: _tickMs), (_) => _beat());
  }

  List<MoverState> _moversAt(int r, int c) =>
      _movers.where((m) => m.row == r && m.col == c).toList();

  /// Patrols that hit the dot as it moved from (fromR,fromC) to (toR,toC):
  /// those ending on its cell, plus those that traded places with it. Crossing
  /// counts as a hit — otherwise the two slide through each other, which looks
  /// on screen like the dot surviving a direct strike. [_moverFrom] is captured
  /// before the step and kept index-aligned by [_removeMover].
  List<MoverState> _moversHitting(int toR, int toC, int fromR, int fromC) {
    final out = <MoverState>[];
    for (var i = 0; i < _movers.length; i++) {
      final m = _movers[i];
      if (m.row == toR && m.col == toC) {
        out.add(m);
        continue;
      }
      if (i < _moverFrom.length &&
          moversCrossed(
            dotFromR: fromR,
            dotFromC: fromC,
            dotToR: toR,
            dotToC: toC,
            moverFromR: _moverFrom[i].$1,
            moverFromC: _moverFrom[i].$2,
            moverToR: m.row,
            moverToC: m.col,
          )) {
        out.add(m);
      }
    }
    return out;
  }

  /// Remove a patrol from the active list, keeping [_moverFrom] index-aligned
  /// with [_movers] so the surviving patrols keep gliding from their OWN
  /// previous cell (not a shifted neighbour's) after one is destroyed.
  void _removeMover(MoverState m) {
    final i = _movers.indexOf(m);
    if (i < 0) return;
    _movers.removeAt(i);
    if (i < _moverFrom.length) _moverFrom.removeAt(i);
  }

  /// The dot (carrying a shield) destroys the patrol(s) on its cell: spend the
  /// aura, remove the mover(s), blow each one up and chain-explode its adjacent
  /// walls. The dot survives.
  void _shieldDestroyMovers(List<MoverState> hit) {
    setState(() {
      _dotShielded = false;
      for (final m in hit) {
        _removeMover(m);
      }
    });
    for (final m in hit) {
      final key = _idx(m.row, m.col);
      _explode(key, fatal: false);
      for (final w in adjacentWallKeys(_level!, key)) {
        if (_destroyedCells.contains(w)) continue;
        _explodeWall(w);
      }
    }
  }

  /// Waits until the dot's and the patrols' one-beat glide animations settle, so
  /// nothing explodes while the dot (or a patrol) is still mid-glide, "in the
  /// air." Returns once both controllers have reached the end of the current
  /// beat's animation.
  Future<void> _settleGlides() async {
    try {
      await Future.wait([
        if (_dotCtrl.isAnimating) _dotCtrl.forward().orCancel,
        if (_moverCtrl.isAnimating) _moverCtrl.forward().orCancel,
      ]);
    } catch (_) {
      // A ticker was canceled (widget disposed / run reset) — nothing to do.
    }
  }

  /// A FATAL hit — a static mine or a patrol. The blast waits for the glide to
  /// finish so the dot visually REACHES the cell before it bursts, instead of
  /// exploding mid-glide. Any colliding patrol(s) blow up with it and leave the
  /// board (they share [cell] with the dot, so the blast covers them).
  Future<void> _fatalHit(int cell, DeathCause cause,
      {List<MoverState> hit = const []}) async {
    _timer?.cancel(); // stop further beats while the glides settle
    _timer = null;
    await _settleGlides();
    if (!mounted || _status != GameStatus.running) return;
    if (hit.isNotEmpty) {
      setState(() {
        for (final m in hit) {
          _removeMover(m);
        }
      });
    }
    _explode(cell, fatal: true);
    _failExploded(cause);
  }

  /// Runs a SURVIVING shielded blow-up (destroyer/patrol chain explosion) only
  /// after the dot's glide finishes, so the boom lands as the dot reaches the
  /// cell. The beat timer is HELD during the glide so no later beat runs on the
  /// pre-blast board (which would move the dot into the still-solid wall); the
  /// run resumes once the chain — clearing walls, spending the shield — resolves.
  Future<void> _afterGlide(void Function() blast) async {
    _timer?.cancel();
    _timer = null;
    await _settleGlides();
    if (!mounted || _status != GameStatus.running) return;
    blast();
    _timer =
        Timer.periodic(const Duration(milliseconds: _tickMs), (_) => _beat());
  }

  void _beat() {
    if (_status != GameStatus.running) return;
    final size = _level!.size;

    // 1. Patrols advance simultaneously with the dot — collisions are checked
    // only after BOTH have moved (below), so a patrol the dot is leaving as it
    // arrives doesn't kill it.
    if (_movers.isNotEmpty) {
      setState(() {
        _moverFrom = [for (final m in _movers) (m.row, m.col)];
        for (final m in _movers) {
          m.step(_destroyedCells);
        }
      });
      _moverCtrl.forward(from: 0);
    }

    if (_dot.pause > 0) {
      setState(() => _dot.pause--);
      // The dot held still — a patrol that ends on it collides. A shield blows
      // the patrol away; otherwise the dot is caught.
      final hit = _moversAt(_dot.r, _dot.c);
      if (hit.isNotEmpty) {
        if (_dotShielded) {
          // Let the patrol finish gliding onto the dot before the blast.
          _afterGlide(() => _shieldDestroyMovers(hit));
        } else {
          _fatalHit(_idx(_dot.r, _dot.c), DeathCause.patrol, hit: hit);
        }
      }
      return;
    }

    final (dr, dc) = _dot.dir.delta;
    final nr = _dot.r + dr;
    final nc = _dot.c + dc;

    if (nr < 0 || nr >= size || nc < 0 || nc >= size) {
      _fail(DeathCause.edge);
      return;
    }
    if (_effBase(nr, nc) == CellType.wall) {
      _fail(DeathCause.wall);
      return;
    }

    final fromR = _dot.r, fromC = _dot.c;
    final newKey = _idx(nr, nc);
    setState(() {
      _dot.r = nr;
      _dot.c = nc;
      _trail.add(newKey);
      _glow(newKey, AppColors.accent, 0.7); // warm cell highlight on entry
    });
    _glide(fromR, fromC, nr, nc);
    Sfx.tick();

    // Both have moved — a patrol catches the dot by sharing its FINAL cell or by
    // trading places with it. A shield blows the patrol away and the dot
    // survives; otherwise it's caught.
    final hitMovers = _moversHitting(nr, nc, fromR, fromC);
    if (hitMovers.isNotEmpty) {
      if (_dotShielded) {
        // Survive: blow the patrol away once the dot has glided into the cell,
        // then resolve that cell as normal. Surviving a patrol does NOT skip
        // what is on the floor underneath it — an arrow there still turns the
        // dot, a pause still holds it. (The patrol's cell is plain empty floor,
        // so unlike a static mine the player can place a piece on it.)
        _afterGlide(() {
          _shieldDestroyMovers(hitMovers);
          _resolveCell(newKey, nr, nc);
        });
        return; // the dot moves on next beat
      }
      // Let the dot and the patrol finish gliding into the shared cell first.
      _fatalHit(newKey, DeathCause.patrol, hit: hitMovers);
      return;
    }

    _resolveCell(newKey, nr, nc);
  }

  /// Resolve whatever the dot has landed on: hazards underfoot, the start-cell
  /// redirect, any placed piece, and the exit. Mirrors the tail of
  /// [simulateDetailed] in the same order, and is reached both by a clean
  /// arrival and by surviving a patrol on this cell with a shield.
  ///
  /// A patrol never stands on a static mine (mines are solid to patrols), so the
  /// mine branch below cannot re-enter [_afterGlide] when called from a blast.
  void _resolveCell(int newKey, int nr, int nc) {
    final base = _effBase(nr, nc);
    if (base == CellType.gap) {
      _die(DeathCause.gap);
      return;
    }
    if (base == CellType.destroyer || base == CellType.movingDestroyer) {
      if (_dotShielded) {
        // The shield absorbs the blow: the destroyer explodes, every adjacent
        // wall is demolished (chain explosion), and the dot survives. Wait for
        // the dot to glide onto the cell so the boom lands on contact.
        _afterGlide(() => _chainExplode(newKey));
        return; // survive this tick; the dot moves on next beat
      }
      // Wait for the dot to reach the mine before it bursts (no mid-air blast).
      _fatalHit(newKey, DeathCause.destroyer);
      return;
    }

    // The start cell acts as a permanent forced arrow on every visit.
    if (base == CellType.start) {
      setState(() {
        _dot.dir = _level!.start.dir;
        _glow(newKey, const Color(0xFF1E88E5), 1.0);
      });
      Sfx.arrow();
    }

    final piece = _pieceAt(newKey);
    if (piece != null) {
      switch (piece.type) {
        case PlacedType.arrow:
          setState(() {
            _dot.dir = piece.direction!;
            _glow(newKey, const Color(0xFF1E88E5), 1.0); // arrow activation flash
          });
          Sfx.arrow();
        case PlacedType.pause:
          setState(() {
            _dot.pause = 2;
            _glow(newKey, const Color(0xFFBA68C8), 1.0);
          });
          Sfx.pause();
        case PlacedType.shield:
          // Collected once per run: revisiting the (now-empty) cell grants
          // nothing. The placement stays in _placed so Retry restores it.
          if (_consumedShields.add(newKey)) {
            setState(() {
              _dotShielded = true; // gain the protective aura (one at a time)
              _glow(newKey, kShieldColor, 1.0);
              // The shield leaves the grid with a shrink-out as it's picked up.
              // (_revision changes each beat as the trail grows, so the grid
              // repaints without the now-hidden shield.)
              _removing.add(FadingPiece(newKey, piece.tool, piece.direction));
            });
            Sfx.shield();
          }
        case PlacedType.teleporter:
          _teleport();
      }
    }

    if (_level!.baseTypeAt(_dot.r, _dot.c) == CellType.exit) {
      _win();
    }
  }

  /// Out the far end of the pair, keeping the heading. Uses the shared link
  /// table so level-defined pairs and the player's own both work, and so the
  /// game agrees with the simulator about which end connects to which.
  void _teleport() {
    final size = _level!.size;
    final links = buildTeleportLinks(_level!, {..._forced, ..._placed});
    final dest = links[_idx(_dot.r, _dot.c)];
    if (dest == null) return; // an unpaired teleporter is inert
    setState(() {
      _dot.r = dest ~/ size;
      _dot.c = dest % size;
      _trail.add(dest);
      _glow(dest, const Color(0xFFFF8A65), 1.0);
    });
    _jump(_dot.r, _dot.c);
    Sfx.teleport();
  }

  void _win() {
    _timer?.cancel();
    _timer = null;
    Sfx.exit();
    // Record completion → unlocks the next level (skipped for designer tests).
    if (widget.levelOverride == null) ProgressStore.markCompleted(_level!.id);
    // Brief beat with the dot at the exit, then the grid fades to celebration.
    setState(() {
      _status = GameStatus.won;
      _celebrationDone = false;
      _winMessage = _winMessages[math.Random().nextInt(_winMessages.length)];
    });
    _winCtrl.forward(from: 0);
    // Rising chime as the celebration screen comes in (after the ~0.5s pause).
    Future.delayed(const Duration(milliseconds: 600), () {
      if (mounted) Sfx.levelComplete();
    });
  }

  /// Load the next level in place (no trip back to the menu).
  void _goToNextLevel() {
    final next = _level!.id + 1;
    final data = levelDataFor(next);
    if (data == null) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => GameScreen(
          level: Level(
            id: next,
            number: next,
            title: data.title,
            difficulty: Difficulty.easy,
            status: LevelStatus.unlocked,
          ),
        ),
      ),
    );
  }

  void _die(DeathCause cause) {
    _timer?.cancel();
    _timer = null;
    _deathCause = cause;
    Sfx.die();
    Future.delayed(const Duration(milliseconds: 280), () {
      if (!mounted) return;
      setState(() => _status = GameStatus.lost);
    });
  }

  /// Spawn a destroyer explosion at [cell]: a cell flash, flying fragments, a
  /// "boom" and a heavy haptic. When [fatal] the dot is hidden (it poofs into
  /// the blast); otherwise (a shielded survival) the dot keeps moving.
  void _explode(int cell, {required bool fatal}) {
    final rng = math.Random();
    const colors = [
      Color(0xFFEF5350), // red
      Color(0xFFFF8A65), // orange
      Color(0xFFFFD54F), // yellow
    ];
    final frags = <Frag>[
      for (var i = 0; i < 14; i++)
        Frag(
          i / 14 * 2 * math.pi + rng.nextDouble() * 0.5,
          0.6 + rng.nextDouble() * 1.0,
          colors[rng.nextInt(colors.length)],
          0.7 + rng.nextDouble() * 0.8,
        ),
    ];
    setState(() {
      _explosions.add(Explosion(cell, frags));
      _destroyedCells.add(cell); // the destroyer is gone after the blast
      _glow(cell, const Color(0xFFEF5350), 1.0); // bright red cell flash
      if (fatal) _dotGone = true;
    });
    Sfx.boom();
    HapticFeedback.heavyImpact();
  }

  /// A shielded hit: blow up the destroyer AND chain-explode every wall beside
  /// it (each shattering with gray fragments), opening a path. The dot survives.
  void _chainExplode(int destroyerKey) {
    setState(() => _dotShielded = false);
    _explode(destroyerKey, fatal: false);
    for (final w in adjacentWallKeys(_level!, destroyerKey)) {
      if (_destroyedCells.contains(w)) continue;
      _explodeWall(w);
    }
  }

  /// A wall shattering: gray fragments fly out and the cell is cleared. Silent —
  /// the destroyer's boom covers the whole blast.
  void _explodeWall(int cell) {
    final rng = math.Random();
    const colors = [
      Color(0xFF78909C),
      Color(0xFF90A4AE),
      Color(0xFFB0BEC5),
    ];
    final frags = <Frag>[
      for (var i = 0; i < 12; i++)
        Frag(
          i / 12 * 2 * math.pi + rng.nextDouble() * 0.5,
          0.5 + rng.nextDouble() * 0.9,
          colors[rng.nextInt(colors.length)],
          0.7 + rng.nextDouble() * 0.8,
        ),
    ];
    setState(() {
      _explosions.add(
          Explosion(cell, frags, tint: const Color(0xFF90A4AE)));
      _destroyedCells.add(cell);
      _glow(cell, const Color(0xFF90A4AE), 0.9);
    });
  }

  /// Death by destroyer: stops the run and shows the fail card AFTER the ~0.5s
  /// explosion has played out.
  void _failExploded(DeathCause cause) {
    _timer?.cancel();
    _timer = null;
    _deathCause = cause;
    Future.delayed(const Duration(milliseconds: 520), () {
      if (!mounted) return;
      setState(() => _status = GameStatus.lost);
    });
  }

  void _fail(DeathCause cause) {
    _timer?.cancel();
    _timer = null;
    _deathCause = cause;
    setState(() => _status = GameStatus.lost);
  }

  /// Reset the dot but keep placed pieces (used by "Retry").
  void _retry() => setState(_resetDot);

  /// Remove every placed piece and restore the toolkit (used by "Reset").
  void _clearAll() {
    setState(() {
      _placed.clear();
      _kit = {for (final e in _level!.toolkit) e.type: e.count};
      _resetDot();
    });
  }

  /// Confirm before clearing the board.
  void _confirmReset() {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.card,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: AppColors.ink, width: 3),
        ),
        title: const Text(
          'Reset all pieces?',
          style: TextStyle(
              fontWeight: FontWeight.w800, color: AppColors.ink, fontSize: 18),
        ),
        content: const Text(
          'This removes everything you placed on the board.',
          style: TextStyle(color: AppColors.textSoft),
        ),
        actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel',
                style: TextStyle(
                    color: AppColors.textSoft, fontWeight: FontWeight.w700)),
          ),
          GestureDetector(
            onTap: () {
              Navigator.of(ctx).pop();
              _clearAll();
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              decoration: BoxDecoration(
                color: AppColors.coral,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.ink, width: 2.5),
              ),
              child: const Text(
                'Reset',
                style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 15),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ----- UI -----

  @override
  Widget build(BuildContext context) {
    if (_level == null) return _buildPlaceholder();

    return Scaffold(
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        // Report the touch-down position to onPanStart (not the post-slop
        // position) so a drag is matched to the tile it actually started on.
        dragStartBehavior: DragStartBehavior.down,
        onTapUp: _onTapUp,
        onPanStart: _onPanStart,
        onPanUpdate: _onPanUpdate,
        onPanEnd: _onPanEnd,
        child: Stack(
          key: _rootKey,
          children: [
            const Positioned.fill(child: CustomPaint(painter: _BgGridPainter())),
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                child: Column(
                  children: [
                    _buildHeader(),
                    const SizedBox(height: 14),
                    Expanded(child: _buildPlayArea()),
                    const SizedBox(height: 16),
                    // Hide the toolkit during the win celebration.
                    if (_status == GameStatus.won)
                      const SizedBox(height: 64)
                    else if (_level!.toolkit.isEmpty)
                      _buildEmptyKitHint()
                    else
                      GameToolbar(
                        tools: _level!.toolkit.map((e) => e.type).toList(),
                        counts: _kit,
                        selected: _selected,
                        enabled: _status != GameStatus.running,
                        tileKeys: _toolKeys,
                        draggingTool: _dragTool,
                        portalNextIsEntrance: _nextPortalIsEntrance,
                        onSelect: (t) => setState(() => _selected = t),
                        onReset: _confirmReset,
                      ),
                    const SizedBox(height: 16),
                    _buildFooter(),
                  ],
                ),
              ),
            ),
            // Fail still uses a small overlay; win celebrates on the grid.
            if (_status == GameStatus.lost) _buildOverlay(),
            // Drag/snap ghost (rebuilds during the snap flight via _snapCtrl).
            AnimatedBuilder(
              animation: _snapCtrl,
              builder: (_, _) => _buildGhost(),
            ),
            if (_showHand)
              AnimatedBuilder(
                animation: _handCtrl,
                builder: (_, _) => _buildTutorialHand(),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      children: [
        BorderedTile(
          width: 46,
          onTap: () => Navigator.of(context).pop(),
          child: const Icon(Icons.arrow_back_rounded,
              color: AppColors.ink, size: 24),
        ),
        const Spacer(),
        Text(
          'Level ${_level!.id}',
          style: const TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w800,
            color: AppColors.ink,
          ),
        ),
        // Dev-only: edit this level in the designer.
        if (isDevMode) ...[
          const SizedBox(width: 8),
          GestureDetector(
            onTap: _openInDesigner,
            child: const Icon(Icons.edit_rounded,
                color: AppColors.textSoft, size: 20),
          ),
        ],
        const Spacer(),
        BorderedTile(
          background: AppColors.ink,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          onTap: () {},
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: const [
              Text('👑', style: TextStyle(fontSize: 16)),
              SizedBox(width: 5),
              Text('x3',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w800)),
            ],
          ),
        ),
        const SizedBox(width: 8),
        // Small, unobtrusive feedback button (top-right).
        BorderedTile(
          width: 44,
          onTap: _showFeedbackDialog,
          child: const Icon(Icons.chat_bubble_outline_rounded,
              color: AppColors.ink, size: 20),
        ),
      ],
    );
  }

  void _showFeedbackDialog() {
    showDialog<void>(
      context: context,
      builder: (_) => FeedbackDialog(level: _level!.id),
    );
  }

  /// Dev-only: open this level in the designer, pre-loaded for editing.
  void _openInDesigner() {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => LevelDesignerScreen(
        initialLevel: _level,
        initialNumber: _level!.id,
        initialDifficulty: widget.level.difficulty,
      ),
    ));
  }

  Widget _buildBoard() {
    return AspectRatio(
      aspectRatio: 1,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final side = constraints.maxWidth;
          final geo = GridGeometry(side, _level!.size);
          final previewKey = _hoverCell == null
              ? null
              : _idx(_hoverCell!.$1, _hoverCell!.$2);

          // KeyedSubtree exposes a stable test key while the inner Stack keeps
          // the GlobalKey used for coordinate conversion.
          return KeyedSubtree(
            key: const ValueKey('gameBoard'),
            child: Stack(
              key: _boardKey,
              children: [
                RepaintBoundary(
                  child: AnimatedBuilder(
                    animation: Listenable.merge([_glowCtrl, _winCtrl]),
                    builder: (_, _) => CustomPaint(
                      size: Size.square(side),
                      painter: GameGridPainter(
                        level: _level!,
                        // Picked-up shields vanish from the grid (the shrink-out
                        // is drawn via `removing`); the placement itself stays
                        // in _placed so Retry restores it.
                        placed: _consumedShields.isEmpty
                            ? _placed
                            : {
                                for (final e in _placed.entries)
                                  if (!_consumedShields.contains(e.key))
                                    e.key: e.value,
                              },
                        trail: _trail,
                        revision: _revision,
                        placeAnim: _placeAnim,
                        removing: _removing,
                        forced: _forced,
                        cellGlow: _cellGlow,
                        cellGlowColor: _cellGlowColor,
                        cellPulse: _cellPulse,
                        explosions: _explosions,
                        destroyedCells: _destroyedCells,
                        glowTick: _glowCtrl.value,
                        showStartHint: _status == GameStatus.planning,
                        winProgress:
                            _status == GameStatus.won ? _winCtrl.value : 0.0,
                        previewKey: previewKey,
                        previewTool: _hoverTool,
                      ),
                    ),
                  ),
                ),
                Positioned.fill(
                  child: AnimatedBuilder(
                    animation: Listenable.merge([_dotCtrl, _glowCtrl]),
                    builder: (_, _) {
                      // Hidden once the dot has been blown up by a destroyer.
                      if (_dotGone) return const SizedBox.shrink();
                      final from = geo.center(_animFrom.$1, _animFrom.$2);
                      final to = geo.center(_animTo.$1, _animTo.$2);
                      final t = Curves.easeInOutCubic.transform(_dotCtrl.value);
                      final pos = Offset.lerp(from, to, t)!;
                      final d = geo.cell * 0.46;
                      // Subtle continuous glow pulse (0..1).
                      final glow =
                          0.5 + 0.5 * math.sin(_glowCtrl.value * 2 * math.pi);
                      return Transform.translate(
                        offset: Offset(pos.dx - d / 2, pos.dy - d / 2),
                        child: Align(
                          alignment: Alignment.topLeft,
                          child: Transform.scale(
                            scale: _dotScale.value,
                            child: _Dot(
                              size: d,
                              paused: _dot.pause > 0,
                              glow: glow,
                              shielded: _dotShielded,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
                // Moving destroyers: red mines gliding between cells, visible
                // while planning AND running so the player can read the patrol.
                if (_movers.isNotEmpty)
                  Positioned.fill(
                    child: IgnorePointer(
                      child: AnimatedBuilder(
                        animation: Listenable.merge([_moverCtrl, _glowCtrl]),
                        builder: (_, _) => CustomPaint(
                          size: Size.square(side),
                          painter: _MoverPainter(
                            movers: _movers,
                            from: _moverFrom,
                            t: Curves.easeInOut.transform(_moverCtrl.value),
                            geo: geo,
                            glowTick: _glowCtrl.value,
                            // Show the patrol path/axis only while planning —
                            // during play the motion itself makes it obvious.
                            planning: _status == GameStatus.planning,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  /// The Expanded play region: the interactive board, or — after a win — the
  /// rippling board with a translucent celebration overlay fading in on top.
  Widget _buildPlayArea() {
    if (_status != GameStatus.won) {
      return Center(child: _buildBoard());
    }
    return AnimatedBuilder(
      animation: _winCtrl,
      builder: (_, _) {
        return Stack(
          fit: StackFit.expand,
          children: [
            // Grid stays visible and ripples (painter winProgress).
            Center(child: _buildBoard()),
            Positioned.fill(
              child: IgnorePointer(child: _buildCelebrationOverlay(_winCtrl.value)),
            ),
          ],
        );
      },
    );
  }

  /// Translucent cream overlay (~72%) over the still-visible grid, with the
  /// bouncy congratulatory message, a star badge and the level number.
  Widget _buildCelebrationOverlay(double v) {
    // The overlay starts fading in after the grid ripple has begun (~0.5s).
    final overlayFade = ((v - 0.23) / 0.22).clamp(0.0, 1.0);
    // Checkmark self-draws over ~0.8s (circle then tick).
    final checkProgress = ((v - 0.30) / 0.40).clamp(0.0, 1.0);
    final msgT = ((v - 0.36) / 0.34).clamp(0.0, 1.0);
    final msgScale = msgT == 0 ? 0.0 : Curves.elasticOut.transform(msgT);
    final msgOpacity = (msgT / 0.25).clamp(0.0, 1.0);
    final subT = ((v - 0.50) / 0.30).clamp(0.0, 1.0);

    return Stack(
      fit: StackFit.expand,
      children: [
        // Cream wash — grid still faintly visible behind it.
        ColoredBox(
          color: AppColors.background.withValues(alpha: 0.72 * overlayFade),
        ),
        Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _SuccessCheck(progress: checkProgress),
              const SizedBox(height: 26),
              Transform.scale(
                scale: msgScale,
                child: Opacity(
                  opacity: msgOpacity,
                  child: Text(
                    _winMessage,
                    textAlign: TextAlign.center,
                    style: GoogleFonts.poppins(
                      fontSize: 52,
                      fontWeight: FontWeight.w800,
                      color: AppColors.coral,
                      height: 1.0,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Opacity(
                opacity: subT,
                child: Text(
                  'Level ${_level!.id}',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textSoft,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// Level-2 tutorial: a semi-transparent hand that repeatedly drags a ghost
  /// Up arrow from the toolbar onto the target cell, then fades out.
  Widget _buildTutorialHand() {
    final toolBox =
        _toolKeys[ToolType.arrowUp]?.currentContext?.findRenderObject()
            as RenderBox?;
    final rootBox = _rootKey.currentContext?.findRenderObject() as RenderBox?;
    final boardBox = _boardKey.currentContext?.findRenderObject() as RenderBox?;
    if (toolBox == null || rootBox == null || boardBox == null) {
      return const SizedBox.shrink();
    }

    final src = rootBox.globalToLocal(toolBox
        .localToGlobal(Offset(toolBox.size.width / 2, toolBox.size.height / 2)));
    final geo = GridGeometry(boardBox.size.width, _level!.size);
    final dst = rootBox.globalToLocal(
        boardBox.localToGlobal(geo.center(_tutorialCell.$1, _tutorialCell.$2)));
    final cell = geo.cell;

    const cycles = 3;
    final v = _handCtrl.value;
    final overallFade = 1 - ((v - 0.9) / 0.1).clamp(0.0, 1.0);
    final cv = (v * cycles) % 1.0;

    // Position: glide src→dst over the first half of each cycle.
    final moveT = ((cv - 0.05) / 0.5).clamp(0.0, 1.0);
    final pos = Offset.lerp(src, dst, Curves.easeInOut.transform(moveT))!;
    // A little press when it lands.
    final press = (cv >= 0.56 && cv < 0.70) ? 0.86 : 1.0;
    // Per-cycle visibility: appear, hold, fade before resetting to src.
    double cycleOpacity;
    if (cv < 0.05) {
      cycleOpacity = cv / 0.05;
    } else if (cv < 0.70) {
      cycleOpacity = 1;
    } else if (cv < 0.86) {
      cycleOpacity = 1 - (cv - 0.70) / 0.16;
    } else {
      cycleOpacity = 0;
    }
    final opacity = (0.55 * cycleOpacity * overallFade).clamp(0.0, 1.0);
    if (opacity <= 0.01) return const SizedBox.shrink();

    final size = cell * 0.92;
    return Positioned(
      left: pos.dx - size / 2,
      top: pos.dy - size / 2,
      child: IgnorePointer(
        child: Opacity(
          opacity: opacity,
          child: Transform.scale(
            scale: press,
            child: SizedBox(
              width: size,
              height: size,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  // The arrow being carried.
                  Positioned.fill(
                    child: DragGhost(tool: ToolType.arrowUp, size: size),
                  ),
                  // The pointing hand, just below the piece.
                  Positioned(
                    right: -size * 0.28,
                    bottom: -size * 0.5,
                    child: Text('👆', style: TextStyle(fontSize: size * 0.7)),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// The floating ghost element — slightly larger than a cell while dragging
  /// (so it feels like a lifted piece), and flying into the cell during the
  /// magnet-snap before the piece pops in.
  Widget _buildGhost() {
    // Determine drag/snap state first — when neither is active (e.g. during
    // the win celebration, when the board is removed) bail out before touching
    // the board key, whose element may be inactive.
    ToolType? tool;
    Offset? globalPos;
    double scale;
    if ((_dragTool != null || _dragPiece != null) && _dragGlobal != null) {
      tool = _activeDragTool;
      globalPos = _dragGlobal;
      scale = 1.2; // lifted piece, larger than the cell
    } else if (_snapKey != null && _snapFrom != null && _snapTo != null) {
      tool = _snapTool ?? _snapPiece?.tool;
      final t = Curves.easeOut.transform(_snapCtrl.value);
      globalPos = Offset.lerp(_snapFrom, _snapTo, t);
      scale = 1.2 - 0.2 * t; // settle to cell size on arrival
    } else {
      return const SizedBox.shrink();
    }
    if (tool == null || globalPos == null) return const SizedBox.shrink();

    final rootBox = _rootKey.currentContext?.findRenderObject() as RenderBox?;
    if (rootBox == null) return const SizedBox.shrink();
    final boardBox = _boardKey.currentContext?.findRenderObject() as RenderBox?;
    final cell = boardBox == null
        ? 58.0
        : GridGeometry(boardBox.size.width, _level!.size).cell;

    final local = rootBox.globalToLocal(globalPos);
    final size = cell * scale;
    return Positioned(
      left: local.dx - size / 2,
      top: local.dy - size / 2,
      child: IgnorePointer(child: DragGhost(tool: tool, size: size)),
    );
  }

  /// Shown instead of the toolbar on levels with no pieces to place.
  Widget _buildEmptyKitHint() {
    return SizedBox(
      height: 64,
      child: Center(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: const [
            Text('👇', style: TextStyle(fontSize: 20)),
            SizedBox(width: 8),
            Text(
              'Press Play!',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: AppColors.textSoft,
                letterSpacing: 0.5,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _goToMenu() => Navigator.of(context).pop(true);

  /// The bottom button area, always occupying [_kFooterHeight] so the grid above
  /// never jumps when the footer swaps between Play, the win pause, and Continue.
  /// Content is bottom-aligned so the button keeps the same baseline throughout.
  Widget _buildFooter() {
    return SizedBox(
      height: _kFooterHeight,
      child: Align(
        alignment: Alignment.bottomCenter,
        child: _footerContent(),
      ),
    );
  }

  Widget _footerContent() {
    if (_status == GameStatus.won) {
      // During the celebration, keep the spot empty; fade Continue in after.
      if (!_celebrationDone) return const SizedBox.shrink();
      return TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeOut,
        builder: (_, t, child) => Opacity(opacity: t, child: child),
        child: _buildContinueCluster(),
      );
    }

    final running = _status == GameStatus.running;
    // Every piece must be placed before Play is enabled (no effect on the
    // no-toolkit Level 1, whose kit is already empty).
    final remaining = _remainingPieces;
    final canPlay = remaining == 0;
    // The hint line is always present (its space is reserved) so the Play button
    // never shifts; only the message changes.
    final hint = running
        ? 'Go!'
        : (canPlay ? 'Ready! Hit Play' : 'Place all elements ($remaining left)');
    final hintColor =
        (canPlay && !running) ? AppColors.completed : AppColors.textSoft;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          hint,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: hintColor,
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: _PillButton(
            label: 'Play',
            icon: Icons.play_arrow_rounded,
            filled: true,
            onTap: (running || !canPlay) ? null : _play,
          ),
        ),
      ],
    );
  }

  /// Post-celebration control: a single Continue (or Back to Menu on the last
  /// level). One clean action — no Replay / Menu.
  Widget _buildContinueCluster() {
    final hasNext =
        widget.levelOverride == null && levelDataFor(_level!.id + 1) != null;
    return SizedBox(
      width: double.infinity,
      child: _PillButton(
        label: hasNext ? 'Continue' : 'Back to Menu',
        icon: hasNext ? Icons.play_arrow_rounded : null,
        filled: true,
        large: true,
        onTap: hasNext ? _goToNextLevel : _goToMenu,
      ),
    );
  }

  /// Headline and accent color for each death cause, so the fail overlay tells
  /// the player exactly why the dot died. The matching icon is drawn by
  /// [_FailIconPainter] in the board's thick-outline style.
  static ({String label, Color color}) _deathInfo(DeathCause? cause) {
    switch (cause) {
      case DeathCause.edge:
        return (label: 'Ran off the edge!', color: Color(0xFFF59E0B));
      case DeathCause.wall:
        return (label: 'Hit a wall!', color: Color(0xFF607D8B));
      case DeathCause.destroyer:
        return (label: 'Destroyed!', color: Color(0xFFEF5350));
      case DeathCause.patrol:
        return (label: 'Caught by patrol!', color: Color(0xFFE53935));
      case DeathCause.gap:
        return (label: 'Fell in a gap!', color: Color(0xFF6D4C41));
      case null:
        return (label: 'Try Again', color: AppColors.ink);
    }
  }

  /// Fail-only overlay — shows WHY the dot died, then "Try Again". Wins
  /// celebrate on the grid instead.
  Widget _buildOverlay() {
    final info = _deathInfo(_deathCause);
    return Positioned.fill(
      child: Container(
        color: Colors.black.withValues(alpha: 0.32),
        alignment: Alignment.center,
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 32),
          padding: const EdgeInsets.fromLTRB(26, 28, 26, 22),
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: AppColors.ink, width: 4),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // The hazard that killed the dot, drawn in the board's icon style.
              SizedBox(
                width: 64,
                height: 64,
                child: CustomPaint(painter: _FailIconPainter(_deathCause)),
              ),
              const SizedBox(height: 10),
              // The death reason — prominent, in its matching color.
              Text(
                info.label,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                  color: info.color,
                ),
              ),
              if (_deathCause != null) ...[
                const SizedBox(height: 4),
                const Text(
                  'Try Again',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textSoft,
                  ),
                ),
              ],
              const SizedBox(height: 20),
              _PillButton(
                label: 'Retry',
                icon: Icons.refresh_rounded,
                filled: true,
                onTap: _retry,
              ),
              const SizedBox(height: 10),
              _PillButton(
                label: 'Clear & Edit',
                filled: false,
                onTap: _clearAll,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPlaceholder() {
    return Scaffold(
      body: Stack(
        children: [
          const Positioned.fill(child: CustomPaint(painter: _BgGridPainter())),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              child: Column(
                children: [
                  Row(
                    children: [
                      BorderedTile(
                        width: 46,
                        onTap: () => Navigator.of(context).pop(),
                        child: const Icon(Icons.arrow_back_rounded,
                            color: AppColors.ink, size: 24),
                      ),
                      const Spacer(),
                      Text('Level ${widget.level.number}',
                          style: const TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w800,
                              color: AppColors.ink)),
                      const Spacer(),
                      const SizedBox(width: 46),
                    ],
                  ),
                  const Expanded(
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.construction_rounded,
                              size: 72, color: AppColors.accent),
                          SizedBox(height: 16),
                          Text('Coming soon',
                              style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.textSoft,
                                  letterSpacing: 1)),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The animated dot, with a subtle pulsing glow ([glow] in 0..1). When
/// [shielded] it wears a glowing cyan protective aura.
class _Dot extends StatelessWidget {
  const _Dot({
    required this.size,
    required this.paused,
    this.glow = 0.5,
    this.shielded = false,
  });

  final double size;
  final bool paused;
  final double glow;
  final bool shielded;

  static const _shield = Color(0xFF38BDF8);

  @override
  Widget build(BuildContext context) {
    final base = paused ? 0.12 : 0.40;
    final span = paused ? 0.10 : 0.30;
    final alpha = base + span * glow;
    final blur = (paused ? 5.0 : 9.0) + 7.0 * glow;
    final dot = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: const RadialGradient(
          center: Alignment(-0.3, -0.35),
          colors: [Color(0xFFFFD89B), AppColors.accent],
          stops: [0.0, 0.85],
        ),
        border: Border.all(color: AppColors.ink, width: 2.5),
        boxShadow: [
          BoxShadow(
            color: AppColors.accent.withValues(alpha: alpha),
            blurRadius: blur,
            spreadRadius: 1 + 1.5 * glow,
          ),
        ],
      ),
    );

    if (!shielded) return dot;

    // Protective cyan bubble around the dot, breathing with the glow pulse.
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          Positioned(
            left: -size * 0.30,
            right: -size * 0.30,
            top: -size * 0.30,
            bottom: -size * 0.30,
            child: Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _shield.withValues(alpha: 0.12 + 0.06 * glow),
                border: Border.all(
                  color: _shield.withValues(alpha: 0.85),
                  width: 2.5,
                ),
                boxShadow: [
                  BoxShadow(
                    color: _shield.withValues(alpha: 0.35 + 0.25 * glow),
                    blurRadius: 10 + 8 * glow,
                    spreadRadius: 1,
                  ),
                ],
              ),
            ),
          ),
          dot,
        ],
      ),
    );
  }
}

/// Thick-bordered pill button matching the menu style.
class _PillButton extends StatelessWidget {
  const _PillButton({
    required this.label,
    required this.filled,
    this.icon,
    this.onTap,
    this.large = false,
  });

  final String label;
  final bool filled;
  final IconData? icon;
  final VoidCallback? onTap;

  /// A bigger, more prominent variant (used for the primary "Next Level").
  final bool large;

  @override
  Widget build(BuildContext context) {
    final disabled = onTap == null;
    final height = large ? 60.0 : 54.0;
    return Opacity(
      opacity: disabled ? 0.45 : 1,
      child: BouncyButton(
        enabled: !disabled,
        onTap: onTap,
        borderRadius: BorderRadius.circular(height / 2),
        rippleColor: filled ? Colors.white : AppColors.coral,
        child: Container(
          height: height,
          padding: const EdgeInsets.symmetric(horizontal: 22),
          decoration: BoxDecoration(
            color: filled ? AppColors.coral : AppColors.card,
            borderRadius: BorderRadius.circular(height / 2),
            border: Border.all(color: AppColors.ink, width: 3),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: large ? 19 : 17,
                  fontWeight: FontWeight.w800,
                  color: filled ? Colors.white : AppColors.ink,
                ),
              ),
              if (icon != null) ...[
                const SizedBox(width: 6),
                Icon(icon,
                    color: filled ? Colors.white : AppColors.ink,
                    size: large ? 28 : 24),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Classic "success checkmark": a ring draws itself, then a tick draws inside.
/// [progress] (0..1) is driven by the win controller — circle over the first
/// half, checkmark over the second.
class _SuccessCheck extends StatelessWidget {
  const _SuccessCheck({required this.progress});

  final double progress;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 76,
      height: 76,
      child: CustomPaint(
        painter: _CheckPainter(
          Curves.easeInOut.transform(progress.clamp(0.0, 1.0)),
          AppColors.coral,
        ),
      ),
    );
  }
}

class _CheckPainter extends CustomPainter {
  _CheckPainter(this.progress, this.color);

  final double progress;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = color;

    // Phase 1 (0–0.5): the ring draws itself from the top, clockwise.
    final circleP = (progress / 0.5).clamp(0.0, 1.0);
    if (circleP > 0) {
      final rect = Rect.fromCircle(
        center: Offset(s / 2, s / 2),
        radius: s / 2 - 4,
      );
      canvas.drawArc(rect, -math.pi / 2, 2 * math.pi * circleP, false, paint);
    }

    // Phase 2 (0.5–1.0): the short leg, then the long leg.
    final checkP = ((progress - 0.5) / 0.5).clamp(0.0, 1.0);
    if (checkP > 0) {
      final p1 = Offset(0.30 * s, 0.52 * s);
      final corner = Offset(0.44 * s, 0.66 * s);
      final p3 = Offset(0.72 * s, 0.37 * s);
      final shortP = (checkP / 0.45).clamp(0.0, 1.0);
      canvas.drawLine(p1, Offset.lerp(p1, corner, shortP)!, paint);
      if (checkP > 0.45) {
        final longP = ((checkP - 0.45) / 0.55).clamp(0.0, 1.0);
        canvas.drawLine(corner, Offset.lerp(corner, p3, longP)!, paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _CheckPainter old) =>
      old.progress != progress || old.color != color;
}

/// Faint background grid, matching the menu screen.
class _BgGridPainter extends CustomPainter {
  static const _cell = 28.0;

  const _BgGridPainter();

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

/// Draws the moving destroyers as red-tinted mines, gliding from their previous
/// cell to their current cell over one beat ([t] 0→1). Used as an overlay above
/// the board so movers animate independently of the grid repaint.
class _MoverPainter extends CustomPainter {
  _MoverPainter({
    required this.movers,
    required this.from,
    required this.t,
    required this.geo,
    required this.glowTick,
    this.planning = false,
  });

  final List<MoverState> movers;
  final List<(int, int)> from;
  final double t;
  final GridGeometry geo;
  final double glowTick;

  /// While planning, draw each mover's patrol path + axis so the player can read
  /// "this mine moves left-right / up-down" before pressing Play.
  final bool planning;

  static const _red = Color(0xFFE53935);

  @override
  void paint(Canvas canvas, Size size) {
    for (var i = 0; i < movers.length; i++) {
      final m = movers[i];
      if (planning) _paintPatrolHint(canvas, m);
      final prev = i < from.length ? from[i] : (m.row, m.col);
      final a = geo.center(prev.$1, prev.$2);
      final b = geo.center(m.row, m.col);
      final c = Offset.lerp(a, b, t)!;
      // Red danger halo so a moving mine reads differently from a static one.
      final pulse = 0.5 + 0.5 * math.sin(glowTick * 2 * math.pi);
      canvas.drawCircle(
        c,
        geo.cell * (0.34 + 0.05 * pulse),
        Paint()
          ..color = _red.withValues(alpha: 0.22 + 0.12 * pulse)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
      );
      paintMineIcon(canvas, c, geo.cell, glowTick);
    }
  }

  /// The dot's start-direction hint (game_grid `_paintStartHint`) mirrored in
  /// red for a moving destroyer: a few fading dots tracing the initial patrol
  /// path plus a small pulsing arrowhead just outside the cell, pointing the way
  /// the mine starts moving. Same size, pulse and positioning as the dot's hint.
  void _paintPatrolHint(Canvas canvas, MoverState m) {
    final r = m.row, c = m.col;
    final dr = m.horizontal ? 0 : m.dir;
    final dc = m.horizontal ? m.dir : 0;
    final center = geo.center(r, c);
    final dir = Offset(dc.toDouble(), dr.toDouble());
    final perp = Offset(-dir.dy, dir.dx);
    final cell = geo.cell;
    // Very gentle opacity breathe only (no scale pulse).
    final breathe = 0.85 + 0.15 * (0.5 + 0.5 * math.sin(glowTick * 2 * math.pi));

    // Lead dots tracing the initial path — small and faint.
    for (var k = 1; k <= 3; k++) {
      final nr = r + dr * k;
      final nc = c + dc * k;
      if (nr < 0 || nr >= geo.n || nc < 0 || nc >= geo.n) break;
      final p = geo.center(nr, nc);
      final fade = 1 - (k - 1) / 3.0; // 1 → .67 → .33
      canvas.drawCircle(
        p,
        cell * 0.07 * fade,
        Paint()..color = _red.withValues(alpha: 0.22 * fade * breathe),
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
      Paint()..color = _red.withValues(alpha: 0.50 * breathe),
    );
  }

  @override
  bool shouldRepaint(covariant _MoverPainter old) =>
      old.t != t ||
      old.glowTick != glowTick ||
      old.movers != movers ||
      old.planning != planning;
}

/// Draws the fail-overlay icon for each [DeathCause] in the board's thick-
/// outline, rounded-cell style — reusing the very hazards seen on the grid (the
/// spiky mine, the gray wall block, the dashed gap) so the player connects the
/// death to the thing that caused it.
class _FailIconPainter extends CustomPainter {
  _FailIconPainter(this.cause);

  final DeathCause? cause;

  // Grid-matched cell colors (see game_grid `_C` / `_paintBase`).
  static const _wallFill = Color(0xFF78909C);
  static const _wallBorder = Color(0xFF5C6B73);
  static const _mineFill = Color(0xFFEF5350);
  static const _mineBorder = Color(0xFFC62828);

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide;
    final c = Offset(size.width / 2, size.height / 2);
    final pad = s * 0.08;
    final box = Rect.fromLTWH(pad, pad, s - pad * 2, s - pad * 2);

    switch (cause) {
      case DeathCause.destroyer:
        _cell(canvas, box, _mineFill, _mineBorder);
        paintMineIcon(canvas, c, s * 1.35, 0);
      case DeathCause.patrol:
        _cell(canvas, box, _mineFill, _mineBorder);
        paintMineIcon(canvas, c, s * 1.25, 0);
        _patrolArrows(canvas, c, s); // a moving mine — patrol axis badge
      case DeathCause.wall:
        _cell(canvas, box, _wallFill, _wallBorder);
        _crack(canvas, box);
      case DeathCause.gap:
        _cell(canvas, box, AppColors.background, AppColors.textSoft,
            dashed: true);
        _downArrow(canvas, c, s, const Color(0xFF6D4C41));
      case DeathCause.edge:
      case null:
        _edge(canvas, box, s);
    }
  }

  /// A rounded, thick-outlined cell — the board's signature look.
  void _cell(Canvas canvas, Rect rect, Color fill, Color border,
      {bool dashed = false}) {
    final rrect =
        RRect.fromRectAndRadius(rect, Radius.circular(rect.width * 0.22));
    canvas.drawRRect(rrect, Paint()..color = fill);
    final bp = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = rect.width * 0.075
      ..strokeJoin = StrokeJoin.round
      ..color = border;
    if (dashed) {
      _dashRRect(canvas, rrect, bp);
    } else {
      canvas.drawRRect(rrect, bp);
    }
  }

  void _dashRRect(Canvas canvas, RRect rrect, Paint p) {
    final path = Path()..addRRect(rrect);
    const dash = 5.0, gap = 4.0;
    for (final m in path.computeMetrics()) {
      var d = 0.0;
      while (d < m.length) {
        canvas.drawPath(m.extractPath(d, math.min(d + dash, m.length)), p);
        d += dash + gap;
      }
    }
  }

  /// A jagged lightning crack across a wall block.
  void _crack(Canvas canvas, Rect box) {
    final w = box.width, h = box.height;
    final p = Path()
      ..moveTo(box.left + w * 0.52, box.top + h * 0.16)
      ..lineTo(box.left + w * 0.38, box.top + h * 0.46)
      ..lineTo(box.left + w * 0.56, box.top + h * 0.52)
      ..lineTo(box.left + w * 0.40, box.top + h * 0.86);
    canvas.drawPath(
      p,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = box.width * 0.09
        ..strokeJoin = StrokeJoin.round
        ..strokeCap = StrokeCap.round
        ..color = const Color(0xFF37474F),
    );
  }

  /// A small red double-headed horizontal arrow under the mine — "this one
  /// moves" (the patrol axis), echoing the planning-phase hint.
  void _patrolArrows(Canvas canvas, Offset c, double s) {
    final y = c.dy + s * 0.30;
    final half = s * 0.26;
    final p = Paint()
      ..color = _mineBorder
      ..strokeWidth = s * 0.05
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;
    final left = Offset(c.dx - half, y);
    final right = Offset(c.dx + half, y);
    canvas.drawLine(left, right, p);
    final head = s * 0.10;
    canvas.drawLine(left, left + Offset(head, -head), p);
    canvas.drawLine(left, left + Offset(head, head), p);
    canvas.drawLine(right, right + Offset(-head, -head), p);
    canvas.drawLine(right, right + Offset(-head, head), p);
  }

  /// A downward arrow falling into the (dashed) gap.
  void _downArrow(Canvas canvas, Offset c, double s, Color color) {
    final p = Paint()
      ..color = color
      ..strokeWidth = s * 0.09
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;
    final top = Offset(c.dx, c.dy - s * 0.22);
    final tip = Offset(c.dx, c.dy + s * 0.20);
    canvas.drawLine(top, tip, p);
    final head = s * 0.16;
    canvas.drawLine(tip, tip + Offset(-head, -head), p);
    canvas.drawLine(tip, tip + Offset(head, -head), p);
  }

  /// The dot leaving the board: a ball inside the cell and an arrow piercing out
  /// through the right edge.
  void _edge(Canvas canvas, Rect box, double s) {
    // Cell sits on the left, leaving room for the arrow to exit on the right.
    final cellRect =
        Rect.fromLTWH(box.left, box.top, box.width * 0.66, box.height);
    _cell(canvas, cellRect, AppColors.card, AppColors.ink);

    final cy = cellRect.center.dy;
    // The dot.
    canvas.drawCircle(
      Offset(cellRect.left + cellRect.width * 0.40, cy),
      s * 0.11,
      Paint()..color = AppColors.accent,
    );
    // Arrow shaft + head crossing the cell's right wall and exiting.
    const amber = Color(0xFFF59E0B);
    final p = Paint()
      ..color = amber
      ..strokeWidth = s * 0.085
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;
    final shaftStart = Offset(cellRect.right - s * 0.06, cy);
    final tip = Offset(box.right + s * 0.04, cy);
    canvas.drawLine(shaftStart, tip, p);
    final head = s * 0.14;
    canvas.drawLine(tip, tip + Offset(-head, -head), p);
    canvas.drawLine(tip, tip + Offset(-head, head), p);
  }

  @override
  bool shouldRepaint(covariant _FailIconPainter old) => old.cause != cause;
}
