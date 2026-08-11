// How often a player gets interrupted. These rules are the part of the ad
// system that can actually be wrong in a way a player would feel, and the part
// that can be tested — AdManager itself is inert under test, so the pacing
// lives apart from it precisely so this file can exist.

import 'package:flutter_test/flutter_test.dart';

import 'package:dotto/ads/ad_pacing.dart';

void main() {
  setUp(AdPacing.resetForTest);

  /// Complete [n] levels, hint-free, all well past the level threshold.
  /// Returns which completions were told an interstitial was due (1-based).
  List<int> runClean(int n) => [
        for (var i = 1; i <= n; i++)
          if (AdPacing.noteLevelCompleted(
              levelId: AdPacing.minLevel + i, usedHint: false))
            i,
      ];

  group('the opening levels are ad-free', () {
    test('nothing fires below the threshold, however many are finished', () {
      // Nine completions is three cadence slots. All of them are suppressed
      // because of where the player is, not how many levels they have done.
      final due = [
        for (var level = 1; level < AdPacing.minLevel; level++)
          if (AdPacing.noteLevelCompleted(levelId: level, usedHint: false))
            level,
      ];
      expect(due, isEmpty,
          reason: 'the early game is where a player decides whether to stay');
    });

    test('the threshold level itself is eligible', () {
      // "level 10 or higher" includes 10.
      AdPacing.noteLevelCompleted(levelId: 1, usedHint: false); // 1
      AdPacing.noteLevelCompleted(levelId: 2, usedHint: false); // 2
      expect(
          AdPacing.noteLevelCompleted(
              levelId: AdPacing.minLevel, usedHint: false),
          isTrue); // 3
    });

    test('the level below the threshold is not', () {
      AdPacing.noteLevelCompleted(levelId: 1, usedHint: false); // 1
      AdPacing.noteLevelCompleted(levelId: 2, usedHint: false); // 2
      expect(
          AdPacing.noteLevelCompleted(
              levelId: AdPacing.minLevel - 1, usedHint: false),
          isFalse); // 3
    });

    test('early levels still count, so the threshold is not a fresh start', () {
      // Someone who plays 1–9 and then 10 has already used up two thirds of a
      // cadence slot; level 10 must not arrive as an immediate interruption.
      for (var level = 1; level < AdPacing.minLevel; level++) {
        AdPacing.noteLevelCompleted(levelId: level, usedHint: false);
      }
      expect(AdPacing.levelsCompletedThisSession, AdPacing.minLevel - 1);
      // The 9th completion was a multiple of three but below the threshold, so
      // the next ad is at the 12th — not on the very next level.
      expect(AdPacing.noteLevelCompleted(levelId: 10, usedHint: false), isFalse);
      expect(AdPacing.noteLevelCompleted(levelId: 11, usedHint: false), isFalse);
      expect(AdPacing.noteLevelCompleted(levelId: 12, usedHint: false), isTrue);
    });
  });

  group('cadence past the threshold', () {
    test('the first two completions are left alone', () {
      expect(runClean(2), isEmpty,
          reason: 'a player who has just started should not be interrupted');
    });

    test('an ad is due on every third level', () {
      expect(runClean(9), [3, 6, 9]);
    });

    test('a long clean session stays at one ad per three levels', () {
      // Guards against an off-by-one in the modulus quietly doubling the rate.
      final due = runClean(30);
      expect(due, hasLength(10));
      expect(due.first, 3);
      expect(due.last, 30);
    });
  });

  group('hints', () {
    test('taking a hint spares that level its ad', () {
      AdPacing.noteLevelCompleted(levelId: 20, usedHint: false); // 1
      AdPacing.noteLevelCompleted(levelId: 21, usedHint: false); // 2
      expect(AdPacing.noteLevelCompleted(levelId: 22, usedHint: true), isFalse,
          reason: 'a hint may already have cost a rewarded video — two ads '
              'around one level is too many');
    });

    test('a skipped slot is dropped, not deferred to the next level', () {
      AdPacing.noteLevelCompleted(levelId: 20, usedHint: false); // 1
      AdPacing.noteLevelCompleted(levelId: 21, usedHint: false); // 2
      AdPacing.noteLevelCompleted(levelId: 22, usedHint: true); // 3 — skipped
      expect(AdPacing.noteLevelCompleted(levelId: 23, usedHint: false), isFalse,
          reason: 'the fourth level must not inherit the third\'s ad');
      expect(
          AdPacing.noteLevelCompleted(levelId: 24, usedHint: false), isFalse);
      expect(AdPacing.noteLevelCompleted(levelId: 25, usedHint: false), isTrue,
          reason: 'the cadence stays on multiples of three');
    });

    test('a hinted level still counts toward the cadence', () {
      // Otherwise a player who hints often would drift out of the rhythm and
      // could go a long stretch with no ad at all.
      AdPacing.noteLevelCompleted(levelId: 20, usedHint: true); // 1
      AdPacing.noteLevelCompleted(levelId: 21, usedHint: true); // 2
      expect(AdPacing.levelsCompletedThisSession, 2);
      expect(AdPacing.noteLevelCompleted(levelId: 22, usedHint: false), isTrue);
    });
  });

  test('the counter tracks completions, whatever suppressed the ad', () {
    AdPacing.noteLevelCompleted(levelId: 1, usedHint: false); // below
    AdPacing.noteLevelCompleted(levelId: 2, usedHint: true); // below + hint
    AdPacing.noteLevelCompleted(levelId: 40, usedHint: true); // hint
    AdPacing.noteLevelCompleted(levelId: 41, usedHint: false);
    expect(AdPacing.levelsCompletedThisSession, 4);
  });
}
