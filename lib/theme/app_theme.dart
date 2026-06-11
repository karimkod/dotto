import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Central palette + text styles for Dotto, mirroring the HTML prototype.
class AppColors {
  AppColors._();

  /// Warm cream background.
  static const background = Color(0xFFFAF8F5);

  /// White card / grid surface.
  static const card = Color(0xFFFFFFFF);

  /// Subtle card border.
  static const border = Color(0xFFE0DDD8);

  /// Warm orange accent.
  static const accent = Color(0xFFFFB347);

  /// Coral-red accent (used for the play button gradient).
  static const coral = Color(0xFFFF6B6B);

  /// Blue-gray for locked levels.
  static const locked = Color(0xFF78909C);

  /// Primary dark text.
  static const text = Color(0xFF2D2D2D);

  /// Muted secondary text.
  static const textSoft = Color(0xFF9A958C);

  /// Gold star for completed levels.
  static const star = Color(0xFFFFD54F);

  /// Soft shadow color shared by cards and icon containers.
  static const shadow = Color(0x14786E5F); // rgba(120,110,95,.08)

  /// Coral → orange gradient for the main play button.
  static const playGradient = LinearGradient(
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
    colors: [coral, accent],
  );
}

class AppTheme {
  AppTheme._();

  static ThemeData get light {
    final base = ThemeData(
      useMaterial3: true,
      scaffoldBackgroundColor: AppColors.background,
      colorScheme: ColorScheme.fromSeed(
        seedColor: AppColors.accent,
        primary: AppColors.accent,
        surface: AppColors.background,
      ),
    );

    return base.copyWith(
      textTheme: GoogleFonts.nunitoTextTheme(base.textTheme).apply(
        bodyColor: AppColors.text,
        displayColor: AppColors.text,
      ),
    );
  }

  /// Big playful wordmark style for the "Dotto" title.
  static TextStyle get title => GoogleFonts.poppins(
        fontSize: 40,
        fontWeight: FontWeight.w800,
        fontStyle: FontStyle.italic,
        color: AppColors.text,
        letterSpacing: 0.5,
      );

  /// Common soft shadow for raised surfaces.
  static List<BoxShadow> softShadow({double y = 4, double blur = 12}) => [
        BoxShadow(
          color: AppColors.shadow,
          offset: Offset(0, y),
          blurRadius: blur,
        ),
      ];
}
