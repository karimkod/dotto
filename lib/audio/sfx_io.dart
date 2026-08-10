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

Future<void> _replay(AudioPlayer player) async {
  try {
    await player.seek(Duration.zero);
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
