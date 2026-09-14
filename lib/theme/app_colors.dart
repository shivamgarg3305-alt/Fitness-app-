import 'package:flutter/material.dart';

class AppColors {
  static const Color navyDeep = Color(0xFF0B132B);

  static const Color cyan = Color(0xFF00D9FF);
  static const Color cyanBright = Color(0xFF5CEBFF);

  static const Color textPrimary = Color(0xFFF5F7FA);
  static const Color textSecondary = Color(0xFFB8C2D1);
  static const Color textDim = Color(0xFF7F8A9A);

  static const LinearGradient dashboardBackground = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [
      Color(0xFF101C3A),
      Color(0xFF0B132B),
    ],
  );
}
