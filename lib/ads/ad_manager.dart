// AdMob: initialisation, and the two ad formats Dotto uses.
//
// NO CONSENT FLOW YET. There is no UMP handling here, so this must not reach
// players as it stands — Dotto targets France, GDPR applies, and ads are being
// requested with no consent decision recorded. See init() for where it goes.
//
// EVERY ID IN THIS FILE IS A GOOGLE TEST ID. They serve test ads to anyone and
// earn nothing; the real ones come from the AdMob console and must replace both
// these unit ids and the app ids in AndroidManifest.xml and Info.plist at the
// same time. Do not point a debug build at the real ids — Google reads that as
// invalid traffic and can suspend the account.
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

  // ----- test unit ids -----

  static String get _rewardedUnitId => Platform.isAndroid
      ? 'ca-app-pub-3940256099942544/5224354917'
      : 'ca-app-pub-3940256099942544/1712485313';

  static String get _interstitialUnitId => Platform.isAndroid
      ? 'ca-app-pub-3940256099942544/1033173712'
      : 'ca-app-pub-3940256099942544/4411468910';

  /// Start the SDK and warm both ad caches.
  ///
  /// No consent flow yet. UMP is deliberately left out for now and has to be
  /// added before this ships to players: Dotto targets France, so GDPR applies,
  /// and requesting ads there without a consent decision on record is not
  /// something to leave to launch day. The hook belongs here, ahead of
  /// initialize(), because the form has to be answered before personalised ads
  /// may be requested.
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
