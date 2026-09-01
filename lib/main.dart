import 'dart:async';
import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/foundation.dart'
    show LicenseEntryWithLineBreaks, LicenseRegistry;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:google_fonts/google_fonts.dart';

import 'ads/ad_manager.dart';
import 'analytics/analytics_service.dart';
import 'analytics/crash_reporting.dart';
import 'app_routes.dart';
import 'consent/consent_manager.dart';
import 'progress/progress_store.dart';
import 'screens/challenges_screen.dart';
import 'screens/consent_screen.dart';
import 'screens/menu_screen.dart';
import 'screens/sign_in_screen.dart';
import 'screens/splash_screen.dart';
import 'services/challenge_service.dart';
import 'services/cloud_save_service.dart';
import 'services/free_hint_service.dart';
import 'services/game_services.dart';
import 'services/music_service.dart';
import 'services/notification_service.dart';
import 'settings/settings_store.dart';
import 'theme/app_theme.dart';

void main() {
  // Crash handling first, before a single line of startup can throw. Flutter
  // loses an uncaught error down one of three routes and these are all three —
  // framework errors, errors that reach the engine with no Dart handler left,
  // and anything else raised inside the zone. See lib/analytics/crash_
  // reporting.dart; the handlers are safe to install now and report only once
  // Crashlytics has actually started, a few lines into _start.
  FlutterError.onError = CrashReporting.onFlutterError;
  PlatformDispatcher.instance.onError = CrashReporting.onPlatformError;
  // The zone has to contain the binding as well as runApp: a binding created
  // outside the zone that guards it is a mismatch Flutter warns about, and the
  // guard would not cover initialisation — which is exactly the part of startup
  // with no UI to fail visibly.
  runZonedGuarded(_start, CrashReporting.onZoneError);
}

Future<void> _start() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Every Nunito and Poppins variant the app asks for is bundled (see the asset
  // list in pubspec.yaml), so google_fonts resolves them from the manifest and
  // never reaches for the network. Left on, a first launch behind a captive
  // portal or with no connection threw `Failed to load font with url` from
  // google_fonts' fetch, and because the package attaches no error handler to
  // that load future, the throw escaped to runZonedGuarded above and was filed
  // as a fatal crash. The text itself had already painted in the fallback face,
  // so the report described nothing the player could see.
  //
  // Turning fetching off removes that path rather than silencing it: an
  // unbundled variant now throws immediately instead of after a failed request,
  // by the same route and with the same result. So the bundled set has to stay
  // in step with the weights the app asks for, which is what
  // test/fonts_assets_test.dart pins.
  GoogleFonts.config.allowRuntimeFetching = false;
  _registerFontLicenses();
  // Everything else loads behind the splash, which holds its handoff until
  // [_boot] settles — so the first frame is the opening rather than a stalled
  // launch colour, and every screen after the splash can still read its
  // stores synchronously.
  runApp(DottoApp(boot: _boot()));
}

/// The launch-time read of the platform's sign-in state, still in flight.
///
/// Written by [_boot], read by [_DottoAppState._afterConsent] through the
/// sign-in gate. Null in tests and anywhere boot never ran, which is treated
/// as "already settled" rather than as something to wait for.
Future<void>? _signInRestored;

