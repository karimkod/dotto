// Mobile/desktop sound effects: the same design the web build synthesizes
// live, pre-rendered to assets/sfx/*.wav and played through audioplayers.
//
// One player per effect, created on first use and kept: the source stays loaded
// so replaying is a seek and a resume rather than a decode. Retriggering an
// effect restarts that one effect and leaves the others ringing, which is what
// a game wants — a tick during an explosion should not cut the explosion.
//
// Everything here is fire-and-forget. Sound is decoration; if a device refuses
// to play, the game carries on in silence rather than surfacing an error.

import 'dart:async';
import 'dart:io' show Platform;

import 'package:audioplayers/audioplayers.dart';

/// `flutter test` has no plugin host, so every call would throw
/// MissingPluginException and litter the suite with async errors. Widget tests
/// exercise the game screen, which plays sounds constantly — so the whole
/// subsystem stands down under test.
final bool _muted = Platform.environment.containsKey('FLUTTER_TEST');

/// The audio context every effect player is built with, and the reason the
/// background music survives a level.
///
/// Android hands out audio focus per player, not per app: a player that asks
/// for AUDIOFOCUS_GAIN takes it from whoever held it last, and the loser is
/// told so even when it belongs to the same process. audioplayers treats that
/// as final — a non-transient loss pauses the player and clears its playing
/// flag, so nothing ever brings it back. With the plugin's default context
/// that is exactly what happened here: the first tick of a level took focus
/// from the music and the track never returned, which read as the music
/// stopping the moment the player entered a level.
///
/// So effects ask for no focus at all and simply mix. The music player keeps
/// the default GAIN, which is what should hold focus anyway — it is the thing
/// that ought to yield to a phone call, and now it is the only player asking.
///
/// Android-only in effect: audioFocus has no counterpart elsewhere, and the
/// iOS half is the plugin's own default, so the session is left as it was.
final AudioContext _context = AudioContext(
  android: const AudioContextAndroid(audioFocus: AndroidAudioFocus.none),
  iOS: AudioContextIOS(),
);

final Map<String, AudioPlayer> _players = {};
final Set<String> _loading = {};

void _play(String name) {
  if (_muted) return;
  final existing = _players[name];
  if (existing != null) {
    unawaited(_replay(existing));
    return;
  }
  if (!_loading.add(name)) return; // first play still loading — drop this one
  unawaited(_create(name));
}

Future<void> _create(String name) async {
  try {
    final player = AudioPlayer(playerId: 'sfx_$name')
      ..setReleaseMode(ReleaseMode.stop);
    // Before the source, not after: changing the context on a loaded player
    // resets it and re-prepares what it was holding.
    await player.setAudioContext(_context);
    // lowLatency keeps the source resident (SoundPool on Android) instead of
    // rebuilding a media player per shot.
    await player.setPlayerMode(PlayerMode.lowLatency);
    await player.setSource(AssetSource('sfx/$name.wav'));
    _players[name] = player;
    await player.resume();
  } catch (_) {
    // Leave the name in _loading so a broken device stops retrying forever.
  }
}

/// Retriggers an already-loaded player.
///
/// The stop is not tidiness, it is the whole trick. Android's SoundPool has no
/// completion callback, so audioplayers never learns the shot ended and leaves
/// its `playing` flag set; `play()` is guarded by `if (!playing)`, so every
/// later resume on its own is a no-op and the effect is heard exactly once per
/// process. Stopping clears that flag (and drops the finished stream id), which
/// lets the resume start a fresh one. It is what audioplayers' own AudioPool
/// does between shots, for the same reason.
Future<void> _replay(AudioPlayer player) async {
  try {
    await player.stop();
    await player.resume();
  } catch (_) {}
}

void playPlace() => _play('place');
void playRemove() => _play('remove');
void playTick() => _play('tick');
void playArrow() => _play('arrow');
void playPause() => _play('pause');
void playTeleport() => _play('teleport');
void playDie() => _play('die');
void playBoom() => _play('boom');
void playShield() => _play('shield');
void playExit() => _play('exit');
void playLevelComplete() => _play('level_complete');
void playClick() => _play('click');
void playTap() => _play('tap');
