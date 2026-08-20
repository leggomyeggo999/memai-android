import 'package:flutter/material.dart';

/// MemDroid typography.
///
/// **Font decision — no `google_fonts`, no new packages, no network fetch.**
/// A runtime-fetched webface would make the first cold/offline start render a
/// different face than the design, and would race a network call in CI. The
/// identity here is carried by the *scale* — sizes, weights, tracking, and
/// tabular figures — not by a bespoke face. We ship on the platform stack with
/// an explicitly pinned fallback so rendering is identical on device and in CI.
///
/// **Global numeral rule (mandatory):** every style below carries
/// [FontFeature.tabularFigures]. Timestamps, counts, elapsed timers and `n/4`
/// figures then tick without a pixel of layout shift.

/// `null` means "inherit the platform default" (Roboto on Android). The
/// fallback list below is what actually pins rendering.
const String? kMemSans = null;

/// Pinned sans fallback — set on every [TextStyle] the theme produces.
const List<String> kMemSansFallback = <String>['Roboto', 'Noto Sans', 'sans-serif'];

/// Monospace face for inline code, code blocks, and raw model ids.
const String kMemMono = 'RobotoMono';

/// Pinned mono fallback.
const List<String> kMemMonoFallback = <String>['monospace'];

/// The global numeral rule. Applied to every style in [memTextTheme] and to
/// [memMonoStyle].
const List<FontFeature> kMemTabularFigures = <FontFeature>[
  FontFeature.tabularFigures(),
];

/// One sans style on the pinned stack, with tabular figures.
///
/// [lineHeight] is the design line-height in logical pixels (the spec writes
/// the scale as `size/line-height`); it is converted to the multiplier
/// `TextStyle.height` wants.
TextStyle memSansStyle({
  required double fontSize,
  required double lineHeight,
  required FontWeight fontWeight,
  required double letterSpacing,
  Color? color,
}) {
  return TextStyle(
    fontFamily: kMemSans,
    fontFamilyFallback: kMemSansFallback,
    fontFeatures: kMemTabularFigures,
    fontSize: fontSize,
    height: lineHeight / fontSize,
    fontWeight: fontWeight,
    letterSpacing: letterSpacing,
    color: color,
  );
}

/// One mono style on the pinned stack, with tabular figures.
///
/// Defaults match the Markdown code ramp: 13/20 w400.
TextStyle memMonoStyle({
  double fontSize = 13,
  double lineHeight = 20,
  FontWeight fontWeight = FontWeight.w400,
  double letterSpacing = 0,
  Color? color,
}) {
  return TextStyle(
    fontFamily: kMemMono,
    fontFamilyFallback: kMemMonoFallback,
    fontFeatures: kMemTabularFigures,
    fontSize: fontSize,
    height: lineHeight / fontSize,
    fontWeight: fontWeight,
    letterSpacing: letterSpacing,
    color: color,
  );
}

/// The complete MemDroid [TextTheme].
///
/// All fifteen roles are defined explicitly — an undefined role would be
/// merged in from `Typography`'s defaults and would arrive **without** the
/// pinned fallback and **without** tabular figures.
///
/// Every style is coloured `scheme.onSurface`. Secondary text is *always*
/// `onSurfaceVariant` at the call site — never `onSurface` with an opacity,
/// which is the most common M3 dark-mode contrast failure and is banned.
///
/// Role map (size/line-height, weight, tracking):
/// * `displaySmall` 32/38 w700 −0.5 — empty-state and first-run headlines
/// * `headlineSmall` 24/30 w600 −0.25 — NoteDetail title
/// * `titleLarge` 20/26 w600 −0.2 — AppBar titles
/// * `titleMedium` 16/22 w600 −0.1 — row and card titles
/// * `titleSmall` 14/20 w600 0 — sheet headers, `StatusTile` labels
/// * `bodyLarge` 16/26 w400 0 — Markdown body, chat text, multi-line inputs
/// * `bodyMedium` 14/20 w400 0 — row snippets, field descriptions
/// * `bodySmall` 12/16 w400 +0.1 — metadata, timestamps, counts
/// * `labelLarge` 14/20 w600 +0.1 — buttons
/// * `labelMedium` 12/16 w600 +0.4 — chips, collection tags, **date group
///   headers in sentence case**
/// * `labelSmall` 11/14 w700 +0.8 — structural section eyebrows (UPPERCASE)
///
/// The larger display/headline roles above `displaySmall` extend the same ramp
/// so nothing can fall through to an unpinned default.
TextTheme memTextTheme(ColorScheme scheme) {
  final Color ink = scheme.onSurface;
  return TextTheme(
    displayLarge: memSansStyle(
      fontSize: 45,
      lineHeight: 52,
      fontWeight: FontWeight.w700,
      letterSpacing: -1.0,
      color: ink,
    ),
    displayMedium: memSansStyle(
      fontSize: 38,
      lineHeight: 44,
      fontWeight: FontWeight.w700,
      letterSpacing: -0.75,
      color: ink,
    ),
    displaySmall: memSansStyle(
      fontSize: 32,
      lineHeight: 38,
      fontWeight: FontWeight.w700,
      letterSpacing: -0.5,
      color: ink,
    ),
    headlineLarge: memSansStyle(
      fontSize: 30,
      lineHeight: 36,
      fontWeight: FontWeight.w600,
      letterSpacing: -0.4,
      color: ink,
    ),
    headlineMedium: memSansStyle(
      fontSize: 26,
      lineHeight: 32,
      fontWeight: FontWeight.w600,
      letterSpacing: -0.3,
      color: ink,
    ),
    headlineSmall: memSansStyle(
      fontSize: 24,
      lineHeight: 30,
      fontWeight: FontWeight.w600,
      letterSpacing: -0.25,
      color: ink,
    ),
    titleLarge: memSansStyle(
      fontSize: 20,
      lineHeight: 26,
      fontWeight: FontWeight.w600,
      letterSpacing: -0.2,
      color: ink,
    ),
    titleMedium: memSansStyle(
      fontSize: 16,
      lineHeight: 22,
      fontWeight: FontWeight.w600,
      letterSpacing: -0.1,
      color: ink,
    ),
    titleSmall: memSansStyle(
      fontSize: 14,
      lineHeight: 20,
      fontWeight: FontWeight.w600,
      letterSpacing: 0,
      color: ink,
    ),
    bodyLarge: memSansStyle(
      fontSize: 16,
      lineHeight: 26,
      fontWeight: FontWeight.w400,
      letterSpacing: 0,
      color: ink,
    ),
    bodyMedium: memSansStyle(
      fontSize: 14,
      lineHeight: 20,
      fontWeight: FontWeight.w400,
      letterSpacing: 0,
      color: ink,
    ),
    bodySmall: memSansStyle(
      fontSize: 12,
      lineHeight: 16,
      fontWeight: FontWeight.w400,
      letterSpacing: 0.1,
      color: ink,
    ),
    labelLarge: memSansStyle(
      fontSize: 14,
      lineHeight: 20,
      fontWeight: FontWeight.w600,
      letterSpacing: 0.1,
      color: ink,
    ),
    labelMedium: memSansStyle(
      fontSize: 12,
      lineHeight: 16,
      fontWeight: FontWeight.w600,
      letterSpacing: 0.4,
      color: ink,
    ),
    labelSmall: memSansStyle(
      fontSize: 11,
      lineHeight: 14,
      fontWeight: FontWeight.w700,
      letterSpacing: 0.8,
      color: ink,
    ),
  );
}
