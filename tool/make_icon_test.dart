// Generates the app icon: the dot itself, glowing. Nothing else.
//
// Run:  flutter test tool/make_icon_test.dart
// Writes assets/icon/dotto_icon.png (full-bleed, iOS + Play listing) and
// dotto_icon_foreground.png (transparent, Android adaptive foreground).
//
// The background is the game's own ink (#2D2D2D) rather than its cream: a warm
// glow reads as light on a dark field and disappears on a light one, and the dot
// is the whole subject here.
import 'dart:io';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';

const _ink = Color(0xFF2D2D2D); // the game's outline colour, used as the field
const _dot = Color(0xFFFFB347); // AppColors.accent — the dot
const _hot = Color(0xFFFFD9A0); // lit top-left of the sphere
const _deep = Color(0xFFF59331); // shaded lower edge

/// Draws the glowing dot centred in a [size] box. Content stays inside the
/// middle ~60% so Android's adaptive mask (which crops to a circle or squircle,
/// then insets a further 16%) never clips the ball itself — only the outer,
/// softest reach of the glow, which fades to nothing anyway.
void paintMark(Canvas canvas, double size, {required bool background}) {
  final c = Offset(size / 2, size / 2);
  if (background) {
    canvas.drawRect(Rect.fromLTWH(0, 0, size, size), Paint()..color = _ink);
  }

  final r = size * 0.20; // the ball
  final glow = size * 0.42; // how far the light reaches

  // The radiance: one wide soft field, then a tighter brighter one, so the
  // falloff has some shape instead of reading as a flat disc.
  canvas.drawCircle(
    c,
    glow,
    Paint()
      ..shader = Gradient.radial(c, glow, [
        _dot.withValues(alpha: 0.42),
        _dot.withValues(alpha: 0.16),
        _dot.withValues(alpha: 0.0),
      ], [
        0.0,
        0.45,
        1.0,
      ]),
  );
  canvas.drawCircle(
    c,
    r * 1.9,
    Paint()
      ..shader = Gradient.radial(c, r * 1.9, [
        _dot.withValues(alpha: 0.55),
        _dot.withValues(alpha: 0.0),
      ], [
        0.3,
        1.0,
      ]),
  );

  // A soft seat beneath the ball so it sits in the light rather than floating
  // flat on it.
  canvas.drawCircle(
    c + Offset(0, r * 0.55),
    r * 0.95,
    Paint()
      ..color = const Color(0xFF1A1614).withValues(alpha: 0.35)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, size * 0.035),
  );

  // The ball, lit from the top-left the way the game lights its dot.
  canvas.drawCircle(
    c,
    r,
    Paint()
      ..shader = Gradient.radial(
        c - Offset(r * 0.35, r * 0.4), // highlight offset
        r * 1.45,
        [_hot, _dot, _deep],
        [0.0, 0.55, 1.0],
      ),
  );

  // A specular kiss — faded, not a pasted-on disc. A hard-edged white circle
  // reads as a sticker; the sheen has to dissolve into the surface.
  final specCentre = c - Offset(r * 0.34, r * 0.40);
  final specR = r * 0.34;
  canvas.drawCircle(
    specCentre,
    specR,
    Paint()
      ..shader = Gradient.radial(specCentre, specR, [
        const Color(0xFFFFFFFF).withValues(alpha: 0.55),
        const Color(0xFFFFFFFF).withValues(alpha: 0.18),
        const Color(0xFFFFFFFF).withValues(alpha: 0.0),
      ], [
        0.0,
        0.5,
        1.0,
      ]),
  );
}

Future<void> write(String path, int px, {required bool background}) async {
  final recorder = PictureRecorder();
  final canvas = Canvas(recorder);
  paintMark(canvas, px.toDouble(), background: background);
  final img = await recorder.endRecording().toImage(px, px);
  final bytes = await img.toByteData(format: ImageByteFormat.png);
  final f = File(path);
  f.parent.createSync(recursive: true);
  f.writeAsBytesSync(bytes!.buffer.asUint8List());
  // ignore: avoid_print
  print('wrote $path (${bytes.lengthInBytes} bytes)');
}

void main() {
  test('generate app icons', () async {
    await write('assets/icon/dotto_icon.png', 1024, background: true);
    await write('assets/icon/dotto_icon_foreground.png', 1024,
        background: false);
  });
}