/// Everything launch needs, in dependency order, behind the splash.
///
/// The splash holds its handoff until this settles, which is what lets the
/// screens after it read progress, settings and the challenge cache
/// synchronously — the guarantee that used to come from finishing all of this
/// before runApp, kept without the stalled native launch screen.
///
/// Never allowed to throw: a boot that dies must still hand the player the
/// game, with whatever defaults the failed step left behind, rather than
/// strand them on the opening. The error is reported, not swallowed.
Future<void> _boot() async {
  try {
    // Progress is read synchronously while the level list builds, so it has
    // to be in memory before the splash hands over — otherwise a returning
    // player sees a fully locked map for an instant.
    await ProgressStore.init();
    await SettingsStore.init();
    // Reads the music preference and starts decoding the track behind it, so
    // the splash covers the load and the menu opens straight into the fade-in.
    await MusicService.init();
    // Started here, awaited below. Everything Firebase-backed needs this to
    // have finished first — Firestore for the challenges, Messaging for the
    // notification state — and it used to run after them, so the first
    // challenge refresh of every launch failed with `[core/no-app]` and fell
    // back to cache. Kicked off rather than awaited on the spot so it
    // overlaps with the consent wait below instead of being added to it.
    final firebaseReady = Analytics.init();
    // Still bounded at eight seconds, but now covered: the splash holds until
    // boot settles, so a slow consent service costs opening time rather than
    // a frozen launch screen — and its answer is in before
    // [_DottoAppState._afterSplash] decides which screen to open, which is
    // the race that used to cost the pre-prompt its first-launch slot.
    await ConsentManager.init();
    await firebaseReady;
    // Attaches to the app Firebase just created, so it has to follow that
    // await rather than sit beside it. Unawaited would race the rest of boot
    // — the window this closes is precisely the one where a launch crash
    // happens.
    await CrashReporting.init();
    // Cached challenges load synchronously enough to decide the menu badge;
    // the network refresh behind it is unawaited.
    await ChallengeService.init();
    await FreeHintService.init();
    // Loads the "already offered sign-in" flag, which decides whether
    // onboarding has one more step.
    await GameServices.init();

    // Firebase itself started above. Starting it before the consent form is
    // deliberate and unchanged: UMP emits the Consent Mode signals itself, so
    // there is no default state for this app to set first.
    //
    // Reads preferences and reconnects whatever permission already exists. It
    // does NOT ask for permission — that happens after a first level is won,
    // by which point the player knows what they are being offered. Unawaited:
    // no screen depends on it, and it must not stand between launch and the
    // game.
    unawaited(NotificationService.init());
    // Reads whether an account is already signed in — it never asks for one.
    // Sign-in is player-initiated only: the onboarding offer, or Achievements.
    // Launching straight into the platform's sign-in dialog is exactly what
    // this must not do.
    //
    // Kept rather than thrown away with unawaited(): the platform probe is a
    // round trip through Play Games or Game Center that routinely outlasts
    // whatever is left of the opening, so the routing after the splash used
    // to read a _signedIn that had not been written yet and offer sign-in to
    // a player who was already signed in. Boot does not wait on it — only the
    // one decision that depends on it does, in
    // [_DottoAppState._afterConsent].
    _signInRestored = GameServices.restoreSignInState();
    // Ads only once UMP says they are allowed *and* Apple's prompt is not
    // still owed. On a first EEA launch UMP alone holds them; on a first iOS
    // launch anywhere else UMP allows them straight away and it is ATT that
    // holds them — starting the AdMob SDK ahead of a tracking request the
    // player has not been shown is the thing App Review rejected the build
    // for. Either way the consent screen starts them once it is through.
    if (ConsentManager.adsMayStartAtLaunch) unawaited(AdManager.init());
  } catch (e, stack) {
    // Reported as caught rather than fatal: the app carries on into the game,
    // it just got there with less than it wanted.
    CrashReporting.recordError(e, stack, fatal: false, context: 'boot');
  }
}

/// Adds the bundled fonts' SIL Open Font License text to the licence page.
///
/// google_fonts registers nothing on our behalf, and it has no reason to: until
/// this change the files were fetched at runtime rather than shipped. Now that
/// the .ttf files are in the bundle, the OFL travels with them, so the notice
/// has to be declared here. The callback is lazy, so the files are only read if
/// a player actually opens the licence list.
void _registerFontLicenses() {
  LicenseRegistry.addLicense(() async* {
    for (final family in const ['nunito', 'poppins']) {
      yield LicenseEntryWithLineBreaks(
        ['google_fonts', family],
        await rootBundle.loadString('assets/fonts/OFL-$family.txt'),
      );
    }
  });
}

class DottoApp extends StatefulWidget {
  const DottoApp({super.key, this.boot});

