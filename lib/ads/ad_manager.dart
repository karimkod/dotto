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


class AdManager {
  AdManager._();

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

  /// Show a rewarded ad; resolves true only if the reward was actually earned.
  ///
  /// Returns false when there is no ad to show, so the caller can decide what a
  /// player who cannot be served an ad deserves — never leave them stuck behind
  /// an ad that will not come.
  static Future<bool> showRewarded() async {
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
