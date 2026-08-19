// Entry point for the Play Store feature graphic.
//
//   flutter run -t lib/main_feature_graphic.dart -d emulator-5554
//
// Deliberately its own entry point rather than a route inside the shipped app:
// the graphic is a build artefact, and it should not drag Firebase, consent,
// ads or the progress store through startup just to draw a still. The route is
// registered below so it can still be pushed by name.

import 'package:flutter/material.dart';

import 'screens/feature_graphic_screen.dart';
import 'theme/app_theme.dart';

void main() => runApp(const FeatureGraphicApp());

class FeatureGraphicApp extends StatelessWidget {
  const FeatureGraphicApp({super.key});

  /// Route name, so the screen can be pushed rather than only opened cold.
  static const String route = '/feature-graphic';

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Dotto feature graphic',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      initialRoute: route,
      routes: {
        route: (_) => const FeatureGraphicScreen(),
      },
    );
  }
}
