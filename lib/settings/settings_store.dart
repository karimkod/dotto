// Player preferences: sound and haptics, on by default, and how fast the dot
// runs.
//
// Unlike ProgressStore this needs no per-platform split — shared_preferences
// covers web too, and the one place it has no answer is `flutter test`, where
// getInstance throws, the cache keeps the defaults, and everything behaves as
// if the player had changed nothing.
//
// Reads are synchronous because they sit on hot paths: every sound and every
// haptic asks. So the values live in memory and preferences is the backup that
// restores them at launch, the same arrangement ProgressStore uses.

import 'dart:async';

import 'package:shared_preferences/shared_preferences.dart';

class SettingsStore {
  SettingsStore._();

  static const _soundKey = 'dotto_sound_on';
  static const _hapticsKey = 'dotto_haptics_on';
  static const _runSpeedKey = 'dotto_run_speed';

  static SharedPreferences? _prefs;

  // Both default to on: a puzzle game that opens silent feels broken rather
  // than considerate.
  static bool _sound = true;
  static bool _haptics = true;

  static bool get soundOn => _sound;
  static bool get hapticsOn => _haptics;

  /// The speeds a run can play at, as multiples of the game's own pace.
  static const runSpeeds = [1, 2, 3];

  // The game's own pace, until the player picks another.
  static int _runSpeed = 1;

  /// How fast the dot runs: one of [runSpeeds].
  static int get runSpeed => _runSpeed;

  /// Load saved preferences. Call once before `runApp`; anything not loaded by
  /// then reads as the default.
  static Future<void> init() async {
    try {
      final prefs = _prefs = await SharedPreferences.getInstance();
      _sound = prefs.getBool(_soundKey) ?? true;
      _haptics = prefs.getBool(_hapticsKey) ?? true;
      // A stored speed the button does not offer falls back to the game's own
      // pace, rather than playing at one the button cannot show.
      final speed = prefs.getInt(_runSpeedKey) ?? 1;
      _runSpeed = runSpeeds.contains(speed) ? speed : 1;
    } catch (_) {
      // No storage available. Defaults stand; the session still works, the
      // choice just will not outlive it.
    }
  }

  static void setSound(bool on) {
    _sound = on;
    _write(_soundKey, on);
  }

  static void setHaptics(bool on) {
    _haptics = on;
    _write(_hapticsKey, on);
  }

  static void setRunSpeed(int speed) {
    assert(runSpeeds.contains(speed), 'not a speed the button offers: $speed');
    _runSpeed = speed;
    final prefs = _prefs;
    if (prefs == null) return;
    unawaited(prefs.setInt(_runSpeedKey, speed).catchError((_) => false));
  }

  static void _write(String key, bool value) {
    final prefs = _prefs;
    if (prefs == null) return;
    // Fire and forget: the setting already took effect in memory, so a failed
    // write costs the next launch rather than this tap.
    unawaited(prefs.setBool(key, value).catchError((_) => false));
  }
}
