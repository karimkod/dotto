// Consent, via Google's User Messaging Platform.
//
// UMP is Google's own certified CMP, which is what AdMob's EU user consent
// policy requires for EEA/UK traffic — a hand-built screen does not qualify,
// however carefully worded, and Dotto ships in France. It replaced exactly such
// a screen here.
//
// What that buys, beyond compliance: UMP owns the consent state and emits the
// Consent Mode v2 signals itself, straight to the SDKs. There is no
// setConsent() call in this codebase any more, and no npa flag on ad requests —
// both would now be a second, competing source of truth for something UMP
// already knows. The only state kept locally is whether the pre-prompt has been
// shown, which is a UX detail rather than a consent record.
//
// Everything is best-effort. If UMP cannot be reached, [canRequestAds] falls
// back to true so the game still serves ads outside the EEA rather than going
// dark on a network error — UMP itself returns "not required" for most of the
// world, so a failure there is far more likely to be transport than refusal.

import 'dart:async';
import 'dart:io' show Platform;

import 'package:app_tracking_transparency/app_tracking_transparency.dart';
import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../analytics/analytics_service.dart';

class ConsentManager {
  ConsentManager._();

  /// Whether the pre-prompt has been shown. Not a consent record — UMP holds
  /// that — just a note so a returning player is not re-introduced to the app.
  static const _prePromptKey = 'consent_prompt_seen';

  static SharedPreferences? _prefs;
  static bool _prePromptSeen = false;
  static bool _canRequestAds = false;

  /// Whether ads may be requested at all. False until UMP has been asked.
  static bool get canRequestAds => _canRequestAds;

  /// Whether to open on the pre-prompt.
  ///
  /// Only when UMP actually has a form to show — outside the EEA there is
  /// nothing behind the Continue button, and a screen that explains a choice
  /// the player will never be offered is worse than no screen.
  static bool _formAvailable = false;
  static bool get needsPrePrompt =>
      _supported && !_prePromptSeen && _formAvailable;

  static bool get _supported {
    if (kIsWeb) return false;
    if (Platform.environment.containsKey('FLUTTER_TEST')) return false;
    return Platform.isAndroid || Platform.isIOS;
  }

  /// Devices that should be treated as if they were in the EEA, so the form can
  /// be exercised from outside it.
  ///
  /// Empty by design: the id is printed by the SDK on first run — look for
  /// "Use ConsentDebugSettings.testIdentifiers" in logcat or the Xcode console
  /// — and is specific to a device and install. Debug builds only; these
  /// settings are ignored in release, so a stray id here cannot affect players.
  static const List<String> _testDeviceIds = <String>[];

  /// Ask UMP what this user needs, and load the answer.
  ///
  /// Safe to call at launch: it is a network round trip, but nothing blocks on
  /// it except the decision of which screen to open.
  static Future<void> init() async {
    try {
      _prefs = await SharedPreferences.getInstance();
      _prePromptSeen = _prefs?.getBool(_prePromptKey) ?? false;
    } catch (_) {
      // No storage. The pre-prompt may be shown twice; harmless.
    }
    if (!_supported) return;

    final params = ConsentRequestParameters(
      consentDebugSettings: kDebugMode && _testDeviceIds.isNotEmpty
          ? ConsentDebugSettings(
              debugGeography: DebugGeography.debugGeographyEea,
              testIdentifiers: _testDeviceIds,
            )
          : null,
    );

    final done = Completer<void>();
    try {
      ConsentInformation.instance.requestConsentInfoUpdate(
        params,
        () async {
          try {
            _formAvailable =
                await ConsentInformation.instance.isConsentFormAvailable();
            _canRequestAds = await ConsentInformation.instance.canRequestAds();
          } catch (e) {
            debugPrint('Consent status read failed: $e');
            _canRequestAds = true;
          }
          if (!done.isCompleted) done.complete();
        },
        (error) {
          // Region lookup failed. Outside the EEA UMP reports "not required"
          // anyway, so treating a transport error as "no form, ads allowed"
          // keeps the game working where consent was never needed. It does mean
          // an EEA user with a broken connection could see an ad before the
          // form — Google's own reference flow makes the same trade.
          debugPrint('Consent info update failed: ${error.message}');
          _canRequestAds = true;
          if (!done.isCompleted) done.complete();
        },
      );
    } catch (e) {
      debugPrint('UMP unavailable: $e');
      _canRequestAds = true;
      if (!done.isCompleted) done.complete();
    }

    // Never let a consent service that does not answer hold up the first frame.
    await done.future.timeout(
      const Duration(seconds: 8),
      onTimeout: () {
        debugPrint('Consent request timed out; carrying on');
        _canRequestAds = true;
      },
    );
  }

