// Sound effects facade. Resolves to the Web Audio implementation on web and a
// no-op stub elsewhere (so VM tests don't touch dart:js_interop).

import 'sfx_stub.dart' if (dart.library.js_interop) 'sfx_web.dart' as impl;

/// Synthesized, file-free game sound effects.
class Sfx {
  Sfx._();

  static void place() => impl.playPlace();
  static void remove() => impl.playRemove();
  static void tick() => impl.playTick();
  static void arrow() => impl.playArrow();
  static void pause() => impl.playPause();
  static void teleport() => impl.playTeleport();
  static void die() => impl.playDie();
  static void exit() => impl.playExit();
  static void levelComplete() => impl.playLevelComplete();
  static void click() => impl.playClick();
}
