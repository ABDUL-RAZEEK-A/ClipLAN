import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppColors {
  AppColors._();

  // ── Core Palette ──────────────────────────────────────────────────────────
  static const background = Color(0xFFF0F6FF); // Soft Ice Blue
  static const surface = Color(0xFFFFFFFF); // Pure White
  static const surfaceLight = Color(0xFFE8F1FC); // Light Blue Tint
  static const primary = Color(0xFF4A90D9); // Sky Blue
  static const primaryLight = Color(0xFF2B6CB0); // Deep Sky Blue
  static const secondary = Color(0xFF7EB8E5); // Soft Blue
  static const accent = Color(0xFF3B82F6); // Vivid Blue Accent

  // ── Semantic Colors ────────────────────────────────────────────────────────
  static const error = Color(0xFFE05252); // Soft Red
  static const warning = Color(0xFFE5A33B); // Warm Amber
  static const success = Color(0xFF38A169); // Fresh Green

  // ── Text Colors ───────────────────────────────────────────────────────────
  static const textPrimary = Color(0xFF1A2B3D); // Dark Navy
  static const textSecondary = Color(0xFF5A6F85); // Cool Gray
  static const textTertiary = Color(0xFF94A3B8); // Muted Slate

  // ── Divider ───────────────────────────────────────────────────────────────
  static const divider = Color(0xFFD6E4F0);

  // ── Gradients ─────────────────────────────────────────────────────────────
  static const gradientPrimary = LinearGradient(
    colors: [Color(0xFF4A90D9), Color(0xFF2B6CB0)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const gradientAccent = LinearGradient(
    colors: [Color(0xFF3B82F6), Color(0xFF7EB8E5), Color(0xFF93C5FD)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const gradientWarmGlow = LinearGradient(
    colors: [Color(0xFF93C5FD), Color(0xFF3B82F6)],
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
  );

  static const gradientSurface = LinearGradient(
    colors: [Color(0xFFFFFFFF), Color(0xFFF0F6FF)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
}

class AppTheme {
  AppTheme._();

  static ThemeData get darkTheme {
    return ThemeData(
      brightness: Brightness.light,
      scaffoldBackgroundColor: AppColors.background,
      primaryColor: AppColors.primary,
      colorScheme: const ColorScheme.light(
        primary: AppColors.primaryLight,
        secondary: AppColors.secondary,
        surface: AppColors.surface,
        error: AppColors.error,
        onPrimary: Colors.white,
        onSecondary: Colors.white,
        onSurface: AppColors.textPrimary,
      ),
      textTheme: GoogleFonts.interTextTheme(ThemeData.light().textTheme)
          .copyWith(
            displayLarge: GoogleFonts.outfit(
              fontSize: 32,
              fontWeight: FontWeight.bold,
              color: AppColors.textPrimary,
            ),
            headlineMedium: GoogleFonts.outfit(
              fontSize: 24,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
            titleLarge: GoogleFonts.inter(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
            titleMedium: GoogleFonts.inter(
              fontSize: 16,
              fontWeight: FontWeight.w500,
              color: AppColors.textPrimary,
            ),
            bodyLarge: GoogleFonts.inter(
              fontSize: 16,
              color: AppColors.textSecondary,
            ),
            bodyMedium: GoogleFonts.inter(
              fontSize: 14,
              color: AppColors.textSecondary,
            ),
            labelLarge: GoogleFonts.inter(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
      cardTheme: CardThemeData(
        color: AppColors.surface,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        titleTextStyle: GoogleFonts.outfit(
          fontSize: 20,
          fontWeight: FontWeight.w600,
          color: AppColors.textPrimary,
        ),
        iconTheme: const IconThemeData(color: AppColors.textPrimary),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: AppColors.primaryLight,
        foregroundColor: Colors.white,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surfaceLight,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: AppColors.primaryLight, width: 2),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 20,
          vertical: 16,
        ),
        labelStyle: const TextStyle(color: AppColors.textSecondary),
        hintStyle: const TextStyle(color: AppColors.textTertiary),
      ),
    );
  }
}
