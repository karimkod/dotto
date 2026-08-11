// Sound effects facade. Resolves to Web Audio on web, to pre-rendered WAV
// assets played through audioplayers on mobile/desktop, and to a no-op stub
// where neither library exists.
//
// The conditions are ordered, first match wins: web has dart.library.js_interop,
// mobile and the VM have dart.library.io.

import '../settings/settings_store.dart';
import 'sfx_stub.dart'
    if (dart.library.js_interop) 'sfx_web.dart'
    if (dart.library.io) 'sfx_io.dart' as impl;

/// The game's sound effects. Synthesized live on web; the same design rendered
/// to assets/sfx/*.wav everywhere else — see sfx_spec.dart.
///
/// The mute lives here rather than in any one implementation: a player who
/// turns sound off means it everywhere, and one gate in the facade cannot be
/// left out of a platform by accident. The check is a field read, so the cost
/// of asking on every tick is nil.
class Sfx {
  Sfx._();

  static bool get _on => SettingsStore.soundOn;

  static void place() {
    if (_on) impl.playPlace();
  }

  static void remove() {
    if (_on) impl.playRemove();
  }

  static void tick() {
    if (_on) impl.playTick();
  }

  static void arrow() {
    if (_on) impl.playArrow();
  }

  static void pause() {
    if (_on) impl.playPause();
  }

  static void teleport() {
    if (_on) impl.playTeleport();
  }

  static void die() {
    if (_on) impl.playDie();
  }

  /// Loud explosion for a destroyer hit.
  static void boom() {
    if (_on) impl.playBoom();
  }

  /// Soft shimmer when the dot picks up a shield aura.
  static void shield() {
    if (_on) impl.playShield();
  }

  static void exit() {
    if (_on) impl.playExit();
  }

  static void levelComplete() {
    if (_on) impl.playLevelComplete();
  }

  static void click() {
    if (_on) impl.playClick();
  }

  /// Light, short feedback for a button press.
  static void tap() {
    if (_on) impl.playTap();
  }
}
