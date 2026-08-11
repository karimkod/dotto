// When an interstitial is allowed to interrupt.
//
// Deliberately separate from AdManager and free of any SDK import: AdManager is
// inert under `flutter test`, so anything living inside it cannot be tested.
// The rules for when a player gets shown an ad are exactly the part worth
// testing, so they live here as plain Dart.
//
// The counter is per session and not persisted. Closing the app earns a clean
// slate, which errs toward showing fewer ads than more — the right direction to
// err in for something that interrupts a player mid-flow.

class AdPacing {
  AdPacing._();

  /// Show at every third completed level.
  static const int everyN = 3;

  /// No interstitials at all until the player is finishing levels at or past
  /// this one. The opening stretch is where a player decides whether the game
  /// is worth their time, and an ad in the middle of that is expensive in a way
  /// that does not show up in ad revenue.
  static const int minLevel = 10;

  static int _completed = 0;

  /// Levels finished since the app started.
  static int get levelsCompletedThisSession => _completed;

  /// Record a completed level and say whether an interstitial is now due.
  ///
  /// Four things stop one:
  ///
  ///  * finishing anything below [minLevel];
  ///  * the first two completions of a session — a player who has just started
  ///    should be allowed to build some momentum before being interrupted;
  ///  * any level the player took a hint on, because the hint may already have
  ///    cost them a rewarded video, and two ads around one level is the kind of
  ///    thing that gets an app deleted;
  ///  * anything that is not a multiple of [everyN].
  ///
  /// A skipped slot is not deferred: taking a hint on the third level costs
  /// that ad rather than moving it to the fourth. The cadence stays predictable
  /// and the player is never surprised by an ad arriving early.
  ///
  /// Levels below [minLevel] still count toward the cadence even though they
  /// can never trigger an ad. The counter means "levels finished this session",
  /// and keeping it that way is what stops a player who crosses the threshold
  /// mid-session from being interrupted immediately on level 10.
  static bool noteLevelCompleted({
    required int levelId,
    required bool usedHint,
  }) {
    _completed++;
    if (levelId < minLevel) return false;
    if (usedHint) return false;
    return _completed % everyN == 0;
  }

  /// Tests only — the counter is otherwise process-global for the session.
  static void resetForTest() => _completed = 0;
}
