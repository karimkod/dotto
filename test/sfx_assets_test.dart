// The non-web sound path is asset-driven and fails quietly: a missing or
// misnamed WAV just means silence, which no test of game logic would ever
// notice. These checks are what stands between a renamed effect and a build
// that ships mute.

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:dotto/audio/sfx_spec.dart';

void main() {
  test('every effect in the spec has a generated asset', () {
    for (final name in kSfxSpecs.keys) {
      expect(File('assets/sfx/$name.wav').existsSync(), isTrue,
          reason: 'assets/sfx/$name.wav is missing — regenerate with '
              '`flutter test tool/make_sfx_test.dart`');
    }
  });

  test('every asset the mobile player asks for exists in the spec', () {
    // Guards drift in the other direction: sfx_io naming an effect the
    // generator does not produce.
    final src = File('lib/audio/sfx_io.dart').readAsStringSync();
    final asked = RegExp(r"_play\('([a-z_]+)'\)")
        .allMatches(src)
        .map((m) => m.group(1)!)
        .toSet();
    expect(asked, isNotEmpty, reason: 'the regex should match the play calls');
    expect(asked.difference(kSfxSpecs.keys.toSet()), isEmpty,
        reason: 'sfx_io plays an effect with no spec entry');
    expect(kSfxSpecs.keys.toSet().difference(asked), isEmpty,
        reason: 'the spec defines an effect nothing plays');
  });

  test('replaying stops before it resumes', () {
    // The native half of this cannot be reached from a Dart test: Android's
    // SoundPool reports no completion, so audioplayers leaves `playing` set and
    // silently ignores every resume after the first. Stopping first is what
    // clears it. Nothing about that is visible from here — the symptom is
    // silence, with no error to assert on — so the call sequence is pinned
    // instead, to keep a plausible-looking `seek(Duration.zero)` from quietly
    // muting the game again.
    final src = File('lib/audio/sfx_io.dart').readAsStringSync();
    expect(src, contains('player.stop()'),
        reason: 'a resume without a preceding stop is a no-op after the '
            'first shot');
    expect(src, isNot(contains('seek(')),
        reason: 'seek does not reset the flag that guards play()');
  });

  test('pubspec bundles the sfx directory', () {
    expect(File('pubspec.yaml').readAsStringSync(), contains('assets/sfx/'),
        reason: 'unbundled assets load as nothing at runtime');
  });

  group('rendered audio', () {
    for (final entry in kSfxSpecs.entries) {
      test('${entry.key} is audible, unclipped and well-formed', () {
        final bytes = renderWav(entry.value);
        expect(String.fromCharCodes(bytes.sublist(0, 4)), 'RIFF');
        expect(String.fromCharCodes(bytes.sublist(8, 12)), 'WAVE');

        final pcm =
            Int16List.view(bytes.buffer, 44, (bytes.length - 44) ~/ 2);
        var peak = 0;
        for (final s in pcm) {
          final a = s.abs();
          if (a > peak) peak = a;
        }
        // Silence means the envelope collapsed; a peak at the rail means the
        // summed layers clipped. Both are wrong in ways the ear notices.
        expect(peak, greaterThan(1000), reason: 'renders as near-silence');
        expect(peak, lessThan(32767), reason: 'clips');
      });
    }
  });

  test('rendering is deterministic', () {
    // The noise is seeded so regenerating produces no diff. If this breaks,
    // every run of the generator churns the repo.
    final a = renderWav(kSfxSpecs['boom']!);
    final b = renderWav(kSfxSpecs['boom']!);
    expect(a, orderedEquals(b));
  });
}
