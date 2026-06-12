import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/level_definitions.dart';
import '../models/game_state.dart';
import '../models/grid_cell.dart';
import '../models/level.dart';
import '../models/level_data.dart';
import '../theme/app_theme.dart';
import '../widgets/game_grid.dart';
import '../widgets/game_toolbar.dart';
import '../widgets/top_bar.dart';

/// Milliseconds between dot movement ticks.
const _tickMs = 400;

/// The core game screen. For levels with a definition it is fully playable;
/// otherwise it shows a "coming soon" placeholder.
class GameScreen extends StatefulWidget {
  const GameScreen({super.key, required this.level});

  final Level level;

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen>
    with SingleTickerProviderStateMixin {
  LevelData? _level;

  final Map<int, PlacedElement> _placed = {};
  Map<ToolType, int> _kit = {};
  ToolType? _selected;

  GameStatus _status = GameStatus.planning;
  late DotState _dot;
  final Set<int> _trail = {};
  String? _failReason;

  Timer? _timer;
  late final AnimationController _dotCtrl;
  (int, int) _animFrom = (0, 0);
  (int, int) _animTo = (0, 0);

  /// Board RenderBox key, used to convert drag globals to local cell coords.
  final GlobalKey _boardKey = GlobalKey();

  /// Cell currently hovered during a valid drag, and the tool being dragged.
  (int, int)? _hoverCell;
  ToolType? _hoverTool;

  @override
  void initState() {
    super.initState();
    _dotCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 320),
    );
    _level = levelDataFor(widget.level.number);
    if (_level != null) {
      _kit = {for (final e in _level!.toolkit) e.type: e.count};
      _selected = _level!.toolkit.isNotEmpty ? _level!.toolkit.first.type : null;
      _resetDot();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _dotCtrl.dispose();
    super.dispose();
  }

  int _idx(int r, int c) => r * _level!.size + c;

  int get _revision => _placed.length * 10000 + _trail.length;

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

  // ----- placement -----

  void _onBoardTapUp(TapUpDetails d, GridGeometry geo) {
    if (_status != GameStatus.planning) return;
    final cell = geo.cellAt(d.localPosition);
    if (cell == null) return;
    final (r, c) = cell;
    final key = _idx(r, c);

    final existing = _placed[key];
    if (existing != null) {
      setState(() {
        _placed.remove(key);
        _kit[existing.tool] = (_kit[existing.tool] ?? 0) + 1;
      });
      return;
    }

    final tool = _selected;
    if (tool == null) return;
    if (_level!.baseTypeAt(r, c) != CellType.empty) return;
    if ((_kit[tool] ?? 0) <= 0) return;

    setState(() {
      _placed[key] = PlacedElement(
        type: tool.placedType,
        tool: tool,
        direction: tool.direction,
      );
      _kit[tool] = _kit[tool]! - 1;
    });
  }

  // ----- drag & drop -----

  /// Convert a global drag position to a board cell, or null if off-grid.
  (int, int)? _cellFromGlobal(Offset global) {
    final box = _boardKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return null;
    return GridGeometry(box.size.width, _level!.size)
        .cellAt(box.globalToLocal(global));
  }

  bool _canPlace((int, int) cell, ToolType tool) {
    if (_status != GameStatus.planning) return false;
    final (r, c) = cell;
    if (_level!.baseTypeAt(r, c) != CellType.empty) return false;
    if (_placed.containsKey(_idx(r, c))) return false;
    return (_kit[tool] ?? 0) > 0;
  }

  /// Live preview update while a toolkit item is dragged over the board.
  void _onDragMove(ToolType tool, Offset global) {
    final cell = _cellFromGlobal(global);
    final valid = cell != null && _canPlace(cell, tool);
    setState(() {
      _hoverCell = valid ? cell : null;
      _hoverTool = valid ? tool : null;
    });
  }

