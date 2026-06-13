import 'package:flutter/material.dart';

import '../data/levels.dart';
import '../models/level.dart';
import '../theme/app_theme.dart';
import '../widgets/level_card.dart';
import '../widgets/play_button.dart';
import '../widgets/top_bar.dart';
import 'game_screen.dart';

/// Vertical slot height per level node on the path.
const double _slotHeight = 116;

/// The Dotto main menu: a grid-patterned background, top bar, wordmark, a
/// vertical scrollable level path (level 1 at the bottom), and a fixed play
/// button for the current level.
class MenuScreen extends StatefulWidget {
  const MenuScreen({super.key});

  @override
  State<MenuScreen> createState() => _MenuScreenState();
}

class _MenuScreenState extends State<MenuScreen> {
  late List<Level> _levels;
  final ScrollController _scrollController = ScrollController();
  final int _hintCount = 3;

  @override
  void initState() {
    super.initState();
    _levels = buildInitialLevels();
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToCurrent());
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  /// The next level to play: first unlocked (non-completed), else the last
  /// completed one as a fallback.
  Level get _currentLevel {
    return _levels.firstWhere(
      (l) => l.isUnlocked,
      orElse: () => _levels.lastWhere(
        (l) => l.isCompleted,
        orElse: () => _levels.first,
      ),
    );
  }

  void _scrollToCurrent() {
    if (!_scrollController.hasClients) return;
    // The path is rendered top-to-bottom as level 20 → level 1, so the visual
    // row of a level is its position counted from the end of the list.
    final visualRow = _levels.length - 1 - _levels.indexOf(_currentLevel);
    final target = (visualRow * _slotHeight) -
        (_scrollController.position.viewportDimension / 2) +
        (_slotHeight / 2);
    final clamped = target.clamp(
      _scrollController.position.minScrollExtent,
      _scrollController.position.maxScrollExtent,
    );
    _scrollController.animateTo(
      clamped,
      duration: const Duration(milliseconds: 600),
      curve: Curves.easeOutCubic,
    );
  }

  void _openLevel(Level level) {
    if (level.isLocked) return;
    Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => GameScreen(level: level)))
        .then((_) {
      // Reflect any newly-unlocked levels on return.
      if (!mounted) return;
      setState(() => _levels = buildInitialLevels());
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToCurrent());
    });
  }

  @override
  Widget build(BuildContext context) {
    final current = _currentLevel;

    return Scaffold(
      body: Stack(
        children: [
          // Subtle grid pattern across the whole background.
          const Positioned.fill(child: CustomPaint(painter: _GridPainter())),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              child: Column(
                children: [
                  TopBar(hintCount: _hintCount, onHints: () {}),
                  const SizedBox(height: 18),
                  Text('Dotto', style: AppTheme.title),
                  const SizedBox(height: 16),
                  Expanded(
                    child: Stack(
                      children: [
                        _buildPath(current),
                        _buildSideIcons(),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  PlayButton(level: current, onPlay: () => _openLevel(current)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPath(Level current) {
    return ShaderMask(
      // Fade levels in/out at the top and bottom edges so they don't hard-cut.
      shaderCallback: (Rect bounds) {
        return const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.transparent,
            Colors.white,
            Colors.white,
            Colors.transparent,
          ],
          stops: [0.0, 0.07, 0.93, 1.0],
        ).createShader(bounds);
      },
      blendMode: BlendMode.dstIn,
      child: ScrollConfiguration(
        behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
        child: SingleChildScrollView(
        controller: _scrollController,
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Stack(
          children: [
            Positioned.fill(
              child: CustomPaint(painter: _DashedLinePainter()),
            ),
            Column(
              // Level 1 sits at the bottom, level 20 at the top — climb upward.
              // Cards stay centered on the dashed line.
              children: [
                for (var i = 0; i < _levels.length; i++)
                  () {
                    final level = _levels[_levels.length - 1 - i];
                    return _LevelSlot(
                      level: level,
                      isCurrent: level.id == current.id,
                      onTap: () => _openLevel(level),
                    );
                  }(),
              ],
            ),
          ],
        ),
        ),
      ),
    );
  }

  /// Circular shortcuts sitting to the LEFT of the dashed line: a locked daily
  /// challenge and a calendar.
  Widget _buildSideIcons() {
    return Positioned.fill(
      child: Align(
        alignment: Alignment.centerLeft,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _SideIcon(icon: Icons.lock_outline_rounded, locked: true),
            const SizedBox(height: 14),
            _SideIcon(icon: Icons.calendar_today_rounded, onTap: () {}),
          ],
        ),
      ),
    );
  }
}

/// One vertical slot on the path holding a single, centered level card.
class _LevelSlot extends StatelessWidget {
  const _LevelSlot({
    required this.level,
    required this.isCurrent,
    required this.onTap,
  });

  final Level level;
  final bool isCurrent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: _slotHeight,
      child: Center(
        child: LevelCard(
          level: level,
          isCurrent: isCurrent,
          onTap: onTap,
        ),
      ),
    );
  }
}

/// Circular, thick-outlined shortcut icon for the left rail.
class _SideIcon extends StatelessWidget {
  const _SideIcon({
    required this.icon,
    this.onTap,
    this.locked = false,
  });

  final IconData icon;
  final VoidCallback? onTap;
  final bool locked;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: locked ? null : onTap,
      child: Container(
        width: 50,
        height: 50,
        decoration: BoxDecoration(
          color: locked ? const Color(0xFFEDEBE7) : AppColors.card,
          shape: BoxShape.circle,
          border: Border.all(
            color: locked
                ? AppColors.locked.withValues(alpha: 0.55)
                : AppColors.ink,
            width: 3,
          ),
        ),
        child: Icon(
          icon,
          color: locked ? AppColors.locked : AppColors.ink,
          size: 22,
        ),
      ),
    );
  }
}

/// Paints the thick dark dashed vertical line down the center of the path.
class _DashedLinePainter extends CustomPainter {
  static const _dash = 10.0;
  static const _gap = 8.0;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppColors.ink
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;

    final x = size.width / 2;
    var y = 0.0;
    while (y < size.height) {
      canvas.drawLine(Offset(x, y), Offset(x, y + _dash), paint);
      y += _dash + _gap;
    }
  }

  @override
  bool shouldRepaint(covariant _DashedLinePainter oldDelegate) => false;
}

/// Paints a faint square grid across the background.
class _GridPainter extends CustomPainter {
  static const _cell = 28.0;

  const _GridPainter();

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
  bool shouldRepaint(covariant _GridPainter oldDelegate) => false;
}
