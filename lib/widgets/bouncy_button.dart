import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../audio/sfx.dart';

/// Wraps any child to make taps feel satisfying:
/// - press-down: shrink to 0.92x + slight darken (fast, ~60ms)
/// - release: bounce back to 1.0 with an elastic overshoot (~220ms)
/// - a subtle ripple expands from the tap point, in [rippleColor]
/// - a light "tap" sound + light haptic on release
///
/// The child's own shadows are NOT clipped — only the ripple/darken overlays
/// are clipped to [borderRadius].
class BouncyButton extends StatefulWidget {
  const BouncyButton({
    super.key,
    required this.child,
    this.onTap,
    this.borderRadius = const BorderRadius.all(Radius.circular(16)),
    this.rippleColor,
    this.enabled = true,
  });

  final Widget child;
  final VoidCallback? onTap;
  final BorderRadiusGeometry borderRadius;
  final Color? rippleColor;
  final bool enabled;

  @override
  State<BouncyButton> createState() => _BouncyButtonState();
}

class _BouncyButtonState extends State<BouncyButton>
    with SingleTickerProviderStateMixin {
  bool _pressed = false;
  Offset _rippleCenter = Offset.zero;
  late final AnimationController _ripple;

  @override
  void initState() {
    super.initState();
    _ripple = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 420),
    );
  }

  @override
  void dispose() {
    _ripple.dispose();
    super.dispose();
  }

  bool get _on => widget.enabled && widget.onTap != null;

  void _onDown(TapDownDetails d) {
    setState(() {
      _pressed = true;
      _rippleCenter = d.localPosition;
    });
    _ripple.forward(from: 0);
  }

  void _onUp() {
    setState(() => _pressed = false);
    Sfx.tap();
    HapticFeedback.lightImpact();
    widget.onTap!();
  }

  void _onCancel() {
    if (_pressed) setState(() => _pressed = false);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: _on ? _onDown : null,
      onTapUp: _on ? (_) => _onUp() : null,
      onTapCancel: _on ? _onCancel : null,
      child: AnimatedScale(
        scale: _pressed ? 0.92 : 1.0,
        duration: Duration(milliseconds: _pressed ? 60 : 220),
        curve: _pressed ? Curves.easeOut : Curves.elasticOut,
        child: Stack(
          clipBehavior: Clip.none, // keep the child's own shadows
          children: [
            widget.child,
            Positioned.fill(
              child: IgnorePointer(
                child: ClipRRect(
                  borderRadius: widget.borderRadius,
                  child: Stack(
                    children: [
                      AnimatedBuilder(
                        animation: _ripple,
                        builder: (_, _) => CustomPaint(
                          painter: _RipplePainter(
                            _rippleCenter,
                            _ripple.value,
                            widget.rippleColor ?? Colors.white,
                          ),
                        ),
                      ),
                      Positioned.fill(
                        child: AnimatedOpacity(
                          opacity: _pressed ? 0.07 : 0,
                          duration: const Duration(milliseconds: 80),
                          child: const ColoredBox(color: Colors.black),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RipplePainter extends CustomPainter {
  _RipplePainter(this.center, this.t, this.color);

  final Offset center;
  final double t;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (t <= 0 || t >= 1) return;
    final dx = math.max(center.dx, size.width - center.dx);
    final dy = math.max(center.dy, size.height - center.dy);
    final maxR = math.sqrt(dx * dx + dy * dy);
    final r = maxR * Curves.easeOut.transform(t);
    final alpha = (1 - t) * 0.18;
    canvas.drawCircle(center, r, Paint()..color = color.withValues(alpha: alpha));
  }

  @override
  bool shouldRepaint(covariant _RipplePainter old) =>
      old.t != t || old.center != center;
}
