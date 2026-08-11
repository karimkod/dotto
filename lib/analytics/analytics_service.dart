// Firebase Analytics: every event the game reports, in one place.
//
// NOT YET CONFIGURED. The Firebase project exists (dotto-d817e) but the
// generated config does not: there is no firebase_options.dart, no
// android/app/google-services.json and no ios/Runner/GoogleService-Info.plist
// in this repo. Until someone runs `flutterfire configure` (see
// docs/firebase-setup.md), Firebase.initializeApp throws, [enabled] stays
// false, and every method below returns without doing anything.
//
// That is the deliberate shape of this file: analytics is an observer, and an
// observer that can break the thing it observes is worse than no observer. Each
// log is fire-and-forget, wrapped, and impossible to await from the game code —
// so a slow network or a misconfigured project cannot stall a level.
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

  /// Start Firebase. Safe to call when nothing is configured — that is the
  /// current state of this repo, and it must not be fatal.
  static Future<void> init() async {
    if (!supported || _analytics != null) return;
    try {
      // No `options:` argument: on Android and iOS the native config files
      // supply them. That is also why this throws until those files exist.
      await Firebase.initializeApp();
      _analytics = FirebaseAnalytics.instance;
    } catch (e) {
      debugPrint('Firebase not configured, analytics disabled: $e');
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