  /// Launch's initialisation, still in flight — see [_boot]. The splash holds
  /// its handoff until this settles. Null in tests, where there is nothing to
  /// wait for.
  final Future<void>? boot;

  @override
  State<DottoApp> createState() => _DottoAppState();
}

class _DottoAppState extends State<DottoApp> with WidgetsBindingObserver {
  /// Whether the app opened on the pre-prompt. Decided at the splash's
  /// handoff, once boot has settled and UMP's answer is in — deciding it any
  /// earlier is the race this replaced, where a first launch whose UMP answer
  /// missed runApp skipped the consent screen and let the one-shot sign-in
  /// offer run ahead of it.
  bool? _prePrompt;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // A tapped notification arrives from the platform with no BuildContext, so
    // it is handed the navigator key instead. Pushing rather than replacing:
    // the player came from outside the app and should be able to get back to
    // wherever they were.
    NotificationService.onNavigate = (route) {
      if (route != '/challenges') return;
      navigatorKey.currentState?.push(
        MaterialPageRoute(builder: (_) => const ChallengesScreen()),
      );
    };
  }

  @override
  void dispose() {
    NotificationService.onNavigate = null;
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Leaving the app is the last certain moment to write: a process killed
    // from the background gets no further warning. The per-event saves already
    // cover the common path; this catches whatever the last one missed.
    if (state == AppLifecycleState.paused) CloudSaveService.save();
    // Music follows the app out and back. A full-screen ad arrives here too —
    // it covers the app, so the platform reports a pause — which is what keeps
    // the track from playing underneath a rewarded video.
    if (state == AppLifecycleState.paused || state == AppLifecycleState.hidden) {
      MusicService.pause();
    } else if (state == AppLifecycleState.resumed) {
      MusicService.resume();
    }
  }

  Future<void> _onContinue(BuildContext context) async {
    // Order matters and is Apple's as much as Google's: explain, then Apple's
    // prompt, then Google's form. ATT first because it decides whether the IDFA
    // exists, and UMP builds its form around the answer — asked the other way
    // round the form is assembled against a tracking state that changes a
    // second later. Never both at once: two system dialogs back to back with no
    // explanation is a wall of permissions, which is what this screen is for.
    //
    // Outside the EEA only the first of the two shows anything: UMP has no
    // form there and the call below returns straight away, having done nothing
    // but confirm as much. That is the point of the screen now running
    // everywhere — ATT is asked either way.
    await ConsentManager.requestTrackingAuthorization();
    final answered =
        await ConsentManager.showFormIfRequired(duringOnboarding: true);
    // Only a UMP that actually answered counts as an introduction made. If the
    // SDK could not be reached this launch, the flag stays unset and the whole
    // thing runs again next time — better a repeated explainer than a player
    // who is never shown the form at all.
    if (answered) await ConsentManager.markPrePromptSeen();
    if (ConsentManager.canRequestAds) unawaited(AdManager.init());
    if (!context.mounted) return;
    _prePrompt = false;
    // Replace rather than pop: the consent screen was pushed over the splash,
    // and there is nothing behind it worth returning to.
    Navigator.of(context).pushReplacement(_fadeTo(_afterConsent));
  }

  /// What the splash opens into. Onboarding is a chain, and each step decides
  /// only whether it is needed — so a returning player falls straight through
  /// to the menu without any of it running.
  ///
  /// The chain has one fixed link: consent is the only thing that can come
  /// first. Every route onwards goes through [_afterConsent], and the sign-in
  /// offer lives inside that — so there is no path where the platform's account
  /// screen appears before the player has been asked about their data.
  Widget _afterSplash(BuildContext context) {
    final prePrompt = _prePrompt ??= ConsentManager.needsPrePrompt;
    return prePrompt
        ? ConsentScreen(
            onContinue: () => _onContinue(context),
            // Outside the EEA there is no form behind Continue, only Apple's
            // prompt, and the screen says so rather than pointing at choices
            // that never arrive.
            hasAdChoices: ConsentManager.hasUmpForm,
          )
        : _afterConsent(context);
  }

  /// After consent: offer sign-in once, then the menu.
  ///
  /// Deliberately not conditional on the consent screen having shown — outside
  /// the EEA there is no form, and a first launch there should still get the
  /// offer.
  ///
  /// Gated on the launch-time sign-in probe, because `needsSignInPrompt` is a
  /// plain getter over state that call is still writing.
  ///
  /// And held until the consent question is settled — answered by UMP this
  /// launch, or introduced on an earlier one. A launch where UMP was
  /// unreachable gets the menu, not the offer: the offer is one-shot, and
  /// spending it here would put the platform's account screen ahead of a
  /// consent screen the player is still owed. The next launch, with UMP's
  /// cached answer, runs the two in the designed order instead.
  Widget _afterConsent(BuildContext context) => _SignInGate(
        restored: _signInRestored,
        builder: (context) => GameServices.needsSignInPrompt &&
                ConsentManager.consentSettled
            ? SignInScreen(
                onDone: () => Navigator.of(context)
                    .pushReplacement(_fadeTo((_) => _menu())),
              )
            : _menu(),
      );

  /// The menu, and the end of the funnel.
  ///
  /// Reaching it is what "onboarding completed" means — not the splash, which
  /// runs before any of it. The call is safe to make from a builder: it reports
  /// nothing unless an onboarding step actually ran this launch, and at most
  /// once either way.
  Widget _menu() {
    Analytics.onboardingCompleted();
    return const MenuScreen();
  }

  /// A cross-fade rather than a slide. The splash and the menu share a
  /// background, so sliding would move a cream panel across a cream one.
  static PageRouteBuilder<void> _fadeTo(WidgetBuilder builder) =>
      PageRouteBuilder<void>(
        pageBuilder: (context, _, _) => builder(context),
        transitionsBuilder: (_, animation, _, child) =>
            FadeTransition(opacity: animation, child: child),
        transitionDuration: const Duration(milliseconds: 450),
      );

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Dotto',
      navigatorKey: navigatorKey,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      // Lets the menu notice it has been uncovered and re-read progress.
      navigatorObservers: [routeObserver],
      home: SplashScreen(next: _afterSplash, holdFor: widget.boot),
    );
  }
}

