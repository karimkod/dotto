// Firebase Analytics: every event the game reports, in one place.
//
// Configured against project dotto-d817e: lib/firebase_options.dart supplies
// the options, with android/app/google-services.json and
// ios/Runner/GoogleService-Info.plist alongside as the native config. All three
// carry the same ids and have to change together — see docs/firebase-setup.md.
//
// Reporting is still best-effort by design. Analytics is an observer, and an
// observer that can break the thing it observes is worse than no observer, so
// every log is fire-and-forget, wrapped, and impossible to await from the game
// code: a slow network, a device without Play Services, or a project that stops
// answering costs statistics and nothing else. [enabled] says whether anything
// is actually being recorded.
//
// Event and parameter names follow Firebase's rules, which are not advisory:
// names are limited to 40 characters, parameters to 100, both must be
// snake_case and start with a letter, and 'firebase_'/'google_'/'ga_' prefixes
// are reserved. A name that breaks a rule is dropped silently by the SDK — no
// error, no event — so they are written out as constants rather than built up
// from strings at the call site.

import 'dart:async';
import 'dart:io' show Platform;

import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

import '../firebase_options.dart';

class Analytics {
  Analytics._();

  /// Where analytics can run at all.
  ///
  /// Web is excluded because there is no config for it and no plan to ship one;
  /// `flutter test` because there is no plugin host to answer. Both would fail
  /// safely anyway — this just avoids the pointless attempt.
  static bool get supported {
    if (kIsWeb) return false;
    if (Platform.environment.containsKey('FLUTTER_TEST')) return false;
    return Platform.isAndroid || Platform.isIOS;
  }

  static FirebaseAnalytics? _analytics;

  /// True once Firebase has started and events are actually being recorded.
  static bool get enabled => _analytics != null;

  /// Start Firebase. Still guarded: a project can be configured and the start
  /// can fail anyway — a device with no Play Services, a clock far enough out
  /// to fail TLS — and none of that should cost the player their game.
  static Future<void> init() async {
    if (!supported || _analytics != null) return;
    try {
      // Options come from lib/firebase_options.dart rather than from the native
      // config, so initialisation does not depend on the Google Services Gradle
      // plugin having injected google-services.json into the Android build.
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
      _analytics = FirebaseAnalytics.instance;
    } catch (e) {
      debugPrint('Firebase init failed, analytics disabled: $e');
    }
  }

  /// The one place an event reaches the SDK. Everything is swallowed: a
  /// reporting failure must never surface as a game failure.
  static void _log(String name, [Map<String, Object>? params]) {
    final a = _analytics;
    if (a == null) return;
    unawaited(
      a.logEvent(name: name, parameters: params).catchError((Object e) {
        debugPrint('analytics: $name failed: $e');
      }),
    );
  }

  static void _setProperty(String name, String value) {
    final a = _analytics;
    if (a == null) return;
    unawaited(
      a.setUserProperty(name: name, value: value).catchError((Object e) {
        debugPrint('analytics: property $name failed: $e');
      }),
    );
  }

  // ----- game -----

  static void levelStart(int levelId, int worldId) =>
      _log('level_start', {'level_id': levelId, 'world_id': worldId});

  static void levelComplete(
    int levelId,
    int worldId, {
    required int timeSeconds,
    required int hintsUsed,
  }) =>
      _log('level_complete', {
        'level_id': levelId,
        'world_id': worldId,
        'time_seconds': timeSeconds,
        'hints_used': hintsUsed,
      });

  /// [attemptNumber] counts failures within this visit to the level, starting
  /// at 1 — which is what makes "how many tries does level 84 take" answerable.
  static void levelFail(int levelId, int worldId, int attemptNumber) =>
      _log('level_fail', {
        'level_id': levelId,
        'world_id': worldId,
        'attempt_number': attemptNumber,
      });

  /// Nothing calls this yet: there is no skip in the game. It is here so the
  /// event name is settled before the feature lands, rather than invented in a
  /// hurry beside it.
  static void levelSkip(int levelId, int worldId) =>
      _log('level_skip', {'level_id': levelId, 'world_id': worldId});

  // ----- hints -----

  /// [hintType] is 'free' or 'ad' — the two ways a hint can be paid for.
  static void hintUsed(int levelId, int worldId, String hintType) =>
      _log('hint_used', {
        'level_id': levelId,
        'world_id': worldId,
        'hint_type': hintType,
      });

  static void hintAdWatched(int levelId, int worldId) =>
      _log('hint_ad_watched', {'level_id': levelId, 'world_id': worldId});

  /// Covers both a player dismissing the video early and an ad that could not
  /// be served — from the player's side the outcome is the same: no reward.
  static void hintAdDismissed(int levelId, int worldId) =>
      _log('hint_ad_dismissed', {'level_id': levelId, 'world_id': worldId});

