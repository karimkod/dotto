import 'package:flutter/material.dart';

import '../app_routes.dart';
import '../data/levels.dart';
import '../models/level.dart';
import '../theme/app_theme.dart';
import '../utils/dev_mode.dart';
import '../widgets/level_card.dart';
import '../widgets/play_button.dart';
import '../widgets/top_bar.dart';
import 'game_screen.dart';
import 'level_designer_screen.dart';

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

class _MenuScreenState extends State<MenuScreen> with RouteAware {
  late List<Level> _levels;
  final ScrollController _scrollController = ScrollController();

  /// Marks whichever slot is currently the one to play, so the scroll can find
  /// it by layout instead of by arithmetic. It moves to a new slot whenever
  /// progress advances.
  final GlobalKey _currentSlotKey = GlobalKey();
  final int _hintCount = 3;

  @override
  void initState() {
    super.initState();
    _levels = buildInitialLevels();
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToCurrent());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    // Widget tests pump this screen without the observer installed, so only
    // subscribe when there is a page route to subscribe to.
    if (route is PageRoute) routeObserver.subscribe(this, route);
  }

  /// Called when whatever was covering the menu is gone — which, however deep
  /// into the game the player went, is the one moment progress can have changed.
  @override
  void didPopNext() => _refresh();

  void _refresh() {
    if (!mounted) return;
    setState(() => _levels = buildInitialLevels());
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToCurrent());
  }

  @override
  void dispose() {
    routeObserver.unsubscribe(this);
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

  /// Centre the path on the level the player should play next.
  ///
  /// This asks the laid-out slot where it is rather than deriving a row from
  /// its index: the column is not a uniform stack of slots — a world banner
  /// sits under the first level of each world — so counting levels and
  /// multiplying by [_slotHeight] under-measures by every banner above the
  /// target, and lands the view short of it. Anything else added between slots
  /// later is likewise accounted for on its own.
  void _scrollToCurrent() {
    final ctx = _currentSlotKey.currentContext;
    if (ctx == null) return;
    Scrollable.ensureVisible(
      ctx,
      alignment: 0.5, // 0.5 = centred in the viewport
      duration: const Duration(milliseconds: 600),
      curve: Curves.easeOutCubic,
    );
  }

  void _openLevel(Level level) {
    if (level.isLocked) return;
    // No .then here: winning a level advances with pushReplacement, which
    // completes this future while the player is still playing. didPopNext is
    // what tells the menu it is genuinely back on top.
    Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => GameScreen(level: level)));
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
                  // Wordmark, with a dev-only "+" (new level) balanced on the
                  // right so the title stays centered.
                  Row(
                    children: [
                      const SizedBox(width: 50),
                      Expanded(
                        child: Center(child: Text('Dotto', style: AppTheme.title)),
                      ),
                      SizedBox(
                        width: 50,
                        child: isDevMode
                            ? Align(
                                alignment: Alignment.centerRight,
                                child: _SideIcon(
                                  icon: Icons.add_rounded,
                                  onTap: () => Navigator.of(context).push(
                                    MaterialPageRoute(
                                      builder: (_) => const LevelDesignerScreen(),
                                    ),
                                  ),
                                ),
                              )
                            : null,
                      ),
                    ],
                  ),
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
              // Level 1 sits at the bottom, the last level at the top — climb
              // upward. A world banner marks the start of each world as you
              // climb past it. Cards stay centered on the dashed line.
              children: [
                for (var i = 0; i < _levels.length; i++)
                  () {
                    final level = _levels[_levels.length - 1 - i];
                    final isCurrent = level.id == current.id;
                    final slot = _LevelSlot(
                      key: isCurrent ? _currentSlotKey : null,
                      level: level,
                      isCurrent: isCurrent,
                      onTap: () => _openLevel(level),
                    );
                    // Place a world banner just below the first level of each
                    // world (so it reads "entering World N" while climbing up).
                    if (level.number == 1) {
                      return Column(children: [
                        slot,
                        const _WorldBanner(
                            number: 1, subtitle: 'Getting Started'),
                      ]);
                    }
                    if (level.number == kWorld2Start) {
                      return Column(children: [
                        slot,
                        const _WorldBanner(
                            number: 2, subtitle: 'Static Destroyers'),
                      ]);
                    }
                    if (level.number == kWorld3Start) {
                      return Column(children: [
                        slot,
                        const _WorldBanner(
                            number: 3, subtitle: 'Shields & Explosions'),
                      ]);
                    }
                    if (level.number == kWorld4Start) {
                      return Column(children: [
                        slot,
                        const _WorldBanner(
                            number: 4, subtitle: 'Patrols & Pause'),
                      ]);
                    }
                    if (level.number == kWorld5Start) {
                      return Column(children: [
                        slot,
                        const _WorldBanner(number: 5, subtitle: 'Teleporters'),
                      ]);
                    }
                    if (level.number == kWorld6Start) {
                      return Column(children: [
                        slot,
                        const _WorldBanner(
                            number: 6, subtitle: 'Rotating Arrows'),
                      ]);
                    }
                    if (level.number == kWorld7Start) {
                      return Column(children: [
                        slot,
                        const _WorldBanner(
                            number: 7, subtitle: 'One-Shot Arrows'),
                      ]);
                    }
                    return slot;
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
    super.key,
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

/// A banner marking the start of a world on the path. Sits centered on the
/// dashed line as a rounded pill with the world number and theme name.
class _WorldBanner extends StatelessWidget {
  const _WorldBanner({required this.number, required this.subtitle});

  final int number;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: AppColors.ink, width: 3),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'WORLD $number',
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 15,
                  letterSpacing: 1.5,
                  color: AppColors.ink,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 11,
                  letterSpacing: 0.5,
                  color: AppColors.textSoft,
                ),
              ),
            ],
          ),
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
