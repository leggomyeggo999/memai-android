import 'package:flutter/material.dart';

/// The two explicit MemDroid colour schemes — "Midnight Instrument" (dark, the
/// default identity) and "Daylight Instrument" (light, a cool paper twin).
///
/// Both are constructed **field by field**, never through
/// `ColorScheme.fromSeed`: an unset role silently falls back to a
/// seed-derived colour and drifts away from the audited contrast table.
/// `test/theme_contrast_test.dart` pins every value below.
///
/// This is the only file in the app allowed to spell out raw `Color(0x…)`
/// literals for scheme roles; everything else reads
/// `Theme.of(context).colorScheme`.

/// DARK — the default. True black canvas so OLED panels switch pixels off.
const ColorScheme memDarkScheme = ColorScheme(
  brightness: Brightness.dark,

  primary: Color(0xFF5EA2FF),
  onPrimary: Color(0xFF002F63),
  primaryContainer: Color(0xFF123A78),
  onPrimaryContainer: Color(0xFFCFE2FF),
  primaryFixed: Color(0xFFCFE2FF),
  onPrimaryFixed: Color(0xFF002F63),
  primaryFixedDim: Color(0xFF9EC6FF),
  onPrimaryFixedVariant: Color(0xFF06407F),

  secondary: Color(0xFFA9B4C6),
  onSecondary: Color(0xFF16202E),
  secondaryContainer: Color(0xFF232C3A),
  onSecondaryContainer: Color(0xFFD8E1F0),

  // AI ONLY — the violet is reserved for model provenance. No stock component
  // may resolve to it; the theme pins them all to primary/secondaryContainer.
  tertiary: Color(0xFFB79DFF),
  onTertiary: Color(0xFF26105E),
  tertiaryContainer: Color(0xFF3A2A6E),
  onTertiaryContainer: Color(0xFFE5DBFF),

  error: Color(0xFFFF6369),
  onError: Color(0xFF3A0507),
  errorContainer: Color(0xFF5C1519),
  onErrorContainer: Color(0xFFFFD9D9),

  surface: Color(0xFF050505), // scaffold + canvas
  onSurface: Color(0xFFEDEDF0),
  onSurfaceVariant: Color(0xFF9A9AA5),
  surfaceDim: Color(0xFF050505),
  surfaceBright: Color(0xFF2A2A30),
  surfaceContainerLowest: Color(0xFF0A0A0A), // sticky bars, input bar
  surfaceContainerLow: Color(0xFF0E0E10), // list sections, cards
  surfaceContainer: Color(0xFF121214), // inputs, chips, search pill
  surfaceContainerHigh: Color(0xFF17171A), // pressed rows, user bubbles
  surfaceContainerHighest: Color(0xFF1C1C20), // sheets, dialogs

  outline: Color(0xFF63636F), // BOUNDARY hairline — >=3:1
  outlineVariant: Color(0xFF2E2E36), // DIVIDER hairline — decorative

  inverseSurface: Color(0xFFEDEDF0),
  onInverseSurface: Color(0xFF17171A),
  inversePrimary: Color(0xFF1E5AC8),

  surfaceTint: Color(0x00000000), // transparent — kills the M3 elevation tint
  shadow: Color(0xFF000000),
  scrim: Color(0xFF000000),
);

/// LIGHT — deliberately a cool paper, not a warm cream, and it uses the
/// identical depth grammar (zero elevation, hairlines, no shadows).
const ColorScheme memLightScheme = ColorScheme(
  brightness: Brightness.light,

  primary: Color(0xFF1E5AC8), // evolution of the historic #1E5AA8 seed
  onPrimary: Color(0xFFFFFFFF),
  primaryContainer: Color(0xFFDCE8FF),
  onPrimaryContainer: Color(0xFF062E6B),
  primaryFixed: Color(0xFFDCE8FF),
  onPrimaryFixed: Color(0xFF062E6B),
  primaryFixedDim: Color(0xFFAFC9F5),
  onPrimaryFixedVariant: Color(0xFF124397),

  secondary: Color(0xFF4D5A6E),
  onSecondary: Color(0xFFFFFFFF),
  secondaryContainer: Color(0xFFE1E7F0),
  onSecondaryContainer: Color(0xFF1D2836),

  // AI ONLY — see the dark scheme note above.
  tertiary: Color(0xFF6A48D0),
  onTertiary: Color(0xFFFFFFFF),
  tertiaryContainer: Color(0xFFE9E1FF),
  onTertiaryContainer: Color(0xFF2A1265),

  error: Color(0xFFBA1A1A),
  onError: Color(0xFFFFFFFF),
  errorContainer: Color(0xFFFFDAD6),
  onErrorContainer: Color(0xFF410002),

  surface: Color(0xFFFBFBFC),
  onSurface: Color(0xFF17181C),
  onSurfaceVariant: Color(0xFF5C616B),
  surfaceDim: Color(0xFFDCDDE2),
  surfaceBright: Color(0xFFFFFFFF),
  surfaceContainerLowest: Color(0xFFFFFFFF),
  surfaceContainerLow: Color(0xFFF6F7F9),
  surfaceContainer: Color(0xFFF1F2F5),
  surfaceContainerHigh: Color(0xFFEBECF0),
  surfaceContainerHighest: Color(0xFFE4E6EB),

  outline: Color(0xFF7E828C), // BOUNDARY hairline — >=3:1
  outlineVariant: Color(0xFFD7DAE1), // DIVIDER hairline — decorative

  inverseSurface: Color(0xFF2C2E33),
  onInverseSurface: Color(0xFFF1F2F5),
  inversePrimary: Color(0xFF5EA2FF),

  surfaceTint: Color(0x00000000),
  shadow: Color(0xFF000000),
  scrim: Color(0xFF000000),
);

/// The scheme for [brightness]. Dark is the product default.
ColorScheme memSchemeFor(Brightness brightness) =>
    brightness == Brightness.dark ? memDarkScheme : memLightScheme;

/// Modal scrim opacity — 60 %, dark and light alike. The scrim is the only
/// darkness in the app that is allowed to read as a shadow.
const double kMemScrimOpacity = 0.60;

/// Focus ring: 2 dp `primary` drawn *outside* the shape, at this alpha.
const double kMemFocusRingWidth = 2.0;
const double kMemFocusRingOpacity = 0.40;
