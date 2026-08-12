// Game Center on iOS, Play Games Services on Android.
//
// ANDROID IS NOT WIRED UP YET. Every androidID below is empty, waiting on the
// Play Console setup. That is not merely inert: the plugin's Achievement.id
// returns androidID on Android, so an empty one would hand Play Games a blank
// achievement id. [_unlock] refuses to send an empty id for exactly that
// reason, which makes Android a silent no-op until the real ids are pasted in —
// the same shape as being signed out.
//
// Everything here is optional and fire-and-forget. A player who never signs in,
// declines Game Center, or plays offline must see no difference in the game, so
// nothing is awaited from game code and every call swallows its errors. An
// achievement is a nice thing that happens, never a thing that can fail.

import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:games_services/games_services.dart';

/// The achievements Dotto reports, with their per-platform ids.
///
/// iOS uses the reverse-domain ids registered in App Store Connect. The Android
/// column is filled in from the Play Console, where ids look like
/// `CgkI...ABw` — they are generated, not chosen, so they cannot be written
/// ahead of the console work.
class _Ach {
  const _Ach(this.ios, this.android);

  final String ios;
  final String android;

  String get forPlatform => Platform.isAndroid ? android : ios;
}

// TODO(android): replace each empty string with the id Play Console generates.
const _worldAchievements = <int, _Ach>{
  1: _Ach('com.karimkod.dotto.world1', ''),
  2: _Ach('com.karimkod.dotto.world2', ''),
  3: _Ach('com.karimkod.dotto.world3', ''),
  4: _Ach('com.karimkod.dotto.world4', ''),
  5: _Ach('com.karimkod.dotto.world5', ''),
  6: _Ach('com.karimkod.dotto.world6', ''),
  7: _Ach('com.karimkod.dotto.world7', ''),
};

const _master = _Ach('com.karimkod.dotto.master', '');
const _hintSeeker = _Ach('com.karimkod.dotto.hint_seeker', '');
const _speedRunner = _Ach('com.karimkod.dotto.speed_runner', '');

/// Hints taken across all sessions before "Hint Seeker" unlocks.
const int kHintSeekerTarget = 10;

/// Levels finished in one sitting before "Speed Runner" unlocks.
const int kSpeedRunnerTarget = 5;

class GameServices {
  GameServices._();

  /// Android stays switched off until Play Games is set up properly.
  ///
  /// This is a safety gate, not tidiness. The Play Games SDK wants an
  /// application id declared in AndroidManifest.xml:
  ///
  ///     <meta-data android:name="com.google.android.gms.games.APP_ID"
  ///                android:value="@string/games_app_id"/>
  ///
  /// and starting it without one can bring the app down at launch — a native
  /// failure, on the launch path, that the try/catch around [signIn] would not
  /// contain. There is no id to declare until the Play Console side exists, so
  /// Android does not sign in at all.
  ///
  /// Flip this to true in the same change that adds the manifest entry and
  /// fills in the androidID fields above.
  static const bool _androidReady = false;

  /// Where a games platform exists to talk to. Web has none, and `flutter test`
  /// has no plugin host.
  static bool get supported {
    if (kIsWeb) return false;
    if (Platform.environment.containsKey('FLUTTER_TEST')) return false;
    if (Platform.isAndroid) return _androidReady;
    return Platform.isIOS;
  }

  static bool _signedIn = false;
  static bool get signedIn => _signedIn;

  /// Levels finished since launch, for Speed Runner. Not persisted — the
  /// achievement is about one sitting.
  static int _sessionCompletions = 0;

  /// Sign in quietly. No UI on failure: a player who has never opened Game
  /// Center should not be met with an error about a feature they did not ask
  /// for.
  static Future<void> signIn() async {
    if (!supported) return;
    try {
      await GamesServices.signIn();
      _signedIn = await GamesServices.isSignedIn;
    } catch (e) {
      debugPrint('Game services sign-in failed, achievements off: $e');
    }
  }

  /// Open the platform's own achievements screen.
  ///
  /// Returns false when there is nothing to show — not signed in, or no games
  /// platform — so the caller can keep the entry point out of the way rather
  /// than opening nothing.
  static Future<bool> showAchievements() async {
    if (!supported || !_signedIn) return false;
    try {
      await GamesServices.showAchievements();
      return true;
    } catch (e) {
      debugPrint('Could not show achievements: $e');
      return false;
    }
  }

  static void _unlock(_Ach ach) {
    if (!supported || !_signedIn) return;
    // The guard that keeps Android quiet until its ids exist. Sending a blank
    // id would be an error report per achievement, several times a level.
    if (ach.forPlatform.isEmpty) return;
    unawaited(
      GamesServices.unlock(
        achievement: Achievement(
          androidID: ach.android,
          iOSID: ach.ios,
          percentComplete: 100,
        ),
      ).catchError((Object e) {
        debugPrint('Achievement unlock failed: $e');
        return null;
      }),
    );
  }

  /// Called after a level is recorded as complete.
  ///
  /// [completed] is the full set of finished levels, [world] the world the
  /// level just won belongs to, and [worldFinished] whether that world is now
  /// complete. The caller works those out because it already holds the level
  /// data; this class deliberately knows nothing about level numbering.
  static void onLevelCompleted({
    required int world,
    required bool worldFinished,
    required int totalCompleted,
    required int levelCount,
    required int lifetimeHints,
  }) {
    if (!supported) return;

    _sessionCompletions++;
    if (_sessionCompletions >= kSpeedRunnerTarget) _unlock(_speedRunner);

    if (worldFinished) {
      final ach = _worldAchievements[world];
      if (ach != null) _unlock(ach);
    }
    if (totalCompleted >= levelCount) _unlock(_master);
    if (lifetimeHints >= kHintSeekerTarget) _unlock(_hintSeeker);
  }

  /// Hints are taken outside a level completion too, so this is checked on its
  /// own as well — otherwise the badge would wait for the next level to end.
  static void onHintUsed(int lifetimeHints) {
    if (lifetimeHints >= kHintSeekerTarget) _unlock(_hintSeeker);
  }

  /// Tests only.
  @visibleForTesting
  static void resetForTest() {
    _sessionCompletions = 0;
    _signedIn = false;
  }
}
