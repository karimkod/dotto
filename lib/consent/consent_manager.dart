// What the player agreed to, and telling Google about it.
//
// COMPLIANCE NOTE, worth reading before trusting this. Dotto's consent screen
// is hand-built. Google's EU user consent policy requires publishers serving
// ads to EEA/UK users to use a Google-certified CMP integrated with the IAB
// TCF; a custom screen is not one, however carefully worded. The UMP SDK
// bundled with google_mobile_ads is Google's own certified CMP and is free.
// What is here satisfies Consent Mode mechanically — the signals are set
// correctly and honoured — but it is not the certified consent flow AdMob asks
// for in Europe, and Dotto targets France. Treat this as the app's own
// preference screen and add UMP before serving EEA traffic at scale.
//
// The mechanics themselves are conventional. Consent Mode v2 has four signals;
// Dotto uses them like this:
//
//   analytics_storage    always granted — the game only measures itself
//   ad_storage           always granted — needed to show any ad at all
//   ad_user_data         granted only for personalized
//   ad_personalization   granted only for personalized
//
// "Standard Ads" therefore still shows ads and still measures the game; what it
// withholds is sending the player's data to Google for ad targeting.

import 'dart:async';
import 'dart:io' show Platform;

import 'package:app_tracking_transparency/app_tracking_transparency.dart';
import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum AdConsent { personalized, standard }

class ConsentManager {
  ConsentManager._();

  static const _givenKey = 'consent_given';
  static const _personalizedKey = 'consent_personalized';
  static const _timestampKey = 'consent_timestamp';

  static SharedPreferences? _prefs;

  static bool _given = false;
  static bool _personalized = false;

  /// Whether the player has made a choice. Until they have, the app must not
  /// request a personalized ad.
  static bool get given => _given;

  static AdConsent get choice =>
      _personalized ? AdConsent.personalized : AdConsent.standard;

  /// The `npa` flag AdMob expects: "1" means non-personalized. Read by
  /// AdManager when it builds a request.
  static String get npa => _personalized ? '0' : '1';

  /// Web has no AdMob and no ATT, so it never asks. `flutter test` has no
  /// plugin host.
  static bool get needsConsentUi {
    if (kIsWeb) return false;
    if (Platform.environment.containsKey('FLUTTER_TEST')) return false;
    return (Platform.isAndroid || Platform.isIOS) && !_given;
  }

  /// Load the saved choice. Must run before the first frame, since it decides
  /// whether the consent screen is the first thing shown.
  static Future<void> init() async {
    try {
      final prefs = _prefs = await SharedPreferences.getInstance();
      _given = prefs.getBool(_givenKey) ?? false;
      _personalized = prefs.getBool(_personalizedKey) ?? false;
    } catch (_) {
      // No storage: the player is asked again. Asking twice is a nuisance;
      // assuming consent that was never given is not an option.
    }
  }

  /// The state everything starts in: nothing granted for advertising.
  ///
  /// Called before Firebase starts, so no ad signal can leave the device ahead
  /// of a decision. Analytics storage is granted from the outset because Dotto
  /// measures only its own use — no ad identifier is involved — and denying it
  /// by default would lose first-open and session data that no consent regime
  /// requires withholding.
  static Future<void> applyDefaults() async {
    await _setConsent(adUserData: false, adPersonalization: false);
  }

  /// Record a choice and push it to Google immediately.
  static Future<void> choose(AdConsent consent) async {
    _given = true;
    _personalized = consent == AdConsent.personalized;

    final prefs = _prefs;
    if (prefs != null) {
      unawaited(prefs.setBool(_givenKey, true).catchError((_) => false));
      unawaited(prefs
          .setBool(_personalizedKey, _personalized)
          .catchError((_) => false));
      unawaited(prefs
          .setInt(_timestampKey, DateTime.now().millisecondsSinceEpoch)
          .catchError((_) => false));
    }

    await _setConsent(
      adUserData: _personalized,
      adPersonalization: _personalized,
    );
  }

  static Future<void> _setConsent({
    required bool adUserData,
    required bool adPersonalization,
  }) async {
    if (kIsWeb) return;
    try {
      await FirebaseAnalytics.instance.setConsent(
        analyticsStorageConsentGranted: true,
        adStorageConsentGranted: true,
        adUserDataConsentGranted: adUserData,
        adPersonalizationSignalsConsentGranted: adPersonalization,
      );
    } catch (e) {
      // Firebase may not have started yet, or at all. The npa flag on each ad
      // request still carries the choice, so the player's decision is honoured
      // either way.
      debugPrint('Consent Mode update failed: $e');
    }
  }

  /// Apple's tracking prompt. iOS only, and only meaningful once.
  ///
  /// Deliberately independent of the GDPR choice: Apple requires the prompt
  /// before the IDFA may be read at all, whatever the player picked here. A
  /// player who chose Standard Ads and then allows tracking still gets
  /// non-personalized ads — the stricter of the two answers wins, which is the
  /// only defensible way to combine them.
  static Future<void> requestTrackingAuthorization() async {
    if (kIsWeb) return;
    if (Platform.environment.containsKey('FLUTTER_TEST')) return;
    if (!Platform.isIOS) return;
    try {
      final status =
          await AppTrackingTransparency.trackingAuthorizationStatus;
      // Only `notDetermined` can be asked. The rest are already settled, and
      // asking again does nothing but return the same answer.
      if (status == TrackingStatus.notDetermined) {
        // A beat after the consent screen dismisses, so the system sheet does
        // not arrive on top of a disappearing route.
        await Future.delayed(const Duration(milliseconds: 250));
        await AppTrackingTransparency.requestTrackingAuthorization();
      }
    } catch (e) {
      // Denied, restricted, or unavailable — all mean the same thing here: no
      // IDFA. Ads still serve, contextually.
      debugPrint('ATT request failed: $e');
    }
  }

  /// Tests only.
  @visibleForTesting
  static void resetForTest() {
    _given = false;
    _personalized = false;
    _prefs = null;
  }

  /// Tests only: set state without touching storage or Firebase.
  @visibleForTesting
  static void setForTest({required bool given, required bool personalized}) {
    _given = given;
    _personalized = personalized;
  }
}
