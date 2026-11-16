// AdMob: initialisation, and the two ad formats Dotto uses.
//
// Consent is handled by UMP in lib/consent/consent_manager.dart. Nothing here
// carries a consent flag: UMP owns that state and the SDK reads it directly.
// What this file must respect is the gate — no ad request before UMP reports
// that ads may be requested.
//
// THE IDS BELOW ARE LIVE. Every impression they serve is real, counted against
// a real account, and the same is true of the app ids in AndroidManifest.xml
// and Info.plist. Two consequences worth keeping in mind while developing:
//
//   * Tapping your own ads, or letting a debug build request them repeatedly,
//     is invalid traffic. Google's response is to suspend the account, not to
//     discard the clicks. Emulators and simulators are recognised as test
//     devices automatically, so they are safe; a physical phone running a debug
//     build is not, until it is registered as a test device with its device id
//     via MobileAds.instance.updateRequestConfiguration.
//   * A brand-new unit serves nothing for a few hours after creation, so an
//     empty ad is not automatically a bug in this file.
//
// Everything here fails soft. Ads are a side channel: if the SDK will not
// initialise, or no ad fills, or the player is offline, the game must carry on.
// The one rule that is NOT soft is the reward: [showRewarded] resolves true
// only when AdMob actually reports the reward earned, so a player who closes an
// ad early does not get paid.

import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import '../analytics/analytics_service.dart';


class AdManager {
  AdManager._();

  /// Report what an impression earned, for GA4's ad-revenue metrics.
  ///
  /// Attached to every ad as it loads rather than as it shows: the callback can
  /// arrive after the ad is dismissed and disposed, and an ad that was never
  /// given the listener simply never reports. [format] is the GA4 ad format
  /// name, [unitId] the AdMob unit so revenue can be split by placement.
  ///
  /// AdMob hands out micros — a millionth of a currency unit — and GA4 wants
  /// whole units, so the division belongs here, once, next to the SDK that
  /// chose the unit. See [Analytics.adImpression] for why sending the raw
  /// number would be wrong in a way nothing would flag.
  ///
  /// Worth knowing before reading the numbers: the paid-event callback is only
  /// populated for accounts Google has enabled it for. Where it is not, this
  /// never fires and ad revenue stays empty — which looks identical to no ads
  /// having served, so check impressions before concluding anything.
  static void _reportPaid(Ad ad, String format, String unitId) {
    (ad as AdWithoutView).onPaidEvent =
        (_, valueMicros, precision, currencyCode) {
      Analytics.adImpression(
        format: format,
        adUnitName: unitId,
        value: valueMicros / 1000000.0,
        currency: currencyCode,
        precision: precision.name,
      );
    };
  }

  /// Whether ads can run at all. Ads are a mobile-only concern here: the web
  /// build has no AdMob SDK, and `flutter test` has no plugin host.
  static bool get supported {
    if (kIsWeb) return false;
    if (Platform.environment.containsKey('FLUTTER_TEST')) return false;
    return Platform.isAndroid || Platform.isIOS;
  }

  static bool _ready = false;
  static bool get ready => _ready;

  // ----- unit ids -----
  //
  // Live units on the Dotto AdMob account, one pair per platform. A unit id is
  // tied to the app id in AndroidManifest.xml / Info.plist, so an Android unit
  // requested under the iOS app id (or the reverse) simply never fills — hence
  // the platform switch rather than one shared constant.

  static String get _rewardedUnitId => !kIsWeb && Platform.isAndroid
      ? 'ca-app-pub-3605343790686215/6607406377'
      : 'ca-app-pub-3605343790686215/9812154217';

  static String get _interstitialUnitId => !kIsWeb && Platform.isAndroid
      ? 'ca-app-pub-3605343790686215/9149809232'
      : 'ca-app-pub-3605343790686215/8766665850';

  /// Start the SDK and warm both ad caches.
  ///
  /// Callers must not reach here until UMP reports that ads may be requested —
  /// main() and the consent screen are the two places that check. Requests
  /// carry no consent flag of their own: UMP holds the consent state and the
  /// SDK reads it directly, so an npa extra here would be a second, competing
  /// source of truth for something already decided.
  static Future<void> init() async {
    if (!supported || _ready) return;
    try {
      await MobileAds.instance.initialize();
      _ready = true;
      unawaited(_loadRewarded());
      unawaited(_loadInterstitial());
    } catch (e) {
      // Leaving _ready false means every show() below turns into a no-op.
      debugPrint('AdMob init failed, continuing without ads: $e');
    }
  }

  // ----- rewarded (hints) -----

