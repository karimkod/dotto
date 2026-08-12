import 'dart:async';

import 'package:flutter/material.dart';

import 'ads/ad_manager.dart';
import 'analytics/analytics_service.dart';
import 'app_routes.dart';
import 'consent/consent_manager.dart';
import 'progress/progress_store.dart';
import 'screens/consent_screen.dart';
import 'screens/menu_screen.dart';
import 'services/challenge_service.dart';
import 'services/cloud_save_service.dart';
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
  // Blocking, but bounded: it decides which screen opens, and it caps itself at
  // eight seconds rather than letting a slow consent service delay the game.
  await ConsentManager.init();
  // Cached challenges load synchronously enough to decide the menu badge; the
  // network refresh behind it is unawaited.
  await ChallengeService.init();

  // Firebase can start regardless — UMP emits the Consent Mode signals itself,
  // so there is no default state for this app to set first.
  unawaited(Analytics.init());
  // Optional and quiet: a player who never signs in should not be able to tell
  // this exists.
  unawaited(GameServices.signIn());
  // Ads only once UMP says they are allowed. On a first EEA launch that is
  // false until the form has been answered, and the consent screen starts them.
  if (ConsentManager.canRequestAds) unawaited(AdManager.init());

  runApp(DottoApp(showPrePrompt: ConsentManager.needsPrePrompt));
}

class DottoApp extends StatefulWidget {
  const DottoApp({super.key, this.showPrePrompt = false});

  /// Whether to open on the pre-prompt rather than the menu.
  final bool showPrePrompt;

  @override
  State<DottoApp> createState() => _DottoAppState();
}

class _DottoAppState extends State<DottoApp> with WidgetsBindingObserver {
  late bool _prePrompt = widget.showPrePrompt;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Leaving the app is the last certain moment to write: a process killed
    // from the background gets no further warning. The per-event saves already
    // cover the common path; this catches whatever the last one missed.
    if (state == AppLifecycleState.paused) CloudSaveService.save();
  }

  Future<void> _onContinue() async {
    // Order matters and is Apple's as much as Google's: explain, then Google's
    // form, then Apple's prompt. Two system dialogs at once reads as a wall of
    // permissions.
    await ConsentManager.markPrePromptSeen();
    await ConsentManager.showFormIfRequired();
    await ConsentManager.requestTrackingAuthorization();
    if (ConsentManager.canRequestAds) unawaited(AdManager.init());
    if (mounted) setState(() => _prePrompt = false);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Dotto',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      // Lets the menu notice it has been uncovered and re-read progress.
      navigatorObservers: [routeObserver],
      home: _prePrompt
          ? ConsentScreen(onContinue: _onContinue)
          : const MenuScreen(),
    );
  }
}
