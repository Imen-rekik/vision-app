import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppColors {
  static const Color electricCyan = Color(0xFF00E5FF);
  static const Color topLightBlue = Color(0xFF9DC9D6);
  static const Color deepMidnight = Color(0xFF162836);
  static const Color crispWhite = Color(0xFFFFFFFF);
  static const Color glassFill = Color(0x1FFFFFFF); // 12% white fill
  static const Color glassBorder = Color(0x4D00E5FF); // 30% cyan stroke
  static const Color errorRed = Color(0xFFFF5252);
  static const Color warningOrange = Color(0xFFFFAB40);
}

class AppTheme {
  static ThemeData get darkTheme {
    return ThemeData(
      brightness: Brightness.dark,
      primaryColor: AppColors.electricCyan,
      scaffoldBackgroundColor: AppColors.deepMidnight,
      colorScheme: const ColorScheme.dark(
        primary: AppColors.electricCyan,
        secondary: AppColors.topLightBlue,
        surface: AppColors.deepMidnight,
        error: AppColors.errorRed,
      ),
      textTheme: GoogleFonts.interTextTheme(ThemeData.dark().textTheme)
          .copyWith(
            displayLarge: GoogleFonts.inter(
              fontSize: 34,
              fontWeight: FontWeight.bold,
              color: AppColors.crispWhite,
            ),
            titleLarge: GoogleFonts.inter(
              fontSize: 24,
              fontWeight: FontWeight.w700,
              color: AppColors.crispWhite,
            ),
            bodyLarge: GoogleFonts.inter(
              fontSize: 18,
              fontWeight: FontWeight.w500,
              color: AppColors.crispWhite,
            ),
            bodyMedium: GoogleFonts.inter(
              fontSize: 16,
              color: AppColors.crispWhite,
            ),
          ),
      iconTheme: const IconThemeData(color: AppColors.crispWhite),
      useMaterial3: true,
    );
  }
}
