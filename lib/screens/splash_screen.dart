// The opening: the dot arrives, the name follows, then the game.
//
// It exists to cover a real gap rather than to be an animation. Everything
// launch needs — storage, consent, the challenge cache — loads behind it (see
// [SplashScreen.holdFor]), and the native launch theme only paints a flat
// colour — so this is the stretch a player would otherwise spend looking at
// nothing, now spent looking at the game arriving instead.
//
// The dot is drawn rather than loaded, in the same terms as the board: a filled
// circle in the game's accent, a thick ink outline, and a warm halo behind it.
// Loading an image here would mean a second source of truth for what the dot
// looks like.

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key, required this.next, this.holdFor});

  /// What to show once the opening is done. Built lazily, so the decision is
  /// made when it is needed rather than before the animation starts.
  final WidgetBuilder next;

  /// The work the opening is covering, or null when there is none.
  ///
  /// The handoff waits for it: the animation may finish first, but [next] is
  /// not built until this settles — which is what lets the screens behind the
  /// splash read their stores synchronously. The animation does not wait in
  /// return; the halo keeps breathing over a long hold, so a slow boot reads
  /// as the opening taking a moment rather than as a hang.
  final Future<void>? holdFor;

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {
  /// Drives the whole opening. The tail after the animations is deliberate —
  /// a beat of stillness before the game reads as composure; cutting on the
  /// last frame of a bounce reads as a glitch.
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1800),
  );

  /// A separate, freely repeating pulse for the halo. Tying it to [_ctrl] would
  /// have made it stop dead at the end of the opening.
  late final AnimationController _glow = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  )..repeat(reverse: true);

  // 0–800ms: the dot arrives, overshooting the way a dropped ball does.
  late final Animation<double> _scale = CurvedAnimation(
    parent: _ctrl,
    curve: const Interval(0, 0.444, curve: Curves.elasticOut),
  );

  // 600–1000ms: the name catches up.
  late final Animation<double> _title = CurvedAnimation(
    parent: _ctrl,
    curve: const Interval(0.333, 0.556, curve: Curves.easeIn),
  );

  @override
  void initState() {
    super.initState();
    _ctrl.forward();
    _ctrl.addStatusListener((s) {
      if (s == AnimationStatus.completed) _handOver();
    });
  }

  /// The animation is done; leave as soon as the covered work is too.
  Future<void> _handOver() async {
    final hold = widget.holdFor;
    if (hold != null) {
      // Never let a failed boot strand the player here: the splash's one job
      // is to get out of the way, and whoever owns the future reports its
      // errors.
      try {
        await hold;
      } catch (_) {}
    }
    if (!mounted) return;
    _go();
  }

  void _go() {
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        pageBuilder: (context, _, _) => widget.next(context),
        transitionsBuilder: (_, animation, _, child) =>
            FadeTransition(opacity: animation, child: child),
        transitionDuration: const Duration(milliseconds: 450),
      ),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _glow.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedBuilder(
              animation: Listenable.merge([_ctrl, _glow]),
              builder: (context, _) => CustomPaint(
                size: const Size(220, 220),
                painter: _DotPainter(
                  scale: _scale.value,
                  // Never fully off: the halo breathes rather than blinking.
                  glow: 0.55 + 0.45 * _glow.value,
                ),
              ),
            ),
            const SizedBox(height: 28),
            FadeTransition(
              opacity: _title,
              child: Text(
                'DOTTO',
                style: TextStyle(
                  color: AppColors.ink,
                  fontSize: 34,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 8, // spaced out, so it reads as a mark
                  fontFamily: AppTheme.title.fontFamily,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The dot and its halo, in the board's own terms.
class _DotPainter extends CustomPainter {
  const _DotPainter({required this.scale, required this.glow});

  /// 0 to slightly past 1 — [Curves.elasticOut] overshoots, which is the point.
  final double scale;

  /// Halo strength, 0–1.
  final double glow;

  @override
  void paint(Canvas canvas, Size size) {
    if (scale <= 0) return;
    final c = Offset(size.width / 2, size.height / 2);
    final r = (size.width * 0.20) * scale;
    if (r <= 0) return;

    // The halo: warm rather than bright. Against cream a pale glow disappears,
    // so this one gains colour as it leaves the dot instead of losing it —
    // the same trick the app icon uses.
    final haloR = r * 2.1;
    canvas.drawCircle(
      c,
      haloR,
      Paint()
        ..shader = RadialGradient(
          colors: [
            AppColors.accent.withValues(alpha: 0.45 * glow),
            AppColors.coral.withValues(alpha: 0.18 * glow),
            AppColors.coral.withValues(alpha: 0),
          ],
          stops: const [0.0, 0.55, 1.0],
        ).createShader(Rect.fromCircle(center: c, radius: haloR)),
    );

    // The dot, lit from the top-left the way the board lights it.
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-0.35, -0.4),
          radius: 0.95,
          colors: const [Color(0xFFFFD9A0), AppColors.accent, Color(0xFFF59331)],
          stops: const [0.0, 0.55, 1.0],
        ).createShader(Rect.fromCircle(center: c, radius: r)),
    );

    // The outline every piece on the board wears. It scales with the dot, or a
    // small dot would wear a hoop.
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = (size.width * 0.018) * scale
        ..color = AppColors.ink,
    );
  }

  @override
  bool shouldRepaint(_DotPainter old) =>
      old.scale != scale || old.glow != glow;
}
