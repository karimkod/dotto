import 'package:flutter/material.dart';

import '../data/levels.dart';
import '../models/level.dart';
import '../theme/app_theme.dart';
import '../widgets/level_card.dart';
import '../widgets/play_button.dart';
import '../widgets/top_bar.dart';
import 'game_screen.dart';

/// Vertical slot height per level node on the path.
const double _slotHeight = 120;

/// The Dotto main menu: top bar, wordmark, a winding scrollable level path,
/// and a fixed play button for the current level.
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
    final index = _levels.indexOf(_currentLevel);
    final target = (index * _slotHeight) -
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
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => GameScreen(level: level)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final current = _currentLevel;

    return Scaffold(
      body: SafeArea(
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
    );
  }

  Widget _buildPath(Level current) {
    return SingleChildScrollView(
      controller: _scrollController,
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Stack(
        children: [
          Positioned.fill(
            child: CustomPaint(painter: _DashedLinePainter()),
          ),
          Column(
            children: [
              for (var i = 0; i < _levels.length; i++)
                _LevelSlot(
                  level: _levels[i],
                  isCurrent: _levels[i].id == current.id,
                  // Alternate left/right of center for a winding path.
                  align: i.isEven ? -0.42 : 0.42,
                  onTap: () => _openLevel(_levels[i]),
                ),
            ],
          ),
        ],
      ),
    );
  }

  /// Floating left-side shortcuts: daily puzzle + a locked "coming soon" slot.
  Widget _buildSideIcons() {
    return Positioned(
      left: 0,
      top: 8,
      child: Column(
        children: [
          _SideIcon(
            icon: Icons.calendar_today_rounded,
            label: 'Daily',
            tint: AppColors.accent,
            onTap: () {},
          ),
          const SizedBox(height: 12),
          _SideIcon(
            icon: Icons.lock_clock_rounded,
            label: 'Soon',
            tint: AppColors.locked,
            locked: true,
          ),
        ],
      ),
    );
  }
}

/// One vertical slot on the path holding a single level card, offset left or
/// right of the center line.
class _LevelSlot extends StatelessWidget {
  const _LevelSlot({
    required this.level,
    required this.isCurrent,
    required this.align,
    required this.onTap,
  });

  final Level level;
  final bool isCurrent;
  final double align;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: _slotHeight,
      child: Align(
        alignment: Alignment(align, 0),
        child: LevelCard(
          level: level,
          isCurrent: isCurrent,
          onTap: onTap,
        ),
      ),
    );
  }
}

/// Small labelled icon button used for the left-side shortcuts.
class _SideIcon extends StatelessWidget {
  const _SideIcon({
    required this.icon,
    required this.label,
    required this.tint,
    this.onTap,
    this.locked = false,
  });

  final IconData icon;
  final String label;
  final Color tint;
  final VoidCallback? onTap;
  final bool locked;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: locked ? 0.55 : 1,
      child: GestureDetector(
        onTap: locked ? null : onTap,
        child: Column(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: AppColors.card,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.border),
                boxShadow: AppTheme.softShadow(y: 3, blur: 8),
              ),
              child: Icon(icon, color: tint, size: 22),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: AppColors.textSoft,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Paints the dashed vertical line running down the center of the path.
class _DashedLinePainter extends CustomPainter {
  static const _dash = 8.0;
  static const _gap = 7.0;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppColors.locked.withValues(alpha: 0.35)
      ..strokeWidth = 3
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
