// Renders the game's sound effects to assets/sfx/*.wav.
//
// Run:  flutter test tool/make_sfx_test.dart
//
// The effects are synthesized live on web through Web Audio; every other
// platform plays these files instead. The definitions live in
// lib/audio/sfx_spec.dart, so this script is only the crank — regenerate after
// changing a layer there.
//
// Output is deterministic (the noise is seeded), so re-running with no spec
// change rewrites the same bytes and produces no diff.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:dotto/audio/sfx_spec.dart';

void main() {
  test('generate sfx wavs', () {
    final dir = Directory('assets/sfx')..createSync(recursive: true);
    var total = 0;
    for (final entry in kSfxSpecs.entries) {
      final bytes = renderWav(entry.value);
      File('${dir.path}/${entry.key}.wav').writeAsBytesSync(bytes);
      total += bytes.length;
      // ignore: avoid_print
      print('wrote ${entry.key}.wav (${bytes.length} bytes)');
    }
    // ignore: avoid_print
    print('${kSfxSpecs.length} effects, $total bytes total');
  });
}
