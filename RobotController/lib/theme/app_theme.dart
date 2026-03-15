import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Design system colors matching the UI design document.
class AppColors {
  static const Color background = Color(0xFF0A1628);
  static const Color surface = Color(0xFF12233D);
  static const Color primaryAccent = Color(0xFF00D4FF);
  static const Color secondaryAccent = Color(0xFFFF6B35);
  static const Color tertiaryAccent = Color(0xFFFFD600);
  static const Color danger = Color(0xFFFF3B3B);
  static const Color success = Color(0xFF00E676);
  static const Color textPrimary = Color(0xFFFFFFFF);
  static const Color textSecondary = Color(0xFF8EAFC6);
  static const Color gridDivider = Color(0xFF1A3050);
  static const Color primaryAccentDim = Color(0x4D00D4FF);
  static const Color surface80 = Color(0xCC12233D);
  static const Color backgroundDark = Color(0xFF070F1C);
}

/// Text styles using Google Fonts.
class AppTextStyles {
  static TextStyle title() => GoogleFonts.orbitron(
        fontSize: 20,
        fontWeight: FontWeight.bold,
        color: AppColors.primaryAccent,
      );

  static TextStyle buttonLabel() => GoogleFonts.rajdhani(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: AppColors.textPrimary,
      );

  static TextStyle dataValue() => GoogleFonts.jetBrainsMono(
        fontSize: 14,
        color: AppColors.textSecondary,
      );

  static TextStyle caption() => GoogleFonts.roboto(
        fontSize: 12,
        color: AppColors.textSecondary,
      );
}

/// App-wide dark theme.
class AppTheme {
  static ThemeData get darkTheme => ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: AppColors.background,
        colorScheme: const ColorScheme.dark(
          primary: AppColors.primaryAccent,
          secondary: AppColors.secondaryAccent,
          surface: AppColors.surface,
          error: AppColors.danger,
          onPrimary: AppColors.background,
          onSecondary: AppColors.textPrimary,
          onSurface: AppColors.textPrimary,
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: AppColors.background,
          elevation: 0,
        ),
        sliderTheme: SliderThemeData(
          activeTrackColor: AppColors.primaryAccent,
          inactiveTrackColor: AppColors.gridDivider,
          thumbColor: AppColors.secondaryAccent,
          overlayColor: AppColors.primaryAccent.withValues(alpha: 0.2),
          trackHeight: 4,
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.secondaryAccent,
            foregroundColor: AppColors.textPrimary,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: AppColors.background,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(6),
            borderSide: BorderSide.none,
          ),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        ),
      );
}
