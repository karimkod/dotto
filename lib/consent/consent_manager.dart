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
//
// Which is also why [init] waits for a network before it asks. That fallback is
// safe but blunt: a launch with no connection at all takes it in full, and an
// EEA player whose phone came up before their wifi did would be filed as "no
// form, ads allowed" on a question that was never actually put. A minute spent
// waiting for a transport to appear turns most of those launches back into real
// answers, and costs nothing on the ordinary launch that already has one.

import 'dart:async';
import 'dart:io' show Platform;

import 'package:app_tracking_transparency/app_tracking_transparency.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
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

  /// Whether UMP answered on this launch. Set only by the success callback in
  /// [init] — a failure or a timeout is precisely UMP *not* answering.
  static bool _answered = false;

  /// Whether ads may be requested at all. False until UMP has been asked.
  static bool get canRequestAds => _canRequestAds;

  /// Whether the consent question is settled enough for onboarding to move
  /// past it: the pre-prompt has been seen on some earlier launch, or UMP
  /// answered on this one — form or no form.
  ///
  /// False means UMP has not been reached yet and the introduction is still
  /// owed. The router holds the sign-in offer on this, so a launch where the
  /// consent service was unreachable cannot spend the one-shot offer ahead of
  /// a consent screen the player has never seen — the next launch, with UMP's
  /// cached answer, runs the two in the designed order instead.
  static bool get consentSettled => _prePromptSeen || _answered;

  /// Whether UMP has a form to show — in practice, whether this player is in
  /// the EEA or UK. Read by the pre-prompt, which words itself differently
  /// depending on what is actually behind the Continue button.
  static bool _formAvailable = false;
  static bool get hasUmpForm => _formAvailable;

  /// Whether Apple's tracking prompt can still be put to this player: iOS, and
  /// a status of `notDetermined`. Read once per launch in [init], before the
  /// network wait, because ATT is a local question and must not be held up by
  /// — or lost to — a consent service that cannot be reached.
  static bool _attPending = false;
  static bool get attPending => _attPending;

  /// Whether to open on the pre-prompt.
  ///
  /// Whenever there is something behind the Continue button. That used to mean
  /// a UMP form and nothing else, which made the whole screen EEA-only — and
  /// because ATT is asked from this flow, an iOS player outside the EEA was
  /// therefore never asked about tracking at all. App Review rejected the
  /// build for exactly that: a US reviewer on iPadOS saw no prompt.
  ///
  /// So the same screen now opens for both, and adapts to what follows it:
  ///
  ///   * EEA — the explainer, then ATT, then Google's form.
  ///   * Everywhere else on iOS — the explainer, then ATT. Google requires no
  ///     form outside the EEA; Apple requires the prompt everywhere.
  ///
  /// Android outside the EEA is the one case that still opens straight into
  /// the game: no ATT there and no form either, so the screen would introduce
  /// a choice that is never offered. That is not what was rejected — it is the
  /// original rule, kept where it still holds.
  static bool get needsPrePrompt =>
      _supported && !_prePromptSeen && (_formAvailable || _attPending);

  /// Whether ads may be started at launch, as opposed to eventually.
  ///
  /// [canRequestAds] is UMP's answer and only UMP's; this adds Apple's half.
  /// Starting the AdMob SDK ahead of a tracking prompt that is still owed is
  /// precisely the "data collected before the request" App Review objected to
  /// — so boot holds off, and the consent screen starts ads once ATT has been
  /// answered.
  static bool get adsMayStartAtLaunch => _canRequestAds && !needsPrePrompt;

  static bool get _supported {
    if (kIsWeb) return false;
    if (Platform.environment.containsKey('FLUTTER_TEST')) return false;
    return Platform.isAndroid || Platform.isIOS;
  }

  /// Devices that should be treated as if they were in the EEA, so the form can
  /// be exercised from outside it.
  ///
  /// The id is printed by the SDK on first run — look for "Use
  /// ConsentDebugSettings.testIdentifiers" in logcat or the Xcode console — and
  /// is specific to a device and install. Add yours here to make the debug
  /// geography below actually take effect on hardware: emulators and simulators
  /// are treated as test devices automatically, real devices are not.
  ///
  /// Debug builds only. [ConsentDebugSettings] is ignored in release, so a
  /// stray id here cannot change what a player sees.
  static const List<String> _testDeviceIds = <String>[];

  /// Which region a debug build pretends to be in. Debug only — see the
  /// [ConsentRequestParameters] below, which passes null in release.
  ///
  /// EEA by default, because that is the flow with the most in it: explainer,
  /// ATT, then Google's form. Switch to [DebugGeography.debugGeographyOther]
  /// to walk the path a US player takes — explainer, ATT, and no form — which
  /// is the one that had no screen at all until App Review found it. Worth
  /// running on a simulator before any iOS release; nothing else exercises it.
  static const _debugGeography = DebugGeography.debugGeographyEea;

  /// How long [init] will wait for a network before giving up on UMP.
  ///
  /// A minute is long for a launch, but the alternative is worse: the only
  /// thing on the other side of this wait is a question about the player's
  /// data, and answering it wrongly by default lasts until the next launch.
  /// Nothing pays it except a launch that genuinely has no transport at all,
  /// and such a launch has nothing else to get on with either — Firebase, the
  /// challenge refresh and the ad load are all in the same position.
  static const _connectivityTimeout = Duration(minutes: 1);

  /// Whether any of the transports the platform reported could carry a request.
  static bool _online(List<ConnectivityResult> results) =>
      results.any((r) => r != ConnectivityResult.none);

  /// Resolve once the device has a network, or [timeout] passes without one.
  ///
  /// Returns whether a network turned up. Returns true immediately when there
  /// already is one, which is the case on essentially every launch — the wait
  /// is only entered when the platform reports no transport whatsoever.
  ///
  /// A connectivity check that itself fails resolves true rather than false:
  /// not being able to tell is not the same as being offline, and the cost of
  /// guessing wrong here is a minute of splash over a working connection. UMP's
  /// own timeout is the backstop for the other direction.
  ///
  /// Note the limit of what this can know: the platform reports a transport,
  /// not reachability. Wifi behind a captive portal counts as online here, and
  /// UMP will fail against it the way it always did.
  @visibleForTesting
  static Future<bool> waitForInternet({
    Duration timeout = _connectivityTimeout,
  }) async {
    final connectivity = Connectivity();
    try {
      if (_online(await connectivity.checkConnectivity())) return true;
    } catch (e) {
      debugPrint('Connectivity check failed: $e');
      return true;
    }

    // Listened to explicitly rather than through `firstWhere().timeout()`, so
    // the subscription is actually cancelled when the timer wins — a future
    // timing out does not close the stream behind it, and this one would then
    // outlive the wait it belongs to.
    final found = Completer<bool>();
    StreamSubscription<List<ConnectivityResult>>? sub;
    try {
      sub = connectivity.onConnectivityChanged.listen(
        (results) {
          if (_online(results) && !found.isCompleted) found.complete(true);
        },
        onError: (Object e) {
          debugPrint('Connectivity stream failed: $e');
          if (!found.isCompleted) found.complete(true);
        },
      );
    } catch (e) {
      debugPrint('Connectivity stream unavailable: $e');
      return true;
    }
    final timer = Timer(timeout, () {
      if (!found.isCompleted) found.complete(false);
    });

    final online = await found.future;
    timer.cancel();
    await sub.cancel();
    if (!online) {
      debugPrint('No connection after ${timeout.inSeconds}s; carrying on');
    }
    return online;
  }

  /// Read whether Apple's prompt is still open to being asked.
  ///
  /// Only `notDetermined` can be put to the player; every other status is a
  /// settled answer that a second request would return without showing
  /// anything. A read that fails is taken as settled — better an explainer
  /// that does not appear than one that leads nowhere.
  static Future<void> _refreshAttPending() async {
    if (!Platform.isIOS) {
      _attPending = false;
      return;
    }
    try {
      _attPending =
          await AppTrackingTransparency.trackingAuthorizationStatus ==
              TrackingStatus.notDetermined;
    } catch (e) {
      debugPrint('ATT status read failed: $e');
      _attPending = false;
    }
  }

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

    // Before anything that can block or fail. ATT is a local read with no
    // network behind it, and the pre-prompt is now gated on its answer as much
    // as on UMP's — so a launch that never reaches Google must still know it
    // owes the player Apple's prompt.
    await _refreshAttPending();

    // UMP is a network round trip and nothing else, so asking it over no
    // connection is not a request that might fail — it is one that cannot
    // succeed. Wait for a transport first; see [waitForInternet].
    if (!await waitForInternet()) {
      // A full minute with nothing to send over. Take the same fallback the
      // error callback below takes rather than spend another eight seconds
      // proving it: ads allowed, nothing settled — so [consentSettled] stays
      // false, the sign-in offer is held, and the whole introduction runs
      // again next launch, which is exactly the unreachable-UMP path.
      _canRequestAds = true;
      return;
    }

    // Debug builds claim a geography, so both flows can be walked through from
    // anywhere — they are otherwise untestable outside their own region, which
    // is the whole reason the missing non-EEA prompt reached App Review rather
    // than a developer. Attached unconditionally in debug rather than only when
    // [_testDeviceIds] is filled: on an emulator or simulator that alone is
    // enough, and a developer should not have to find their device id before
    // the form will appear. Release builds get null, so none of this can follow
    // a build to the store.
    final params = ConsentRequestParameters(
      consentDebugSettings: kDebugMode
          ? ConsentDebugSettings(
              debugGeography: _debugGeography,
              testIdentifiers: _testDeviceIds,
            )
          : null,
    );

    final done = Completer<void>();
    try {
      ConsentInformation.instance.requestConsentInfoUpdate(
        params,
        () async {
          // Answered, whatever the reads below make of it: the callback firing
          // at all is UMP getting back to us, which is what settles the
          // question this launch.
          _answered = true;
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
  /// Returns whether UMP got as far as an answer: true when the form was shown
  /// and dismissed, or when there was nothing to show, and false when the SDK
  /// errored, threw, or never came back. The caller uses that to decide whether
  /// the pre-prompt counts as done — a first launch where UMP could not be
  /// reached must be able to try again next time rather than remembering a step
  /// that did not happen.
  ///
  /// [duringOnboarding] gates the funnel events. Settings → Ad preferences
  /// calls this too, and a returning player changing their mind is not part of
  /// the first-launch funnel — counting it there would inflate a step that is
  /// supposed to measure new players only.
  ///
  /// So does [hasUmpForm], now that the pre-prompt runs outside the EEA as
  /// well: the call below is a no-op where there is no form, and reporting a
  /// UMP step for every non-EEA player would drown the one measurement this
  /// event exists to make.
  static Future<bool> showFormIfRequired({
    bool duringOnboarding = false,
  }) async {
    // Nothing to show and nothing that can fail: on web and under `flutter
    // test` there is no form to come back to, so this is a success.
    if (!_supported) return true;
    final reportFunnel = duringOnboarding && _formAvailable;
    if (reportFunnel) Analytics.onboardingUmpShown();
    var ok = true;
    final done = Completer<void>();
    try {
      await ConsentForm.loadAndShowConsentFormIfRequired((error) {
        if (error != null) {
          debugPrint('Consent form error: ${error.message}');
          ok = false;
        }
        if (!done.isCompleted) done.complete();
      });
    } catch (e) {
      debugPrint('Consent form failed: $e');
      ok = false;
      if (!done.isCompleted) done.complete();
    }
    await done.future.timeout(const Duration(seconds: 60), onTimeout: () {
      debugPrint('Consent form never dismissed; carrying on');
      ok = false;
    });
    try {
      _canRequestAds = await ConsentInformation.instance.canRequestAds();
    } catch (_) {
      _canRequestAds = true;
    }
    if (reportFunnel) Analytics.onboardingUmpCompleted();
    return ok;
  }

  /// Remember that the pre-prompt has been shown.
  ///
  /// Called only once UMP has actually answered — see [showFormIfRequired]. A
  /// first launch that could not reach the SDK deliberately leaves this unset,
  /// so the whole introduction runs again next time instead of the player being
  /// silently dropped past a form they never saw.
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
  /// Between the pre-prompt and the UMP form, rather than after it: ATT decides
  /// whether the IDFA can be read at all, and UMP reads that answer when it
  /// builds the form — asking Apple second means the form is put together
  /// against a tracking state that is about to change. Still never beside the
  /// form: two dialogs at once reads as a wall of permissions, which is why the
  /// explainer comes before both.
  ///
  /// UMP's answer does not decide this one either way, and neither does UMP
  /// having anything to ask. Apple requires the prompt before the IDFA may be
  /// read, whatever was agreed for GDPR and wherever the player is — which is
  /// why the pre-prompt that leads here no longer waits for a form that only
  /// the EEA ever gets. See [needsPrePrompt].
  static Future<void> requestTrackingAuthorization() async {
    if (kIsWeb) return;
    if (Platform.environment.containsKey('FLUTTER_TEST')) return;
    if (!Platform.isIOS) return;
    // Asked or not, the question is not owed twice. Cleared before the request
    // rather than after it, so a prompt the player leaves unanswered by
    // backgrounding the app cannot leave the flag set for a second pass.
    _attPending = false;
    try {
      final status = await AppTrackingTransparency.trackingAuthorizationStatus;
      // Only `notDetermined` can be asked. Every other state is settled, and
      // asking again just returns the same answer without showing anything.
      if (status == TrackingStatus.notDetermined) {
        // A beat after the tap that started all this, so the system sheet does
        // not arrive on top of a button still finishing its own animation.
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
    _attPending = false;
    _canRequestAds = false;
    _answered = false;
    _prefs = null;
  }

  /// Tests only: set state without touching the platform.
  @visibleForTesting
  static void setForTest({
    bool prePromptSeen = false,
    bool formAvailable = false,
    bool attPending = false,
    bool canRequestAds = false,
    bool answered = false,
  }) {
    _prePromptSeen = prePromptSeen;
    _formAvailable = formAvailable;
    _attPending = attPending;
    _canRequestAds = canRequestAds;
    _answered = answered;
  }
}
