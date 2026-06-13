import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../audio/sfx.dart';
import '../data/level_definitions.dart';
import '../models/game_state.dart';
import '../models/grid_cell.dart';
import '../models/level.dart';
import '../models/level_data.dart';
import '../progress/progress_store.dart';
import '../theme/app_theme.dart';
import '../widgets/feedback_dialog.dart';
import '../widgets/game_grid.dart';
import '../widgets/game_toolbar.dart';
import '../widgets/top_bar.dart';

/// Milliseconds between dot movement ticks.
const _tickMs = 400;

/// The core game screen. For levels with a definition it is fully playable;
/// otherwise it shows a "coming soon" placeholder.
///
/// Drag-and-drop is implemented manually with pan gestures on a top-level
/// [GestureDetector] (no [DragTarget]) so all coordinate math is under our
/// control — reliable across platforms including web.
class GameScreen extends StatefulWidget {
  const GameScreen({super.key, required this.level});

  final Level level;

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
  String? _failReason;

  Timer? _timer;
  late final AnimationController _dotCtrl; // per-step glide + squish
  late final Animation<double> _dotScale; // arrival squish
  late final AnimationController _glowCtrl; // continuous fx driver
  (int, int) _animFrom = (0, 0);
  (int, int) _animTo = (0, 0);

  // Visual effect state, advanced each frame in [_onFxTick].
  final Map<int, double> _placeAnim = {}; // cell → pop-in progress
  final List<FadingPiece> _removing = []; // shrinking-away pieces
  final Map<int, double> _cellGlow = {}; // cell → glow intensity
  final Map<int, Color> _cellGlowColor = {};
  final Map<int, double> _cellPulse = {}; // cell → neighbor ripple progress

  // Win celebration: grid fades out, a full celebration screen fades in.
  late final AnimationController _winCtrl;
  bool _celebrationDone = false;
  String _winMessage = '';

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
    _level = levelDataFor(widget.level.number);
    if (_level != null) {
      _kit = {for (final e in _level!.toolkit) e.type: e.count};
      for (final e in _level!.toolkit) {
        _toolKeys[e.type] = GlobalKey();
      }
      for (final a in _level!.forcedArrows) {
        _forced[a.r * _level!.size + a.c] = PlacedElement(
          type: PlacedType.arrow,
          tool: a.dir.arrowTool,
          direction: a.dir,
        );
      }
      _selected = _level!.toolkit.isNotEmpty ? _level!.toolkit.first.type : null;
      _resetDot();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _dotCtrl.dispose();
    _glowCtrl.dispose();
    _snapCtrl.dispose();
    _winCtrl.dispose();
    super.dispose();
  }

  int _idx(int r, int c) => r * _level!.size + c;

