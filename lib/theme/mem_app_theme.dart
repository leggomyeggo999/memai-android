import 'package:flutter/material.dart';

/// OLED-friendly dark surfaces — intentionally **not** a copy of the Mem web
/// layout; mobile-first rhythm and contrast per Material 3.
ThemeData buildMemAppTheme() {
  const seed = Color(0xFF1E5AA8);
  final base = ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: ColorScheme.fromSeed(
      seedColor: seed,
      brightness: Brightness.dark,
      surface: const Color(0xFF0A0A0A),
    ),
  );
  return base.copyWith(
    scaffoldBackgroundColor: const Color(0xFF050505),
    cardTheme: CardThemeData(
      color: const Color(0xFF121212),
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
    appBarTheme: const AppBarTheme(centerTitle: false, scrolledUnderElevation: 0),
  );
}
