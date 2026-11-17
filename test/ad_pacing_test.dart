// How often a player gets interrupted. These rules are the part of the ad
// system that can actually be wrong in a way a player would feel, and the part
// that can be tested — AdManager itself is inert under test, so the pacing
// lives apart from it precisely so this file can exist.

import 'package:flutter_test/flutter_test.dart';

import 'package:dotto/ads/ad_pacing.dart';

void main() {
  // The wall clock the gap between ads is read from, moved by hand.
  late DateTime now;

  setUp(() {
    AdPacing.resetForTest();
    now = DateTime(2026, 11, 17, 12);
    AdPacing.setClockForTest(() => now);
  });

  /// Play one level the way the game screen reports it: started, [took] long,
  /// finished. Well past the threshold and a minute long unless told otherwise.
  AdBreak? finish({
    int level = 20,
    Duration took = const Duration(minutes: 1),
  }) {
    AdPacing.noteLevelStarted();
    now = now.add(took);
    return AdPacing.noteLevelCompleted(levelNumber: level, timeOnLevel: took);
  }

  /// Play [n] one-minute levels, showing every ad that comes due.
  /// Returns which of them (1-based) ended on one.
  List<int> session(int n) {
    final ads = <int>[];
    for (var i = 1; i <= n; i++) {
      if (finish() != null) {
        AdPacing.noteAdShown();
        ads.add(i);
      }
    }
    return ads;
  }

  group('the opening levels are ad-free', () {
    test('nothing fires below level 5, however long a level takes', () {
      final due = [
        for (var level = 1; level < AdPacing.minLevel; level++)
          finish(level: level, took: const Duration(minutes: 10)),
      ];
      expect(due, everyElement(isNull),
          reason: 'the early game is where a player decides whether to stay');
    });

    test("a new player's first ad comes at the end of level 5", () {
      // Levels 1-4 count toward the two-level beat even though they can never
      // end on an ad, so level 5 arrives with the beat already due.
      for (var level = 1; level < AdPacing.minLevel; level++) {
        finish(level: level);
      }
      expect(finish(level: AdPacing.minLevel), AdBreak.betweenLevels);
    });
  });

  group('every two levels', () {
    test('an ad ends every second level', () {
      expect(session(8), [2, 4, 6, 8]);
    });

    test('a long session stays at one ad per two levels', () {
      // Guards against an off-by-one in the count quietly doubling the rate.
      final ads = session(30);
      expect(ads, hasLength(15));
      expect(ads.first, 2);
      expect(ads.last, 30);
    });

    test('an ad that did not show is still due at the next level end', () {
      finish();
      expect(finish(), AdBreak.betweenLevels); // due, but nothing filled
      expect(finish(), AdBreak.betweenLevels,
          reason: 'only an ad that actually showed restarts the count');
    });
  });

  group('long levels', () {
    test('a level over three minutes ends on an ad, off the beat', () {
      session(2); // an ad at the end of the second level
      expect(finish(took: const Duration(minutes: 3, seconds: 1)),
          AdBreak.longLevel);
    });

    test('three minutes exactly is not over three minutes', () {
      session(2);
      expect(finish(took: AdPacing.longLevel), isNull);
    });

    test('a long level that is due anyway is put down to the beat', () {
      // So that long_level in analytics counts only the ads that rule adds.
      session(2);
      finish();
      expect(finish(took: const Duration(minutes: 5)), AdBreak.betweenLevels);
    });

    test('the count restarts after a long-level ad', () {
      session(2);
      expect(finish(took: const Duration(minutes: 4)), AdBreak.longLevel);
      AdPacing.noteAdShown();
      // Two minutes, so that the gap is not what holds this one back.
      expect(finish(took: const Duration(minutes: 2)), isNull,
          reason: 'a long level and the one after it must not both end on an '
              'ad');
      expect(finish(), AdBreak.betweenLevels);
    });
  });

  group('the gap between ads', () {
    test('quick levels after an ad wait out the gap, then have it', () {
      session(2);
      expect(finish(took: const Duration(seconds: 30)), isNull);
      expect(finish(took: const Duration(seconds: 30)), isNull,
          reason: 'two levels since the ad, but only a minute');
      expect(finish(took: const Duration(seconds: 40)), AdBreak.betweenLevels,
          reason: 'held back, not dropped');
    });

    test('ninety seconds exactly is enough', () {
      session(2);
      finish(took: const Duration(seconds: 45));
      expect(finish(took: const Duration(seconds: 45)), AdBreak.betweenLevels);
    });

    test('there is no gap to wait out before the first ad', () {
      // The gap is between ads, and a session that has shown none has nothing
      // for the next one to be close to.
      finish(took: const Duration(seconds: 10));
      expect(finish(took: const Duration(seconds: 10)), AdBreak.betweenLevels);
    });
  });

  group('hint videos', () {
    test('one spares its level the ad, however long the level ran', () {
      session(2);
      AdPacing.noteLevelStarted();
      now = now.add(const Duration(minutes: 1));
      AdPacing.noteAdShown(); // the hint video, a minute in
      now = now.add(const Duration(minutes: 4));
      expect(
          AdPacing.noteLevelCompleted(
              levelNumber: 20, timeOnLevel: const Duration(minutes: 5)),
          isNull,
          reason: 'two ads around one level is too many');
    });

    test('one counts as an ad for the gap and the count', () {
      finish();
      AdPacing.noteLevelStarted();
      AdPacing.noteAdShown(); // the hint video, as the level opens
      now = now.add(const Duration(seconds: 30));
      AdPacing.noteLevelCompleted(
          levelNumber: 20, timeOnLevel: const Duration(seconds: 30));
      expect(AdPacing.levelsSinceAd, 1,
          reason: 'the level before the video no longer counts');
      expect(finish(took: const Duration(seconds: 30)), isNull,
          reason: 'two levels since the video, but only a minute');
      expect(finish(took: const Duration(seconds: 40)), AdBreak.betweenLevels);
    });

    test('one on a level does not spare the next', () {
      AdPacing.noteLevelStarted();
      AdPacing.noteAdShown();
      now = now.add(const Duration(minutes: 2));
      AdPacing.noteLevelCompleted(
          levelNumber: 20, timeOnLevel: const Duration(minutes: 2));
      expect(finish(took: const Duration(minutes: 4)), AdBreak.betweenLevels);
    });
  });

  test('the count covers every level finished since the last ad', () {
    finish(level: 1);
    finish(level: 2, took: const Duration(minutes: 5));
    finish();
    expect(AdPacing.levelsSinceAd, 3,
        reason: 'counted whatever kept each level from ending on an ad');
    AdPacing.noteAdShown();
    expect(AdPacing.levelsSinceAd, 0);
  });
}