  static RewardedAd? _rewarded;
  static bool _loadingRewarded = false;

  static Future<void> _loadRewarded() async {
    if (!_ready || _rewarded != null || _loadingRewarded) return;
    _loadingRewarded = true;
    await RewardedAd.load(
      adUnitId: _rewardedUnitId,
      request: const AdRequest(),
      rewardedAdLoadCallback: RewardedAdLoadCallback(
        onAdLoaded: (ad) {
          _reportPaid(ad, 'rewarded', _rewardedUnitId);
          _rewarded = ad;
          _loadingRewarded = false;
        },
        onAdFailedToLoad: (err) {
          debugPrint('Rewarded ad failed to load: $err');
          _rewarded = null;
          _loadingRewarded = false;
        },
      ),
    );
  }

  /// True when a rewarded ad is cached and could be shown right now.
  static bool get rewardedReady => _rewarded != null;

  /// Whether a rewarded ad could actually be served this second.
  ///
  /// The one question callers should ask. "Ads do not run on this platform",
  /// "the SDK never started" and "nothing is cached" are three different
  /// stories that leave the player in exactly the same place, and anything
  /// offering an ad in trade has to know that BEFORE it makes the offer.
  static bool get rewardedAvailable =>
      _rewardedStub != null || (supported && rewardedReady);

  /// Tests only: stands in for the SDK, returning what the "reward earned"
  /// callback would have reported.
  ///
  /// [supported] is false under `flutter test`, so without this seam the whole
  /// rewarded path is unreachable there — which matters now that an ad which
  /// does not play means no hint. Pass null to put the real SDK back.
  static Future<bool> Function()? _rewardedStub;

  @visibleForTesting
  static void stubRewardedForTest(Future<bool> Function()? earns) {
    _rewardedStub = earns;
  }

  /// Show a rewarded ad; resolves true only if the reward was actually earned.
  ///
  /// Returns false when there is no ad to show, so the caller can decide what a
  /// player who cannot be served an ad deserves — never leave them stuck behind
  /// an ad that will not come.
  static Future<bool> showRewarded() async {
    final stub = _rewardedStub;
    if (stub != null) return stub();
    if (!_ready) return false;
    final ad = _rewarded;
    if (ad == null) {
      unawaited(_loadRewarded()); // try to have one ready next time
      return false;
    }
    _rewarded = null; // a loaded ad is single-use

    var earned = false;
    final closed = Completer<void>();
    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (ad) {
        ad.dispose();
        unawaited(_loadRewarded());
        if (!closed.isCompleted) closed.complete();
      },
      onAdFailedToShowFullScreenContent: (ad, err) {
        debugPrint('Rewarded ad failed to show: $err');
        ad.dispose();
        unawaited(_loadRewarded());
        if (!closed.isCompleted) closed.complete();
      },
    );

    await ad.show(onUserEarnedReward: (_, _) => earned = true);
    await closed.future;
    return earned;
  }

  // ----- interstitial (reserved for the fail counter) -----

  static InterstitialAd? _interstitial;
  static bool _loadingInterstitial = false;

  static Future<void> _loadInterstitial() async {
    if (!_ready || _interstitial != null || _loadingInterstitial) return;
    _loadingInterstitial = true;
    await InterstitialAd.load(
      adUnitId: _interstitialUnitId,
      request: const AdRequest(),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (ad) {
          _reportPaid(ad, 'interstitial', _interstitialUnitId);
          _interstitial = ad;
          _loadingInterstitial = false;
        },
        onAdFailedToLoad: (err) {
          debugPrint('Interstitial failed to load: $err');
          _interstitial = null;
          _loadingInterstitial = false;
        },
      ),
    );
  }

  /// Show a cached interstitial if there is one. Returns whether it showed.
  ///
  /// Nothing calls this yet — it is here so the planned "after N failures"
  /// break has a loaded ad waiting rather than a cold start at the moment it is
  /// wanted.
  static Future<bool> showInterstitial() async {
    if (!_ready) return false;
    final ad = _interstitial;
    if (ad == null) {
      unawaited(_loadInterstitial());
      return false;
    }
    _interstitial = null;

    final closed = Completer<void>();
    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (ad) {
        ad.dispose();
        unawaited(_loadInterstitial());
        if (!closed.isCompleted) closed.complete();
      },
      onAdFailedToShowFullScreenContent: (ad, err) {
        debugPrint('Interstitial failed to show: $err');
        ad.dispose();
        unawaited(_loadInterstitial());
        if (!closed.isCompleted) closed.complete();
      },
    );
    await ad.show();
    await closed.future;
    return true;
  }
}
