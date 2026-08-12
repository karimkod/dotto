import 'dart:async';

import 'package:flutter/material.dart';

import 'ads/ad_manager.dart';
import 'analytics/analytics_service.dart';
import 'app_routes.dart';
import 'consent/consent_manager.dart';
import 'progress/progress_store.dart';
import 'screens/consent_screen.dart';
import 'screens/menu_screen.dart';
import 'services/game_services.dart';
import 'settings/settings_store.dart';
import 'theme/app_theme.dart';

Future<void> main() async {
  // Progress is read synchronously while the level list builds, so it has to be
  // in memory before the first frame — otherwise a returning player sees a
  // fully locked map for an instant.
  WidgetsFlutterBinding.ensureInitialized();
  await ProgressStore.init();
  await SettingsStore.init();
  // Must precede Analytics.init: the default consent state has to be in place
  // before Firebase starts, or the first ping leaves the device before the
  // player has said anything. Also decides whether the consent screen is the
  // first thing shown, so it cannot be deferred either.
  await ConsentManager.init();

  // Firebase start-up touches the network, so it does not block the first
  // frame — but the defaults it needs are applied inside, ahead of it.
  unawaited(_startAnalytics());
  // Optional and quiet: a player who never signs in should not be able to tell
  // this exists.
  unawaited(GameServices.signIn());
  // Ads wait for a decision. Starting the SDK is harmless, but requesting an ad
  // before the player has chosen is the thing consent exists to prevent, so on
  // a first launch this is left to the consent screen.
  if (!ConsentManager.needsConsentUi) unawaited(AdManager.init());

  runApp(DottoApp(showConsent: ConsentManager.needsConsentUi));
}

/// Consent defaults, then Firebase. The order is the whole point: Consent Mode
/// defaults set after initialisation would arrive too late to govern the first
/// events.
Future<void> _startAnalytics() async {
  await ConsentManager.applyDefaults();
  await Analytics.init();
  // Re-send the stored choice now that Firebase is running: applyDefaults ran
  // against an SDK that had not started, so it recorded the defaults and
  // nothing else.
  if (ConsentManager.given) await ConsentManager.choose(ConsentManager.choice);
}

class DottoApp extends StatefulWidget {
  const DottoApp({super.key, this.showConsent = false});

  /// Whether to open on the consent screen rather than the menu.
  final bool showConsent;

  @override
  State<DottoApp> createState() => _DottoAppState();
}

class _DottoAppState extends State<DottoApp> {
  late bool _needsConsent = widget.showConsent;

  Future<void> _onConsentChosen(AdConsent consent) async {
    await ConsentManager.choose(consent);
    // Apple's prompt comes after ours: the GDPR choice is the app's own
    // question, and stacking two system-looking dialogs at once reads as a
    // wall of permissions. iOS only; a no-op everywhere else.
    await ConsentManager.requestTrackingAuthorization();
    // Only now may ads load — with the npa flag the choice implies.
    unawaited(AdManager.init());
    if (mounted) setState(() => _needsConsent = false);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Dotto',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      // Lets the menu notice it has been uncovered and re-read progress.
      navigatorObservers: [routeObserver],
      home: _needsConsent
          ? ConsentScreen(onChosen: _onConsentChosen)
          : const MenuScreen(),
    );
  }
}
