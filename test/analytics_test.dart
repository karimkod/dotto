// Analytics observes the game; it must never be able to affect it. With no
// Firebase config in the repo, initialisation fails by design — so what is
// pinned here is that failing costs nothing, and that no event call throws when
// the SDK was never started.

import 'package:flutter_test/flutter_test.dart';

import 'package:dotto/analytics/analytics_service.dart';
import 'package:dotto/data/levels.dart';

void main() {
  test('analytics stands down where there is no Firebase to talk to', () {
    // kIsWeb is checked before dart:io, which is what keeps the web build from
    // calling Platform on a platform that has no Platform.
    expect(Analytics.supported, isFalse);
    expect(Analytics.enabled, isFalse);
  });

  test('init is a no-op rather than a crash when unconfigured', () async {
    // main() fires this before runApp; anything it throws kills the launch.
    await expectLater(Analytics.init(), completes);
    expect(Analytics.enabled, isFalse);
  });

  test('every event is safe to call with analytics switched off', () {
    // These run on the hot paths — level load, win, loss, hint — so a throw
    // here would surface as a broken game rather than a missing statistic.
    expect(() {
      Analytics.levelStart(1, 1);
      Analytics.levelComplete(1, 1, timeSeconds: 12, hintsUsed: 0);
      Analytics.levelFail(1, 1, 2);
      Analytics.levelSkip(1, 1);
      Analytics.hintUsed(1, 1, 'free');
      Analytics.hintAdWatched(1, 1);
      Analytics.hintAdDismissed(1, 1);
      Analytics.rewardedAdShown(1);
      Analytics.interstitialShown(1, 'fail_counter');
      Analytics.interstitialClicked(1);
      Analytics.worldUnlocked(2);
      Analytics.gameCompleted();
      Analytics.levelDesignerOpened();
      Analytics.setProgress(levelsCompleted: 3, currentWorld: 1);
      Analytics.setHintsUsedTotal(4);
    }, returnsNormally);
  });

  group('worldOf', () {
    test('maps each world to its own range', () {
      expect(worldOf(1), 1);
      expect(worldOf(kWorld2Start - 1), 1);
      expect(worldOf(kWorld2Start), 2);
      expect(worldOf(kWorld3Start), 3);
      expect(worldOf(kWorld4Start), 4);
      expect(worldOf(kWorld5Start), 5);
      expect(worldOf(kWorld6Start), 6);
      expect(worldOf(kWorld7Start), 7);
      expect(worldOf(kLevelCount), 7);
    });

    test('the Master Trials count as World 5', () {
      // 61–70 revisit World 5's pieces rather than introducing any, so they are
      // grouped with it. The test suite's own worldOf splits them out instead —
      // the two disagree here deliberately.
      expect(worldOf(61), 5);
      expect(worldOf(70), 5);
    });

    test('a world boundary is exactly where the next world starts', () {
      // What drives the world_unlocked event: the level before a world's first
      // level must report a different world from it.
      for (final start in [
        kWorld2Start,
        kWorld3Start,
        kWorld4Start,
        kWorld5Start,
        kWorld6Start,
        kWorld7Start,
      ]) {
        expect(worldOf(start - 1), isNot(worldOf(start)),
            reason: 'finishing level ${start - 1} should unlock a new world');
      }
    });
  });
}
