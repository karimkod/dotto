// When an interstitial is allowed to interrupt.
//
// Deliberately separate from AdManager and free of any SDK import: AdManager is
// inert under `flutter test`, so anything living inside it cannot be tested.
// The rules for when a player gets shown an ad are exactly the part worth
// testing, so they live here as plain Dart.
//
// Every interstitial lands at the end of a level, as the player moves on from
// the win, and never while they are still working on one. That is a choice: an
// ad on the fail card would reach the player who gives up mid-level, but it
// would reach them at their most frustrated, which is when an ad is likeliest
// to turn one more try into closing the app for good.
//
// The state is per session and not persisted. Closing the app earns a clean
// slate, which errs toward showing fewer ads than more — the right direction to
// err in for something that interrupts a player mid-flow.

/// Why an interstitial was due, as sent in `interstitial_shown`'s `trigger`.
enum AdBreak {
  /// [AdPacing.everyN] levels finished since the last ad.
  betweenLevels('between_levels'),

  /// A level that took longer than [AdPacing.longLevel].
  longLevel('long_level');

  const AdBreak(this.trigger);

  /// The analytics name. `between_levels` is older than the long-level rule
  /// and keeps its name, so the counts from before the rule still line up.
  final String trigger;
}

class AdPacing {
  AdPacing._();

  /// An ad is due once this many levels have been finished since the last one.
  static const int everyN = 2;

  /// A level that takes longer than this ends on an ad even off the [everyN]
  /// beat, so a player who spends a long time on few levels sees ads in step
  /// with how long they play rather than how far they get.
  ///
  /// Play time only: the game screen's clock stops while the app is in the
  /// background, so time spent away never earns an ad.
  static const Duration longLevel = Duration(minutes: 3);

  /// Never two ads closer together than this, whichever rule asks. Two quick
  /// levels would otherwise put ads half a minute apart. An ad held back is not
  /// lost: the count keeps running, so the next level end asks again.
  static const Duration minGap = Duration(seconds: 90);

  /// No interstitials at all until the player is finishing levels at or past
  /// this one. The opening stretch is where a player decides whether the game
  /// is worth their time, and an ad in the middle of that is expensive in a way
  /// that does not show up in ad revenue.
  ///
  /// Counted in play order, by the number the player sees on the level. Ids
  /// keep the gaps that retired levels leave, so counting by id would shorten
  /// this stretch by every level retired from it.
  static const int minLevel = 5;

  static int _levelsSinceAd = 0;
  static DateTime? _lastAdAt;
  static bool _adThisLevel = false;
  static DateTime Function() _clock = DateTime.now;

  /// Levels finished since the last ad showed, or since the app started.
  static int get levelsSinceAd => _levelsSinceAd;

  /// Mark the start of a level, so that [noteLevelCompleted] can tell whether
  /// an ad played while it was open.
  static void noteLevelStarted() => _adThisLevel = false;

  /// Record that a full-screen ad, of either kind, was on screen and has now
  /// closed. AdManager calls this for every ad that actually showed, so a hint
  /// video counts exactly as an interstitial does.
  ///
  /// Restarts the level count and the [minGap] clock. The clock runs from the
  /// close rather than the start, so the gap is time the player had back in
  /// the game, not time partly spent watching the last ad.
  static void noteAdShown() {
    _levelsSinceAd = 0;
    _lastAdAt = _clock();
    _adThisLevel = true;
  }

  /// Record a completed level and say whether an interstitial is now due, and
  /// why, or null if none is.
  ///
  /// [levelNumber] is the place in play order, not the id; see [minLevel].
  /// [timeOnLevel] is the play time since the level opened, every attempt
  /// included, which is what [longLevel] is measured against.
  ///
  /// Three things stop one:
  ///
  ///  * finishing anything below [minLevel];
  ///  * an ad having played while the level was open. In practice that is a
  ///    hint video, the only ad that can, and two ads around one level is the
  ///    kind of thing that gets an app deleted. A free hint is no reason: it
  ///    showed nothing, and long levels are where players take hints, so
  ///    sparing every hinted level would spare many of the levels [longLevel]
  ///    is there for;
  ///  * less than [minGap] since the last ad.
  ///
  /// Past those, an ad is due once [everyN] levels have been finished since the
  /// last one, or at the end of a level that took longer than [longLevel]. When
  /// both apply it is put down to [everyN], so that `long_level` counts only
  /// the ads that rule adds.
  ///
  /// Levels below [minLevel] still count toward [everyN], so a new player's
  /// first ad comes at the end of level 5 itself rather than at 6. Nothing here
  /// restarts the count; only an ad that actually showed does, so an ad that
  /// was due but did not load is still due at the next level end.
  static AdBreak? noteLevelCompleted({
    required int levelNumber,
    required Duration timeOnLevel,
  }) {
    _levelsSinceAd++;
    if (levelNumber < minLevel) return null;
    if (_adThisLevel) return null;
    final last = _lastAdAt;
    if (last != null && _clock().difference(last) < minGap) return null;
    if (_levelsSinceAd >= everyN) return AdBreak.betweenLevels;
    if (timeOnLevel > longLevel) return AdBreak.longLevel;
    return null;
  }

  /// Tests only: where [minGap] reads the time from.
  static void setClockForTest(DateTime Function() clock) => _clock = clock;

  /// Tests only — the state is otherwise process-global for the session.
  static void resetForTest() {
    _levelsSinceAd = 0;
    _lastAdAt = null;
    _adThisLevel = false;
    _clock = DateTime.now;
  }
}
