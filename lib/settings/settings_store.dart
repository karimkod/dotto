// Player preferences: sound and haptics, on by default.
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

  static SharedPreferences? _prefs;

  // Both default to on: a puzzle game that opens silent feels broken rather
  // than considerate.
  static bool _sound = true;
  static bool _haptics = true;

  static bool get soundOn => _sound;
  static bool get hapticsOn => _haptics;

  /// Load saved preferences. Call once before `runApp`; anything not loaded by
  /// then reads as the default.
  static Future<void> init() async {
    try {
      final prefs = _prefs = await SharedPreferences.getInstance();
      _sound = prefs.getBool(_soundKey) ?? true;
      _haptics = prefs.getBool(_hapticsKey) ?? true;
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

  static void _write(String key, bool value) {
    final prefs = _prefs;
    if (prefs == null) return;
    // Fire and forget: the setting already took effect in memory, so a failed
    // write costs the next launch rather than this tap.
    unawaited(prefs.setBool(key, value).catchError((_) => false));
  }
}
