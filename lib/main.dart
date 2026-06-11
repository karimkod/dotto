import 'package:flutter/material.dart';

import 'screens/menu_screen.dart';
import 'theme/app_theme.dart';

void main() {
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
