// Sound effects facade. Resolves to Web Audio on web, to pre-rendered WAV
// assets played through audioplayers on mobile/desktop, and to a no-op stub
// where neither library exists.
//
// The conditions are ordered, first match wins: web has dart.library.js_interop,
// mobile and the VM have dart.library.io.

import 'sfx_stub.dart'
    if (dart.library.js_interop) 'sfx_web.dart'
    if (dart.library.io) 'sfx_io.dart' as impl;

/// The game's sound effects. Synthesized live on web; the same design rendered
/// to assets/sfx/*.wav everywhere else — see sfx_spec.dart.
class Sfx {
  Sfx._();

  static void place() => impl.playPlace();
  static void remove() => impl.playRemove();
  static void tick() => impl.playTick();
  static void arrow() => impl.playArrow();
  static void pause() => impl.playPause();
  static void teleport() => impl.playTeleport();
  static void die() => impl.playDie();

  /// Loud explosion for a destroyer hit.
  static void boom() => impl.playBoom();

  /// Soft shimmer when the dot picks up a shield aura.
  static void shield() => impl.playShield();

  static void exit() => impl.playExit();
  static void levelComplete() => impl.playLevelComplete();
  static void click() => impl.playClick();

  /// Light, short feedback for a button press.
  static void tap() => impl.playTap();
}