  // ----- ads -----

  static void rewardedAdShown(int levelId) =>
      _log('rewarded_ad_shown', {'level_id': levelId});

  /// [trigger] records why the break happened, so the fail-counter interstitial
  /// stays distinguishable from whatever triggers get added later.
  static void interstitialShown(int levelId, String trigger) =>
      _log('interstitial_shown', {'level_id': levelId, 'trigger': trigger});

  /// Unused: AdMob does not report clicks to the app, so this can only ever
  /// fire if a future SDK exposes them. Kept for the same reason as levelSkip.
  static void interstitialClicked(int levelId) =>
      _log('interstitial_clicked', {'level_id': levelId});

  // ----- progression -----

  static void worldUnlocked(int worldId) =>
      _log('world_unlocked', {'world_id': worldId});

  static void gameCompleted() => _log('game_completed');

  static void levelDesignerOpened() => _log('level_designer_opened');

  // ----- onboarding funnel -----
  //
  // A first launch only. Every step marks the funnel as running, and
  // [onboardingCompleted] refuses to fire unless one did — so a returning
  // player, or an install that predates this code, cannot report finishing a
  // funnel they never entered. Without that guard the last step would count
  // every launch and the funnel would read as ~100% completion forever.

  static bool _onboardingRan = false;

  static void _onboardingStep(String name) {
    _onboardingRan = true;
    _log(name);
  }

  static void onboardingConsentShown() =>
      _onboardingStep('onboarding_consent_shown');

  static void onboardingConsentCompleted() =>
      _onboardingStep('onboarding_consent_completed');

  static void onboardingUmpShown() => _onboardingStep('onboarding_ump_shown');

  /// Fired when the form closes, whatever was chosen — the choice itself is
  /// UMP's to record, and this only measures how many people got through it.
  static void onboardingUmpCompleted() =>
      _onboardingStep('onboarding_ump_completed');

  static void onboardingAttShown() => _onboardingStep('onboarding_att_shown');

  static void onboardingAttAccepted() =>
      _onboardingStep('onboarding_att_accepted');

  static void onboardingAttDenied() =>
      _onboardingStep('onboarding_att_denied');

  static void onboardingSignInShown() =>
      _onboardingStep('onboarding_signin_shown');

  static void onboardingSignInAccepted() =>
      _onboardingStep('onboarding_signin_accepted');

  static void onboardingSignInSkipped() =>
      _onboardingStep('onboarding_signin_skipped');

  /// Declined, cancelled, or unavailable — indistinguishable from here, and
  /// from the player's side too.
  static void onboardingSignInFailed() =>
      _onboardingStep('onboarding_signin_failed');

  /// The menu, reached for the first time. Only counts if the player actually
  /// went through onboarding this launch.
  static void onboardingCompleted() {
    if (!_onboardingRan) return;
    _onboardingRan = false; // at most once per launch
    _log('onboarding_completed');
  }

  /// Tests only.
  @visibleForTesting
  static void resetOnboardingForTest() => _onboardingRan = false;

  /// Tests only: whether any onboarding step has been reported this launch.
  @visibleForTesting
  static bool get onboardingRan => _onboardingRan;

  /// A weekly challenge finished. [id] is the document id, so a challenge can
  /// be followed from Firestore through to its completion rate.
  static void challengeCompleted(String id, String title) =>
      _log('challenge_completed', {'challenge_id': id, 'challenge_title': title});

  /// Cloud save trouble. Reported so a platform that quietly stops accepting
  /// saves is visible in the data — the player is told nothing, by design.
  /// [op] is 'save' or 'load'.
  static void cloudSaveFailed(String op) =>
      _log('cloud_save_failed', {'operation': op});

  // ----- notifications -----

  /// The pre-prompt, not the system dialog. Shown once ever, after a first
  /// level is finished.
  static void notificationPromptShown() => _log('notification_prompt_shown');

  /// Accepted and denied are reported against the OS answer rather than the
  /// button: someone can tap "Enable Notifications" and then decline the system
  /// dialog behind it, and counting that as an acceptance would make the
  /// pre-prompt look like it works better than it does.
  static void notificationPromptAccepted() =>
      _log('notification_prompt_accepted');

  static void notificationPromptDenied() => _log('notification_prompt_denied');

  // ----- user properties -----

  /// Firebase stores user properties as strings, whatever they describe.
  static void setProgress({
    required int levelsCompleted,
    required int currentWorld,
  }) {
    _setProperty('levels_completed', '$levelsCompleted');
    _setProperty('current_world', '$currentWorld');
  }

  static void setHintsUsedTotal(int total) =>
      _setProperty('hints_used_total', '$total');
}
