// Generates the app icon: the dot itself, glowing. Nothing else.
//
// Run:  flutter test tool/make_icon_test.dart
// Writes assets/icon/dotto_icon.png (full-bleed, iOS + Play listing) and
// dotto_icon_foreground.png (transparent, Android adaptive foreground).
//
// The background is the game's cream (#FAF8F5), so the icon sits in the same
// world as the board. A glow has less contrast to work with on a light field
// than on a dark one, so it is carried by warmth rather than brightness — the
// halo deepens toward coral instead of fading to white — and the ball takes the
// game's ink outline, which is what gives it definition against the cream.
import 'dart:io';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';

const _cream = Color(0xFFFAF8F5); // AppColors.background — the field
const _ink = Color(0xFF2D2D2D); // AppColors.ink — the outline
const _dot = Color(0xFFFFB347); // AppColors.accent — the dot
const _coral = Color(0xFFFF6B6B); // AppColors.coral — the outer glow's warmth
const _hot = Color(0xFFFFD9A0); // lit top-left of the sphere
const _deep = Color(0xFFF59331); // shaded lower edge

/// The share of an Android adaptive layer that survives the mask: the layer is
/// 108dp and only the middle 72dp is guaranteed visible.
const _adaptiveSafeFraction = 72 / 108;

/// How much a full-bleed target has to grow to match what the adaptive mask
/// shows. Cropping to the safe zone is itself a zoom of 1 / (72/108) = 1.5, so
/// an uncropped icon must apply that zoom itself or the mark lands smaller.
const _fullBleedScale = 1 / _adaptiveSafeFraction;

/// Draws the glowing dot centred in a [size] box. Content is laid out against
/// Android's adaptive safe zone, staying inside the middle ~60% so the mask
/// (which crops to a circle or squircle, then insets a further 16%) never clips
/// the ball itself — only the outer, softest reach of the glow, which fades to
/// nothing anyway.
///
/// [markScale] compensates for that safe-zone padding on targets nothing crops.
/// Without it the same artwork reads at two different sizes: the ball is 40% of
/// the canvas here, so it fills 40% of an iOS tile but 60% of an Android one,
/// because the mask has zoomed in. Passing [_fullBleedScale] for uncropped
/// targets makes the ball the same size on both.
void paintMark(
  Canvas canvas,
  double size, {
  required bool background,
  double markScale = 1.0,
}) {
  final c = Offset(size / 2, size / 2);
  if (background) {
    canvas.drawRect(Rect.fromLTWH(0, 0, size, size), Paint()..color = _cream);
  }

  // Scale about the centre so the mark grows without drifting. The cream field
  // is filled before this and stays full-bleed either way. An unscaled mark
  // skips the transform entirely rather than applying an identity one, so the
  // already-shipped Android foreground stays byte-for-byte what it was.
  final scaled = markScale != 1.0;
  if (scaled) {
    canvas.save();
    canvas.translate(c.dx, c.dy);
    canvas.scale(markScale);
    canvas.translate(-c.dx, -c.dy);
  }

  final r = size * 0.20; // the ball
  final glow = size * 0.42; // how far the light reaches

  // The radiance. Against cream a pale halo would vanish, so this one gains
  // saturation as it leaves the ball — orange into coral — and fades out on
  // colour rather than on brightness.
  canvas.drawCircle(
    c,
    glow,
    Paint()
      ..shader = Gradient.radial(c, glow, [
        _dot.withValues(alpha: 0.50),
        _coral.withValues(alpha: 0.22),
        _coral.withValues(alpha: 0.0),
      ], [
        0.0,
        0.5,
        1.0,
      ]),
  );
  canvas.drawCircle(
    c,
    r * 1.75,
    Paint()
      ..shader = Gradient.radial(c, r * 1.75, [
        _dot.withValues(alpha: 0.45),
        _dot.withValues(alpha: 0.0),
      ], [
        0.35,
        1.0,
      ]),
  );

  // A soft seat beneath the ball. Warm grey — the game's own shadow colour —
  // rather than black, which would go muddy against cream.
  canvas.drawCircle(
    c + Offset(0, r * 0.62),
    r * 0.92,
    Paint()
      ..color = const Color(0xFF786E5F).withValues(alpha: 0.28)
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

  // The thick hand-drawn outline every piece on the board wears. On the dark
  // field this was unnecessary; on cream it is what separates ball from
  // backdrop, and it puts the icon in the same visual language as the game.
  canvas.drawCircle(
    c,
    r,
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = size * 0.022
      ..color = _ink,
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

  if (scaled) {
    canvas.restore();
  }
}

Future<void> write(
  String path,
  int px, {
  required bool background,
  double markScale = 1.0,
}) async {
  final recorder = PictureRecorder();
  final canvas = Canvas(recorder);
  paintMark(canvas, px.toDouble(), background: background, markScale: markScale);
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
    // Full-bleed: iOS, the Play listing, and the Android legacy launcher icon.
    // Nothing masks these, so they carry the zoom themselves.
    await write('assets/icon/dotto_icon.png', 1024,
        background: true, markScale: _fullBleedScale);
    // Android adaptive foreground: the mask supplies the same zoom, so this one
    // stays at its natural size.
    await write('assets/icon/dotto_icon_foreground.png', 1024,
        background: false);
  });
}
