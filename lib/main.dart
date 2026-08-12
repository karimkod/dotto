import 'dart:async';

import 'package:flutter/material.dart';

import 'ads/ad_manager.dart';
import 'analytics/analytics_service.dart';
import 'app_routes.dart';
import 'progress/progress_store.dart';
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
  // Ads start in the background: consent and the first ad fetch involve the
  // network, and none of it should stand between launch and the first frame.
  // AdManager fails soft, so a slow or failed start just means no ads.
  unawaited(AdManager.init());
  // Same treatment, same reason: Firebase start-up touches the network, and
  // until `flutterfire configure` has been run it fails outright. Neither
  // should delay or block the first frame.
  unawaited(Analytics.init());
  // Optional and quiet: a player who never signs in should not be able to tell
  // this exists.
  unawaited(GameServices.signIn());
  runApp(const DottoApp());
}

class DottoApp extends StatelessWidget {
  const DottoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Dotto',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      // Lets the menu notice it has been uncovered and re-read progress.
      navigatorObservers: [routeObserver],
      home: const MenuScreen(),
    );
  }
}
