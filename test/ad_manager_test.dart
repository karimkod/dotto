// Ads must never be able to break the game. The SDK is absent on web and has no
// plugin host under `flutter test`, so the guard that keeps AdManager inert on
// those platforms is the thing worth pinning: if it ever stops short-circuiting,
// launch itself starts throwing.

import 'package:flutter_test/flutter_test.dart';

import 'package:dotto/ads/ad_manager.dart';

void main() {
  test('ads stand down where there is no SDK to talk to', () {
    // Under test there is no plugin host; on web there is no AdMob at all. The
    // getter checks kIsWeb before it touches dart:io, which is what keeps the
    // web build from throwing on a Platform call that has no meaning there.
    expect(AdManager.supported, isFalse);
    expect(AdManager.ready, isFalse);
  });

  test('init is a no-op rather than a crash when unsupported', () async {
    // main() calls this before runApp, so anything it throws takes the whole
    // app down before the first frame.
    await expectLater(AdManager.init(), completes);
    expect(AdManager.ready, isFalse);
  });

  test('showing an ad that cannot exist reports failure, quietly', () async {
    // The hint flow reads these: false means "no ad was watched", and the
    // caller grants the hint anyway rather than stranding the player.
    expect(AdManager.rewardedReady, isFalse);
    await expectLater(AdManager.showRewarded(), completion(isFalse));
    await expectLater(AdManager.showInterstitial(), completion(isFalse));
  });
}