/// Holds the last step of onboarding until the launch-time sign-in probe has
/// answered.
///
/// The decision it guards — offer sign-in, or go straight to the menu — is read
/// from a getter over state that [GameServices.restoreSignInState] writes when
/// the platform gets back to it, which is usually after the splash has already
/// finished. Building on that too early is not a cosmetic race: a player who is
/// signed in gets offered sign-in again, and the offer is a screen they were
/// promised they would only ever see once.
///
/// The splash is left alone: it holds for boot, not for this. The probe is
/// boot's last act, so what this covers is the probe's own round trip after
/// the handoff — bounded, because a platform that stays silent should cost a
/// beat, not the launch.
class _SignInGate extends StatefulWidget {
  const _SignInGate({required this.restored, required this.builder});

  /// The probe, or null when there is none to wait for.
  final Future<void>? restored;

  /// What to build once it has settled.
  final WidgetBuilder builder;

  @override
  State<_SignInGate> createState() => _SignInGateState();
}

class _SignInGateState extends State<_SignInGate> {
  late bool _ready = widget.restored == null;

  @override
  void initState() {
    super.initState();
    if (_ready) return;
    // Bounded, and generously: the probe already carries its own ten-second
    // deadline and pulls the cloud save behind it, neither of which the player
    // should be made to watch. Past this the routing goes ahead on what is
    // known — the same answer the unawaited version gave, just no sooner.
    widget.restored!
        .timeout(const Duration(milliseconds: 2500))
        .catchError((_) {})
        .whenComplete(() {
      if (mounted) setState(() => _ready = true);
    });
  }

  @override
  Widget build(BuildContext context) => _ready
      ? widget.builder(context)
      // The splash's own backdrop, so a wait short enough to be a single frame
      // is invisible and a longer one reads as the opening holding a moment.
      : const Scaffold(backgroundColor: AppColors.background);
}
