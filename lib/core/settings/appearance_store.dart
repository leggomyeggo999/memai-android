import 'package:flutter/material.dart' show ThemeMode;
import 'package:shared_preferences/shared_preferences.dart';

/// Storage key for the Appearance preference. Values are the literal strings
/// `system` / `light` / `dark`; anything else (including a missing entry)
/// decodes to the product default, [ThemeMode.dark].
const String kAppearanceThemeModeKey = 'appearance_theme_mode_v1';

const String _kSystem = 'system';
const String _kLight = 'light';
const String _kDark = 'dark';

/// Persists the Settings → Appearance choice (System / Light / Dark).
///
/// Deliberately plain `shared_preferences`, not the secure vault: this is a
/// display preference, not a secret, and it must be readable cheaply during
/// `AppState.load()` before the first frame settles on a theme.
class AppearanceStore {
  /// The stored mode, or [ThemeMode.dark] when nothing has been stored yet.
  Future<ThemeMode> loadThemeMode() async {
    final p = await SharedPreferences.getInstance();
    return decodeThemeMode(p.getString(kAppearanceThemeModeKey));
  }

  Future<void> saveThemeMode(ThemeMode mode) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(kAppearanceThemeModeKey, encodeThemeMode(mode));
  }

  /// Wire format — stable, do not rename without bumping the key suffix.
  static String encodeThemeMode(ThemeMode mode) => switch (mode) {
    ThemeMode.system => _kSystem,
    ThemeMode.light => _kLight,
    ThemeMode.dark => _kDark,
  };

  /// Tolerates null and unknown values: dark is the shipped default and the
  /// launch splash is dark, so an unreadable preference must not flash light.
  static ThemeMode decodeThemeMode(String? raw) => switch (raw) {
    _kSystem => ThemeMode.system,
    _kLight => ThemeMode.light,
    _ => ThemeMode.dark,
  };
}
