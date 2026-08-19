// Entry point for the Play Store promo video.
//
//   flutter run -t lib/main_promo.dart -d chrome
//
// Its own entry point rather than a route inside the shipped app, for the same
// reason the feature graphic has one: the video is a build artefact, and it
// should not drag Firebase, consent, ads or the progress store through startup
// just to play a loop. Size the window 16:9 and screen-record it.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'screens/promo_video_screen.dart';
import 'theme/app_theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // Landscape only. A no-op on the web, where the window is the frame.
  SystemChrome.setPreferredOrientations(const [
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  runApp(const PromoApp());
}

class PromoApp extends StatelessWidget {
  const PromoApp({super.key});

  /// Route name, so the screen can be pushed rather than only opened cold.
  static const String route = '/promo-video';

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Dotto promo',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      initialRoute: route,
      routes: {
        route: (_) => const PromoVideoScreen(),
      },
    );
  }
}