  int get _revision => _placed.length * 10000 + _trail.length;

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
        _commitPlace(
          key,
          PlacedElement(
              type: tool.placedType, tool: tool, direction: tool.direction),
          decrementKit: true,
        );
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
    _commitPlace(
      _idx(cell.$1, cell.$2),
      PlacedElement(type: tool.placedType, tool: tool, direction: tool.direction),
      decrementKit: true,
    );
  }

  void _removeAt(int key) {
    final piece = _placed[key];
    if (piece == null) return;
    setState(() {
      _placed.remove(key);
      _placeAnim.remove(key);
      _removing.add(FadingPiece(key, piece.tool, piece.direction)); // shrink-out
      _kit[piece.tool] = (_kit[piece.tool] ?? 0) + 1;
    });
    Sfx.remove();
    HapticFeedback.lightImpact();
  }

  // ----- run loop -----

  void _play() {
    if (_status == GameStatus.running) return;
    Sfx.click();
    setState(() {
      _resetDot();
      _status = GameStatus.running;
    });
    _timer =
        Timer.periodic(const Duration(milliseconds: _tickMs), (_) => _beat());
  }

  void _beat() {
    if (_status != GameStatus.running) return;
    final size = _level!.size;

    if (_dot.pause > 0) {
      setState(() => _dot.pause--);
      return;
    }

    final (dr, dc) = _dot.dir.delta;
    final nr = _dot.r + dr;
    final nc = _dot.c + dc;

    if (nr < 0 || nr >= size || nc < 0 || nc >= size) {
      _fail('The dot ran off the edge.');
      return;
    }
    if (_level!.baseTypeAt(nr, nc) == CellType.wall) {
      _fail('The dot hit a wall.');
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

    final base = _level!.baseTypeAt(nr, nc);
    if (base == CellType.gap) {
      _die('The dot fell into a hole.');
      return;
    }
    if (base == CellType.destroyer || base == CellType.movingDestroyer) {
      _die('The dot was destroyed!');
      return;
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
        case PlacedType.teleporter:
          _teleport();
      }
    }

    if (_level!.baseTypeAt(_dot.r, _dot.c) == CellType.exit) {
      _win();
    }
  }

  void _teleport() {
    final size = _level!.size;
    for (final entry in _placed.entries) {
      if (entry.value.type != PlacedType.teleporter) continue;
      final r = entry.key ~/ size;
      final c = entry.key % size;
      if (r == _dot.r && c == _dot.c) continue;
      setState(() {
        _dot.r = r;
        _dot.c = c;
        _trail.add(entry.key);
        _glow(entry.key, const Color(0xFFFF8A65), 1.0);
      });
      _jump(r, c);
      Sfx.teleport();
      return;
    }
  }

  void _win() {
    _timer?.cancel();
    _timer = null;
    Sfx.exit();
    // Record completion → unlocks the next level.
    ProgressStore.markCompleted(_level!.id);
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

  void _die(String msg) {
    _timer?.cancel();
    _timer = null;
    _failReason = msg;
    Sfx.die();
    Future.delayed(const Duration(milliseconds: 280), () {
      if (!mounted) return;
      setState(() => _status = GameStatus.lost);
    });
  }

  void _fail(String msg) {
    _timer?.cancel();
    _timer = null;
    _failReason = msg;
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
                    Text(
                      _level!.tip,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 13,
                        height: 1.3,
                        color: AppColors.textSoft,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 12),
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
                        onSelect: (t) => setState(() => _selected = t),
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
                        placed: _placed,
                        trail: _trail,
                        revision: _revision,
                        placeAnim: _placeAnim,
                        removing: _removing,
                        forced: _forced,
                        cellGlow: _cellGlow,
                        cellGlowColor: _cellGlowColor,
                        cellPulse: _cellPulse,
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
                            ),
                          ),
                        ),
                      );
                    },
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

  Widget _buildFooter() {
    if (_status == GameStatus.won) {
      // During the celebration, keep the spot empty; fade Continue in after.
      if (!_celebrationDone) return const SizedBox(height: 54);
      return TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeOut,
        builder: (_, t, child) => Opacity(opacity: t, child: child),
        child: _buildContinueCluster(),
      );
    }

    final running = _status == GameStatus.running;
    return Row(
      children: [
        _PillButton(
          label: 'Reset',
          filled: false,
          onTap: running ? null : _clearAll,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _PillButton(
            label: 'Play',
            icon: Icons.play_arrow_rounded,
            filled: true,
            onTap: running ? null : _play,
          ),
        ),
      ],
    );
  }

  /// Post-celebration control: a single Continue (or Back to Menu on the last
  /// level). One clean action — no Replay / Menu.
  Widget _buildContinueCluster() {
    final hasNext = levelDataFor(_level!.id + 1) != null;
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

  /// Fail-only overlay ("Try Again"). Wins celebrate on the grid instead.
  Widget _buildOverlay() {
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
              const Text('💥', style: TextStyle(fontSize: 48)),
              const SizedBox(height: 8),
              const Text(
                'Try Again',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: AppColors.ink,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                _failReason ?? '',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 14,
                  color: AppColors.textSoft,
                  fontWeight: FontWeight.w600,
                ),
              ),
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

/// The animated dot, with a subtle pulsing glow ([glow] in 0..1).
class _Dot extends StatelessWidget {
  const _Dot({required this.size, required this.paused, this.glow = 0.5});

  final double size;
  final bool paused;
  final double glow;

  @override
  Widget build(BuildContext context) {
    final base = paused ? 0.12 : 0.40;
    final span = paused ? 0.10 : 0.30;
    final alpha = base + span * glow;
    final blur = (paused ? 5.0 : 9.0) + 7.0 * glow;
    return Container(
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
      child: GestureDetector(
        onTap: onTap,
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
