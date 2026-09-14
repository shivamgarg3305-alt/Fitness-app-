import 'package:flutter/material.dart';

class AppColors {

  static const Color navyDeep = Color(0xFF0B132B);

  static const Color cyan = Color(0xFF00D9FF);
  static const Color cyanBright = Color(0xFF5CEBFF);

  static const Color textPrimary = Color(0xFFF5F7FA);
  static const Color textSecondary = Color(0xFFB8C2D1);
  static const Color textDim = Color(0xFF7F8A9A);

  static const Color micGreen = Color(0xFF32D74B);

  static const LinearGradient dashboardBackground = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [
      Color(0xFF101C3A),
      Color(0xFF0B132B),
    ],
  );

  static const LinearGradient sessionButtonGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      Color(0xFF00D9FF),
      Color(0xFF007AFF),
    ],
  );

  // Base surfaces
  static const Color pureBlack = Color(0xFF000000);
  static const Color navyBase = Color(0xFF0B132B);
  static const Color navyDeep = Color(0xFF060A1A);
  static const Color dashboardBackground = Color(0xFF0D1526);

  // Cards
  static const Color purpleCard = Color(0xFF2E2557);

  // Accents
  static const Color cyan = Color(0xFF00BCD4);
  static const Color cyanBright = Color(0xFF18FFFF);
  static const Color violet = Color(0xFF8A63D2);
  static const Color micGreen = Color(0xFF4CD964);

  // Text
  static const Color textPrimary = Color(0xFFFFFFFF);
  static const Color textSecondary = Color(0xFFB0B3B8);
  static const Color textDim = Color(0xFF6B7280);

  // Gradients
  static const List<Color> cardGradient = [
    Color(0xFF2E2557),
    Color(0xFF1B1440),
  ];

  static const List<Color> sessionButtonGradient = [
    Color(0xFF00BCD4),
    Color(0xFF18FFFF),
  ];

}