  void _onDragDrop(ToolType tool, Offset global) {
    final cell = _cellFromGlobal(global);
    if (cell != null && _canPlace(cell, tool)) {
      final (r, c) = cell;
      setState(() {
        _placed[_idx(r, c)] = PlacedElement(
          type: tool.placedType,
          tool: tool,
          direction: tool.direction,
        );
        _kit[tool] = _kit[tool]! - 1;
      });
      HapticFeedback.lightImpact();
    }
    setState(() {
      _hoverCell = null;
      _hoverTool = null;
    });
  }

  /// Dragging a placed piece off the grid removes it (refunds the toolkit).
  void _onPlacedDragEnd(int key, DraggableDetails details) {
    if (_status != GameStatus.planning) return;
    final box = _boardKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return;
    final local = box.globalToLocal(details.offset);
    final side = box.size.width;
    final offGrid =
        local.dx < 0 || local.dy < 0 || local.dx > side || local.dy > side;
    if (!offGrid) return;
    final piece = _placed[key];
    if (piece == null) return;
    setState(() {
      _placed.remove(key);
      _kit[piece.tool] = (_kit[piece.tool] ?? 0) + 1;
    });
    HapticFeedback.lightImpact();
  }

  // ----- run loop -----

  void _play() {
    if (_status == GameStatus.running) return;
    setState(() {
      _resetDot();
      _status = GameStatus.running;
    });
    _timer = Timer.periodic(const Duration(milliseconds: _tickMs), (_) => _beat());
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
    setState(() {
      _dot.r = nr;
      _dot.c = nc;
      _trail.add(_idx(nr, nc));
    });
    _glide(fromR, fromC, nr, nc);

    final base = _level!.baseTypeAt(nr, nc);
    if (base == CellType.gap) {
      _die('The dot fell into a hole.');
      return;
    }
    if (base == CellType.destroyer || base == CellType.movingDestroyer) {
      _die('The dot was destroyed!');
      return;
    }

    final piece = _placed[_idx(nr, nc)];
    if (piece != null) {
      switch (piece.type) {
        case PlacedType.arrow:
          setState(() => _dot.dir = piece.direction!);
        case PlacedType.pause:
          setState(() => _dot.pause = 2);
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
      });
      _jump(r, c);
      return;
    }
  }

  void _win() {
    _timer?.cancel();
    _timer = null;
    Future.delayed(const Duration(milliseconds: 280), () {
      if (!mounted) return;
      setState(() => _status = GameStatus.won);
    });
  }

  void _die(String msg) {
    _timer?.cancel();
    _timer = null;
    _failReason = msg;
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
      body: Stack(
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
                  Expanded(child: Center(child: _buildBoard())),
                  const SizedBox(height: 16),
                  GameToolbar(
                    tools: _level!.toolkit.map((e) => e.type).toList(),
                    counts: _kit,
                    selected: _selected,
                    enabled: _status != GameStatus.running,
                    onSelect: (t) => setState(() => _selected = t),
                  ),
                  const SizedBox(height: 16),
                  _buildFooter(),
                ],
              ),
            ),
          ),
          if (_status == GameStatus.won || _status == GameStatus.lost)
            _buildOverlay(),
        ],
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
      ],
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

          return DragTarget<ToolType>(
            onWillAcceptWithDetails: (d) {
              final cell = _cellFromGlobal(d.offset);
              return cell != null && _canPlace(cell, d.data);
            },
            onMove: (d) => _onDragMove(d.data, d.offset),
            onLeave: (_) => setState(() {
              _hoverCell = null;
              _hoverTool = null;
            }),
            onAcceptWithDetails: (d) => _onDragDrop(d.data, d.offset),
            builder: (context, candidate, rejected) {
              return GestureDetector(
                key: const ValueKey('gameBoard'),
                onTapUp: (d) => _onBoardTapUp(d, geo),
                child: Stack(
                  key: _boardKey,
                  children: [
                    RepaintBoundary(
                      child: CustomPaint(
                        size: Size.square(side),
                        painter: GameGridPainter(
                          level: _level!,
                          placed: _placed,
                          trail: _trail,
                          revision: _revision,
                          previewKey: previewKey,
                          previewTool: _hoverTool,
                        ),
                      ),
                    ),
                    ..._buildPlacedDragHandles(geo),
                    Positioned.fill(
                      child: AnimatedBuilder(
                        animation: _dotCtrl,
                        builder: (_, _) {
                          final from = geo.center(_animFrom.$1, _animFrom.$2);
                          final to = geo.center(_animTo.$1, _animTo.$2);
                          final pos = Offset.lerp(from, to, _dotCtrl.value)!;
                          final d = geo.cell * 0.46;
                          return Transform.translate(
                            offset: Offset(pos.dx - d / 2, pos.dy - d / 2),
                            child: Align(
                              alignment: Alignment.topLeft,
                              child: _Dot(size: d, paused: _dot.pause > 0),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }

  /// Transparent, draggable handles over each placed piece: long-press-drag off
  /// the grid to remove, or tap to remove.
  List<Widget> _buildPlacedDragHandles(GridGeometry geo) {
    if (_status != GameStatus.planning) return const [];
    final cs = geo.cell;
    return _placed.entries.map((e) {
      final r = e.key ~/ _level!.size;
      final c = e.key % _level!.size;
      final center = geo.center(r, c);
      return Positioned(
        left: center.dx - cs / 2,
        top: center.dy - cs / 2,
        width: cs,
        height: cs,
        child: LongPressDraggable<int>(
          data: e.key,
          dragAnchorStrategy: pointerDragAnchorStrategy,
          feedback: DragGhost(tool: e.value.tool, size: cs * 0.8),
          childWhenDragging: const SizedBox.shrink(),
          onDragEnd: (d) => _onPlacedDragEnd(e.key, d),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => _removePlaced(e.key),
            child: const SizedBox.expand(),
          ),
        ),
      );
    }).toList();
  }

  void _removePlaced(int key) {
    if (_status != GameStatus.planning) return;
    final piece = _placed[key];
    if (piece == null) return;
    setState(() {
      _placed.remove(key);
      _kit[piece.tool] = (_kit[piece.tool] ?? 0) + 1;
    });
  }

  Widget _buildFooter() {
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

  Widget _buildOverlay() {
    final won = _status == GameStatus.won;
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
              Text(won ? '🎉' : '💥', style: const TextStyle(fontSize: 48)),
              const SizedBox(height: 8),
              Text(
                won ? 'Level Complete!' : 'Try Again',
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: AppColors.ink,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                won ? '${_level!.title} solved.' : (_failReason ?? ''),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 14,
                  color: AppColors.textSoft,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 20),
              if (won) ...[
                _PillButton(
                  label: 'Back to Menu',
                  filled: true,
                  onTap: () => Navigator.of(context).pop(true),
                ),
                const SizedBox(height: 10),
                _PillButton(
                  label: 'Replay',
                  filled: false,
                  onTap: _retry,
                ),
              ] else ...[
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

/// The animated dot.
class _Dot extends StatelessWidget {
  const _Dot({required this.size, required this.paused});

  final double size;
  final bool paused;

  @override
  Widget build(BuildContext context) {
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
            color: AppColors.accent.withValues(alpha: paused ? 0.15 : 0.55),
            blurRadius: paused ? 6 : 12,
            spreadRadius: paused ? 0 : 1,
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
  });

  final String label;
  final bool filled;
  final IconData? icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final disabled = onTap == null;
    return Opacity(
      opacity: disabled ? 0.45 : 1,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          height: 54,
          padding: const EdgeInsets.symmetric(horizontal: 22),
          decoration: BoxDecoration(
            color: filled ? AppColors.coral : AppColors.card,
            borderRadius: BorderRadius.circular(27),
            border: Border.all(color: AppColors.ink, width: 3),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  color: filled ? Colors.white : AppColors.ink,
                ),
              ),
              if (icon != null) ...[
                const SizedBox(width: 6),
                Icon(icon,
                    color: filled ? Colors.white : AppColors.ink, size: 24),
              ],
            ],
          ),
        ),
      ),
    );
  }
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
