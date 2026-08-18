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
  // Progress is read synchronously while the level list builds, so it has to be
  // in memory before the first frame — otherwise a returning player sees a
  // fully locked map for an instant.
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
  await ProgressStore.init();
  await SettingsStore.init();
  // Reads the music preference and starts decoding the track behind it, so the
  // splash covers the load and the menu opens straight into the fade-in.
  await MusicService.init();
  // Started here, awaited below. Everything Firebase-backed needs this to have
  // finished first — Firestore for the challenges, Messaging for the
  // notification state — and it used to run after them, so the first challenge
  // refresh of every launch failed with `[core/no-app]` and fell back to cache.
  // Kicked off rather than awaited on the spot so it overlaps with the consent
  // wait below instead of being added to it.
  final firebaseReady = Analytics.init();
  // Blocking, but bounded: it decides which screen opens, and it caps itself at
  // eight seconds rather than letting a slow consent service delay the game.
  await ConsentManager.init();
  await firebaseReady;
  // Attaches to the app Firebase just created, so it has to follow that await
  // rather than sit beside it. Unawaited would race the rest of startup — the
  // window this closes is precisely the one where a launch crash happens.
  await CrashReporting.init();
  // Cached challenges load synchronously enough to decide the menu badge; the
  // network refresh behind it is unawaited.
  await ChallengeService.init();
  await FreeHintService.init();
  // Loads the "already offered sign-in" flag, which decides whether onboarding
  // has one more step.
  await GameServices.init();

  // Firebase itself started above. Starting it before the consent form is
  // deliberate and unchanged: UMP emits the Consent Mode signals itself, so
  // there is no default state for this app to set first.
  //
  // Reads preferences and reconnects whatever permission already exists. It
  // does NOT ask for permission — that happens after a first level is won, by
  // which point the player knows what they are being offered. Unawaited: no
  // screen depends on it, and it must not stand between launch and the game.
  unawaited(NotificationService.init());
  // Reads whether an account is already signed in — it never asks for one.
  // Sign-in is player-initiated only: the onboarding offer, or Achievements.
  // Launching straight into the platform's sign-in dialog is exactly what this
  // must not do.
  //
  // Kept rather than thrown away with unawaited(): the platform probe is a
  // round trip through Play Games or Game Center and routinely outlasts the
  // 1800ms opening, so the routing after the splash used to read a _signedIn
  // that had not been written yet and offer sign-in to a player who was already
  // signed in. Nothing before the first frame waits on it — only the one
  // decision that depends on it does, in [_DottoAppState._afterConsent].
  final signInRestored = GameServices.restoreSignInState();
  // Ads only once UMP says they are allowed. On a first EEA launch that is
  // false until the form has been answered, and the consent screen starts them.
  if (ConsentManager.canRequestAds) unawaited(AdManager.init());

  runApp(DottoApp(
    showPrePrompt: ConsentManager.needsPrePrompt,
    signInRestored: signInRestored,
  ));
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
  const DottoApp({super.key, this.showPrePrompt = false, this.signInRestored});

  /// Whether to open on the pre-prompt rather than the menu.
  final bool showPrePrompt;

  /// The launch-time read of the platform's sign-in state, still in flight.
  ///
  /// Null in tests and anywhere the probe was never started, which is treated
  /// as "already settled" rather than as something to wait for.
  final Future<void>? signInRestored;

  @override
  State<DottoApp> createState() => _DottoAppState();
}

class _DottoAppState extends State<DottoApp> with WidgetsBindingObserver {
  late bool _prePrompt = widget.showPrePrompt;

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
  Widget _afterSplash(BuildContext context) => _prePrompt
      ? ConsentScreen(onContinue: () => _onContinue(context))
      : _afterConsent(context);

  /// After consent: offer sign-in once, then the menu.
  ///
  /// Deliberately not conditional on the consent screen having shown — outside
  /// the EEA there is no form, and a first launch there should still get the
  /// offer.
  ///
  /// Gated on the launch-time sign-in probe, because `needsSignInPrompt` is a
  /// plain getter over state that call is still writing.
  Widget _afterConsent(BuildContext context) => _SignInGate(
        restored: widget.signInRestored,
        builder: (context) => GameServices.needsSignInPrompt
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
      home: SplashScreen(next: _afterSplash),
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
/// The splash is left alone. It runs its full opening regardless, and this only
/// covers whatever is left of the probe when the animation is done — normally
/// nothing, since the two have been running side by side since launch.
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