  /// Show the UMP form if one is required, then re-read whether ads may run.
  ///
  /// Resolves when the form is dismissed — or immediately, if none was needed.
  ///
  /// [duringOnboarding] gates the funnel events. Settings → Ad preferences
  /// calls this too, and a returning player changing their mind is not part of
  /// the first-launch funnel — counting it there would inflate a step that is
  /// supposed to measure new players only.
  static Future<void> showFormIfRequired({
    bool duringOnboarding = false,
  }) async {
    if (!_supported) return;
    if (duringOnboarding) Analytics.onboardingUmpShown();
    final done = Completer<void>();
    try {
      await ConsentForm.loadAndShowConsentFormIfRequired((error) {
        if (error != null) debugPrint('Consent form error: ${error.message}');
        if (!done.isCompleted) done.complete();
      });
    } catch (e) {
      debugPrint('Consent form failed: $e');
      if (!done.isCompleted) done.complete();
    }
    await done.future.timeout(const Duration(seconds: 60), onTimeout: () {
      debugPrint('Consent form never dismissed; carrying on');
    });
    try {
      _canRequestAds = await ConsentInformation.instance.canRequestAds();
    } catch (_) {
      _canRequestAds = true;
    }
    if (duringOnboarding) Analytics.onboardingUmpCompleted();
  }

  /// Remember that the pre-prompt has been shown.
  static Future<void> markPrePromptSeen() async {
    _prePromptSeen = true;
    final prefs = _prefs;
    if (prefs == null) return;
    unawaited(prefs.setBool(_prePromptKey, true).catchError((_) => false));
  }

  /// Settings → Ad preferences: wipe UMP's record and ask again.
  ///
  /// No pre-prompt this time. A player who went looking for this screen has
  /// already been told what it is for, and an explainer in front of a form they
  /// asked for is friction.
  ///
  /// The reset is deliberate rather than incidental: without it UMP considers
  /// consent obtained and shows nothing, which is indistinguishable from a
  /// broken button.
  static Future<void> reopenForm() async {
    if (!_supported) return;
    try {
      await ConsentInformation.instance.reset();
    } catch (e) {
      debugPrint('Consent reset failed: $e');
      return;
    }
    await init();
    await showFormIfRequired();
  }

  /// Apple's tracking prompt. iOS only, and only ever meaningful once.
  ///
  /// After the UMP form, not beside it: two consent dialogs at once reads as a
  /// wall of permissions, and Apple's own guidance is to explain before asking.
  /// UMP's answer does not decide this one — Apple requires the prompt before
  /// the IDFA may be read at all, whatever was agreed for GDPR.
  static Future<void> requestTrackingAuthorization() async {
    if (kIsWeb) return;
    if (Platform.environment.containsKey('FLUTTER_TEST')) return;
    if (!Platform.isIOS) return;
    try {
      final status = await AppTrackingTransparency.trackingAuthorizationStatus;
      // Only `notDetermined` can be asked. Every other state is settled, and
      // asking again just returns the same answer without showing anything.
      if (status == TrackingStatus.notDetermined) {
        // A beat after the form dismisses, so the system sheet does not arrive
        // on top of a disappearing route.
        await Future.delayed(const Duration(milliseconds: 250));
        Analytics.onboardingAttShown();
        final result =
            await AppTrackingTransparency.requestTrackingAuthorization();
        // Only `authorized` is a yes. Restricted means a policy said no on the
        // player's behalf, which counts the same way from here.
        if (result == TrackingStatus.authorized) {
          Analytics.onboardingAttAccepted();
        } else {
          Analytics.onboardingAttDenied();
        }
      }
    } catch (e) {
      // Denied, restricted, or unavailable all mean the same thing here: no
      // IDFA. Ads still serve, contextually.
      debugPrint('ATT request failed: $e');
    }
  }

  /// Tests only.
  @visibleForTesting
  static void resetForTest() {
    _prePromptSeen = false;
    _formAvailable = false;
    _canRequestAds = false;
    _prefs = null;
  }

  /// Tests only: set state without touching the platform.
  @visibleForTesting
  static void setForTest({
    bool prePromptSeen = false,
    bool formAvailable = false,
    bool canRequestAds = false,
  }) {
    _prePromptSeen = prePromptSeen;
    _formAvailable = formAvailable;
    _canRequestAds = canRequestAds;
  }
}
