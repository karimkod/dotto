// Vibration feedback, behind the same kind of gate as sound.
//
// Every haptic in the game goes through here rather than calling
// HapticFeedback directly, so the settings toggle has one place to work and
// cannot be bypassed by a call site that forgot about it.

import 'package:flutter/services.dart';

import 'settings_store.dart';

class Haptics {
  Haptics._();

  static bool get _on => SettingsStore.hapticsOn;

  /// A tap, a piece lifted, a button.
  static void light() {
    if (_on) HapticFeedback.lightImpact();
  }

  /// A piece landing on the board.
  static void medium() {
    if (_on) HapticFeedback.mediumImpact();
  }

  /// Something going wrong — an explosion, a run lost.
  static void heavy() {
    if (_on) HapticFeedback.heavyImpact();
  }
}
