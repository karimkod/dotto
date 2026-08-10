import 'package:flutter/material.dart';

import 'progress/progress_store.dart';
import 'screens/menu_screen.dart';
import 'theme/app_theme.dart';

Future<void> main() async {
  // Progress is read synchronously while the level list builds, so it has to be
  // in memory before the first frame — otherwise a returning player sees a
  // fully locked map for an instant.
  WidgetsFlutterBinding.ensureInitialized();
  await ProgressStore.init();
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
      home: const MenuScreen(),
    );
  }
}
