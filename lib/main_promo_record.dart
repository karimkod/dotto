// Entry point that renders the promo out as a PNG sequence.
//
//   flutter run -t lib/main_promo_record.dart -d windows
//
// Windows rather than web on purpose: the recorder writes ~900 PNGs, and
// dart:io can put them straight on disk where ffmpeg will find them. In a
// browser every frame would have to come back through a download or an upload.
//
// Override the destination with:
//   --dart-define=PROMO_OUT=C:\somewhere\frames

import 'package:flutter/material.dart';

import 'screens/promo_recorder_screen.dart';
import 'theme/app_theme.dart';

const String _kOutDir = String.fromEnvironment(
  'PROMO_OUT',
  defaultValue: r'C:\Users\bourn\AppData\Local\Temp\dotto_promo_frames',
);

void main() => runApp(const PromoRecorderApp());

class PromoRecorderApp extends StatelessWidget {
  const PromoRecorderApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Dotto promo recorder',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      home: const PromoRecorderScreen(outDir: _kOutDir),
    );
  }
}
