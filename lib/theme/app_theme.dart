import 'package:flutter/material.dart';

class AppColors {
  // Primary gradient colors - Orange to Deep Orange
  static const primaryStart = Color(0xFFFF8C00);
  static const primaryEnd = Color(0xFFFF6B35);

  // Secondary gradient colors - Yellow to Orange
  static const secondaryStart = Color(0xFFFFB700);
  static const secondaryEnd = Color(0xFFFF8C00);

  // Accent gradient colors - Bright Orange to Yellow
  static const accentStart = Color(0xFFFF9500);
  static const accentEnd = Color(0xFFFFCC00);

  // Success/Money gradient - Gold to Amber
  static const successStart = Color(0xFFFFC107);
  static const successEnd = Color(0xFFFF9800);

  // Card gradient - Tangerine to Orange
  static const cardStart = Color(0xFFFF7043);
  static const cardEnd = Color(0xFFFF5722);

  // Info gradient - Yellow to Golden
  static const infoStart = Color(0xFFFFD54F);
  static const infoEnd = Color(0xFFFFB300);

  // Warm gradient - Coral Orange to Peach
  static const warmStart = Color(0xFFFF9966);
  static const warmEnd = Color(0xFFFF6F61);

  // Neutral colors
  static const backgroundColor = Color(0xFFF8F9FA);
  static const cardBackground = Colors.white;
  static const textPrimary = Color(0xFF2C3E50);
  static const textSecondary = Color(0xFF7F8C8D);
  static const textLight = Color(0xFFBDC3C7);

  // Gradients with creative angles
  static const LinearGradient primaryGradient = LinearGradient(
    colors: [primaryStart, primaryEnd],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient secondaryGradient = LinearGradient(
    colors: [secondaryStart, secondaryEnd],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient successGradient = LinearGradient(
    colors: [successStart, successEnd],
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
  );

  static const LinearGradient cardGradient = LinearGradient(
    colors: [cardStart, cardEnd],
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
  );

  static const LinearGradient accentGradient = LinearGradient(
    colors: [accentStart, accentEnd],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient infoGradient = LinearGradient(
    colors: [infoStart, infoEnd],
    begin: Alignment.topRight,
    end: Alignment.bottomLeft,
  );

  static const LinearGradient warmGradient = LinearGradient(
    colors: [warmStart, warmEnd],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
}

class AppTheme {
  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,
      scaffoldBackgroundColor: AppColors.backgroundColor,
      colorScheme: ColorScheme.fromSeed(
        seedColor: AppColors.primaryStart,
        brightness: Brightness.light,
      ),
      appBarTheme: const AppBarTheme(
        elevation: 0,
        centerTitle: true,
        iconTheme: IconThemeData(color: Colors.white),
        titleTextStyle: TextStyle(
          color: Colors.white,
          fontSize: 20,
          fontWeight: FontWeight.bold,
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 4,
        shadowColor: Colors.black.withValues(alpha: 0.1),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        elevation: 6,
      ),
    );
  }
}
