// The background track and the preference in front of it.
//
// Music fails the same quiet way the sound effects do: a missing asset, an
// unbundled directory or a format the device cannot decode all come out as
// silence, with no error for a test of game logic to trip over. These checks
// are what stands between that and a build that ships mute.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:dotto/services/music_service.dart';

/// The asset path the service asks for, read from the source rather than
/// duplicated here — a constant copied into the test cannot catch the two
/// drifting apart.
String _assetPath() {
  final src = File('lib/services/music_service.dart').readAsStringSync();
  final match = RegExp(r"_asset = '([^']+)'").firstMatch(src);
  expect(match, isNotNull, reason: 'music_service should name its asset');
  return 'assets/${match!.group(1)!}';
}

void main() {
  test('the track the service asks for is actually there', () {
    final path = _assetPath();
    final file = File(path);
    expect(file.existsSync(), isTrue,
        reason: '$path is missing — rebuild it from '
            'promo/dotto_promo_music.wav');
    // A truncated or placeholder file still exists, and existing is all the
    // check above asks of it. Twenty-three seconds of VBR MP3 is ~230 KB.
    expect(file.lengthSync(), greaterThan(50000),
        reason: '$path is too small to be the track');
  });

  test('the track is a format every target can decode', () {
    // The trap this guards is specific and silent: Apple's media stack cannot
    // decode Ogg Vorbis, so an .ogg here plays on Android, passes review, and
    // is silence on every iPhone and in Safari. OGG is the smaller file, which
    // is exactly why someone will be tempted.
    final path = _assetPath();
    expect(path, endsWith('.mp3'),
        reason: 'iOS and Safari cannot play Ogg Vorbis');
    // The MPEG frame sync, allowing for an ID3v2 tag in front of it.
    final head = File(path).openSync().readSync(3);
    final isId3 = String.fromCharCodes(head) == 'ID3';
    final isFrame = head[0] == 0xFF && (head[1] & 0xE0) == 0xE0;
    expect(isId3 || isFrame, isTrue, reason: '$path is not an MPEG stream');
  });

  test('pubspec bundles the audio directory', () {
    expect(File('pubspec.yaml').readAsStringSync(), contains('assets/audio/'),
        reason: 'unbundled assets load as nothing at runtime');
  });

  test('the track loops natively rather than on a timer', () {
    // ReleaseMode.loop hands the repeat to the platform. A Dart-side restart
    // would put a frame of scheduling jitter at the seam, which is the one
    // place in the track where a gap is audible.
    final src = File('lib/services/music_service.dart').readAsStringSync();
    expect(src, contains('ReleaseMode.loop'));
  });

  test('music is on by default', () {
    // No plugin host under test, so the preference keeps its in-memory
    // default. A puzzle game that opens silent reads as broken.
    expect(MusicService.isEnabled, isTrue);
  });

  test('the setting takes effect immediately, storage or not', () {
    // The write is fire-and-forget and fails silently here; the value the game
    // reads is the in-memory one, which must change on the spot.
    MusicService.setEnabled(false);
    expect(MusicService.isEnabled, isFalse);
    MusicService.setEnabled(true);
    expect(MusicService.isEnabled, isTrue);
  });

  test('the volume sits low enough to stay underneath the game', () {
    expect(MusicService.defaultVolume, lessThanOrEqualTo(0.4));
    expect(MusicService.defaultVolume, greaterThan(0));
    expect(MusicService.volume, MusicService.defaultVolume);
  });

  test('a volume outside the range is clamped rather than passed on', () {
    MusicService.setVolume(2);
    expect(MusicService.volume, 1.0);
    MusicService.setVolume(-1);
    expect(MusicService.volume, 0.0);
    MusicService.setVolume(MusicService.defaultVolume);
    expect(MusicService.volume, MusicService.defaultVolume);
  });

  test('asking for music repeatedly is harmless', () {
    // Every screen that wants music says so in initState without checking
    // whether it is already playing, so this has to be idempotent.
    MusicService.play();
    MusicService.play();
    MusicService.pause();
    MusicService.resume();
    MusicService.stop();
    expect(MusicService.isEnabled, isTrue);
  });
}
