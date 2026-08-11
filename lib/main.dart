import 'dart:async';

import 'package:flutter/material.dart';

import 'ads/ad_manager.dart';
import 'app_routes.dart';
import 'progress/progress_store.dart';
import 'screens/menu_screen.dart';
import 'theme/app_theme.dart';

Future<void> main() async {
  // Progress is read synchronously while the level list builds, so it has to be
  // in memory before the first frame — otherwise a returning player sees a
  // fully locked map for an instant.
  WidgetsFlutterBinding.ensureInitialized();
  await ProgressStore.init();
  // Ads start in the background: consent and the first ad fetch involve the
  // network, and none of it should stand between launch and the first frame.
  // AdManager fails soft, so a slow or failed start just means no ads.
  unawaited(AdManager.init());
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
