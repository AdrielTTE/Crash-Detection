import 'package:flutter/material.dart';

/// Instrument-panel palette. Dark by design: this screen is read at a glance
/// while the phone is mounted in a vehicle, and a light ground washes out the
/// live traces in daylight through a windscreen.
abstract final class AppColors {
  static const background = Color(0xFF0E1013);
  static const surface = Color(0xFF171A1F);
  static const surfaceAlt = Color(0xFF1F242B);
  static const border = Color(0xFF2A2F38);

  static const textPrimary = Color(0xFFE8EAED);
  static const textSecondary = Color(0xFF9BA3AF);
  static const textMuted = Color(0xFF666E7A);

  /// One colour per sensor channel, reused by the card header, the value and
  /// the trace so a reading and its plot are always visually paired.
  static const accel = Color(0xFF4EA8FF);
  static const linear = Color(0xFFFF6B3F);
  static const gyro = Color(0xFFB07BFF);
  static const magnet = Color(0xFF3FD9A4);
  static const baro = Color(0xFFFFC94E);
  static const location = Color(0xFF52D1FF);

  static const ok = Color(0xFF3FD97A);
  static const warn = Color(0xFFFFB020);
  static const danger = Color(0xFFFF4D4D);
}

abstract final class AppTheme {
  /// Tabular figures matter more than the typeface here — without them every
  /// digit change reflows the row and the numbers are unreadable in motion.
  static const numeric = TextStyle(
    fontFamily: 'monospace',
    fontFeatures: [FontFeature.tabularFigures()],
  );

  static ThemeData get dark {
    final base = ThemeData.dark(useMaterial3: true);
    return base.copyWith(
      scaffoldBackgroundColor: AppColors.background,
      colorScheme: base.colorScheme.copyWith(
        surface: AppColors.surface,
        primary: AppColors.linear,
        error: AppColors.danger,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.background,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
      ),
      dividerColor: AppColors.border,
    );
  }
}
