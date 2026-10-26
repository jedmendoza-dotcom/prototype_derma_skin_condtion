import 'package:flutter/material.dart';

/// Height of the glass app bar (not counting the phone status bar inset).
const double kBarHeight = 72;

/// Space pages must leave at the top so content starts below the app bar.
double barInset(BuildContext context) =>
    kBarHeight + MediaQuery.of(context).padding.top;

/// Same colour with a different opacity (avoids deprecated withOpacity).
Color fade(Color c, double opacity) =>
    c.withAlpha((opacity.clamp(0.0, 1.0) * 255).round());

class AppColors {
  static const primary = Color(0xFF0A66C2); // hospital blue
  static const primaryDark = Color(0xFF084C91);
  static const accent = Color(0xFF00B4D8); // clean cyan
  static const ink = Color(0xFF0F2A43);
  static const muted = Color(0xFF5B7086);
  static const bg = Color(0xFFF3F8FD);
  static const line = Color(0xFFDCE7F3);
  static const danger = Color(0xFFD64545);
  static const success = Color(0xFF1B9E77);
  static const warning = Color(0xFFF2A100);
}

ThemeData buildTheme() {
  OutlineInputBorder border(Color c, [double w = 1]) => OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: c, width: w),
      );

  return ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(seedColor: AppColors.primary),
    scaffoldBackgroundColor: AppColors.bg,
    textTheme: ThemeData.light().textTheme.apply(
          bodyColor: AppColors.ink,
          displayColor: AppColors.ink,
        ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: const Color(0xFFF7FAFE),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      border: border(AppColors.line),
      enabledBorder: border(AppColors.line),
      disabledBorder: border(AppColors.line),
      focusedBorder: border(AppColors.primary, 1.6),
      errorBorder: border(AppColors.danger),
      focusedErrorBorder: border(AppColors.danger, 1.6),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        minimumSize: const Size(0, 52),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.primary,
        minimumSize: const Size(0, 52),
        side: const BorderSide(color: AppColors.primary, width: 1.4),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
      ),
    ),
  );
}
