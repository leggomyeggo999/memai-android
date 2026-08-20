import 'package:flutter/material.dart';

import 'mem_color_schemes.dart';
import 'mem_metrics.dart';
import 'mem_semantic_colors.dart';
import 'mem_typography.dart';

/// Builds the one MemDroid [ThemeData] for [brightness].
///
/// Ground rules baked in here so no screen has to remember them:
///
/// * **Elevation is zero, app-wide.** Every surface gets `elevation: 0` and a
///   transparent `surfaceTintColor`. Depth is a surface step plus a 1 dp
///   hairline. There is no `BoxShadow` in either theme; the only darkness that
///   reads as a shadow is the 60 % modal scrim.
/// * **The 80 ms press is the signature.** `splashFactory: NoSplash` globally,
///   with `surfaceContainerHigh` as the press flash and
///   `animationDuration: MemMotion.press` on every button style.
/// * **`tertiary` is reserved for AI provenance.** `SegmentedButton`, `Switch`,
///   `Slider`, `Radio`, `Checkbox`, `FilterChip` selection, and
///   `ProgressIndicator` are pinned to `primary` / `secondaryContainer` so M3
///   can never hand one of them the violet.
/// * **The global [InputDecorationTheme] owns `OutlineInputBorder`.** No
///   `TextField` re-declares one inline.
ThemeData buildMemTheme(Brightness brightness) {
  final ColorScheme scheme = memSchemeFor(brightness);
  final TextTheme text = memTextTheme(scheme);
  final MemSemanticColors semantics = MemSemanticColors.of(brightness);

  // 1.0 is the design hairline. Widgets that can see a BuildContext must snap
  // it to whole physical pixels with hairlineWidth(context); the theme has no
  // context, so the theme-level defaults use the nominal 1.0.
  const double hairline = 1.0;

  OutlineInputBorder inputBorder(Color color, double width) =>
      OutlineInputBorder(
        borderRadius: MemRadius.sectionAll,
        borderSide: BorderSide(color: color, width: width),
      );

  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    extensions: <ThemeExtension<dynamic>>[semantics],

    scaffoldBackgroundColor: scheme.surface,
    canvasColor: scheme.surface,
    dividerColor: scheme.outlineVariant,

    textTheme: text,
    primaryTextTheme: text,

    // NoSplash + an opaque pressed-surface highlight is the whole press
    // language: a flash to surfaceContainerHigh, never a 300 ms ripple bloom.
    splashFactory: NoSplash.splashFactory,
    splashColor: Colors.transparent,
    highlightColor: scheme.surfaceContainerHigh,

    materialTapTargetSize: MaterialTapTargetSize.padded,
    visualDensity: VisualDensity.standard,
    iconTheme: IconThemeData(color: scheme.onSurface),

    pageTransitionsTheme: const PageTransitionsTheme(
      builders: <TargetPlatform, PageTransitionsBuilder>{
        TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
      },
    ),

    dividerTheme: DividerThemeData(
      thickness: hairline,
      space: hairline,
      color: scheme.outlineVariant,
    ),

    appBarTheme: AppBarThemeData(
      centerTitle: false,
      elevation: 0,
      scrolledUnderElevation: 0,
      shadowColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      backgroundColor: scheme.surface,
      foregroundColor: scheme.onSurface,
      titleTextStyle: text.titleLarge,
      toolbarTextStyle: text.bodyMedium,
      iconTheme: IconThemeData(color: scheme.onSurface),
      actionsIconTheme: IconThemeData(color: scheme.onSurface),
    ),

    // The shell wraps this in a decoration-only Container for the top
    // hairline; the bar itself is continuous with the canvas — no seam.
    navigationBarTheme: NavigationBarThemeData(
      height: MemInsets.navBarHeight,
      backgroundColor: scheme.surface,
      elevation: 0,
      shadowColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      indicatorColor: scheme.primary,
      indicatorShape: MemRadius.stadium,
      labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      overlayColor: memPressOverlay(scheme),
      labelTextStyle: WidgetStateProperty.resolveWith<TextStyle?>((
        Set<WidgetState> states,
      ) {
        final TextStyle base = text.labelSmall!;
        return states.contains(WidgetState.selected)
            ? base.copyWith(color: scheme.onSurface)
            : base.copyWith(color: scheme.onSurfaceVariant);
      }),
      iconTheme: WidgetStateProperty.resolveWith<IconThemeData?>((
        Set<WidgetState> states,
      ) {
        return IconThemeData(
          size: 24,
          color: states.contains(WidgetState.selected)
              ? scheme.onPrimary
              : scheme.onSurfaceVariant,
        );
      }),
    ),

    // Owns OutlineInputBorder for the whole app.
    inputDecorationTheme: InputDecorationThemeData(
      filled: true,
      fillColor: scheme.surfaceContainer,
      isDense: false,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      border: inputBorder(scheme.outline, hairline),
      enabledBorder: inputBorder(scheme.outline, hairline),
      focusedBorder: inputBorder(scheme.primary, 2),
      errorBorder: inputBorder(scheme.error, hairline),
      focusedErrorBorder: inputBorder(scheme.error, 2),
      disabledBorder: inputBorder(scheme.outlineVariant, hairline),
      hintStyle: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
      labelStyle: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
      floatingLabelStyle: text.labelMedium?.copyWith(color: scheme.primary),
      helperStyle: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
      errorStyle: text.bodySmall?.copyWith(color: scheme.error),
      prefixIconColor: scheme.onSurfaceVariant,
      suffixIconColor: scheme.onSurfaceVariant,
    ),

    // Selection resolves to primary/onPrimary — never tertiary.
    chipTheme: ChipThemeData(
      backgroundColor: scheme.surfaceContainer,
      selectedColor: scheme.primary,
      secondarySelectedColor: scheme.primary,
      disabledColor: scheme.surfaceContainer,
      surfaceTintColor: Colors.transparent,
      shadowColor: Colors.transparent,
      selectedShadowColor: Colors.transparent,
      elevation: 0,
      pressElevation: 0,
      showCheckmark: true,
      checkmarkColor: scheme.onPrimary,
      side: BorderSide(color: scheme.outline, width: hairline),
      shape: const RoundedRectangleBorder(borderRadius: MemRadius.controlAll),
      labelStyle: text.labelMedium!.copyWith(color: scheme.onSurface),
      secondaryLabelStyle: text.labelMedium!.copyWith(color: scheme.onPrimary),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      iconTheme: IconThemeData(color: scheme.onSurfaceVariant, size: 18),
    ),

    filledButtonTheme: FilledButtonThemeData(
      style: _buttonStyle(
        scheme: scheme,
        text: text,
        // An opaque surface overlay would erase the fill, so a filled button
        // flashes with its own onPrimary ink instead.
        overlay: WidgetStateProperty.resolveWith<Color?>((states) {
          if (states.contains(WidgetState.pressed) ||
              states.contains(WidgetState.focused)) {
            return scheme.onPrimary.withValues(alpha: 0.14);
          }
          return null;
        }),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: _buttonStyle(
        scheme: scheme,
        text: text,
        overlay: memPressOverlay(scheme),
      ).copyWith(
        side: WidgetStatePropertyAll<BorderSide>(
          BorderSide(color: scheme.outline, width: hairline),
        ),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: _buttonStyle(
        scheme: scheme,
        text: text,
        overlay: memPressOverlay(scheme),
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: _buttonStyle(
        scheme: scheme,
        text: text,
        overlay: memPressOverlay(scheme),
      ),
    ),

    iconButtonTheme: IconButtonThemeData(
      style: ButtonStyle(
        minimumSize: const WidgetStatePropertyAll<Size>(
          Size(MemSize.touchTarget, MemSize.touchTarget),
        ),
        shape: const WidgetStatePropertyAll<OutlinedBorder>(MemRadius.stadium),
        overlayColor: memPressOverlay(scheme),
        elevation: const WidgetStatePropertyAll<double>(0),
        animationDuration: MemMotion.press,
        tapTargetSize: MaterialTapTargetSize.padded,
      ),
    ),

    dialogTheme: DialogThemeData(
      backgroundColor: scheme.surfaceContainerHighest,
      surfaceTintColor: Colors.transparent,
      shadowColor: Colors.transparent,
      elevation: 0,
      barrierColor: scheme.scrim.withValues(alpha: kMemScrimOpacity),
      shape: const RoundedRectangleBorder(borderRadius: MemRadius.dialogAll),
      titleTextStyle: text.titleMedium,
      contentTextStyle: text.bodyMedium,
    ),

    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: scheme.surfaceContainerHighest,
      modalBackgroundColor: scheme.surfaceContainerHighest,
      surfaceTintColor: Colors.transparent,
      shadowColor: Colors.transparent,
      elevation: 0,
      modalElevation: 0,
      modalBarrierColor: scheme.scrim.withValues(alpha: kMemScrimOpacity),
      showDragHandle: true,
      dragHandleColor: scheme.outline,
      shape: const RoundedRectangleBorder(borderRadius: MemRadius.sheetTop),
    ),

    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: scheme.inverseSurface,
      contentTextStyle: text.bodyMedium?.copyWith(
        color: scheme.onInverseSurface,
      ),
      actionTextColor: scheme.inversePrimary,
      closeIconColor: scheme.onInverseSurface,
      elevation: 0,
      shape: const RoundedRectangleBorder(borderRadius: MemRadius.controlAll),
    ),

    // Retired in favour of AppListSection/AppRow. Kept sane for any stray Card.
    cardTheme: CardThemeData(
      color: scheme.surfaceContainerLow,
      surfaceTintColor: Colors.transparent,
      shadowColor: Colors.transparent,
      elevation: 0,
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: MemRadius.sectionAll,
        side: BorderSide(color: scheme.outline, width: hairline),
      ),
    ),

    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        backgroundColor: WidgetStateProperty.resolveWith<Color?>((states) {
          return states.contains(WidgetState.selected)
              ? scheme.primary
              : scheme.surfaceContainer;
        }),
        foregroundColor: WidgetStateProperty.resolveWith<Color?>((states) {
          return states.contains(WidgetState.selected)
              ? scheme.onPrimary
              : scheme.onSurfaceVariant;
        }),
        overlayColor: memPressOverlay(scheme),
        side: WidgetStatePropertyAll<BorderSide>(
          BorderSide(color: scheme.outline, width: hairline),
        ),
        shape: const WidgetStatePropertyAll<OutlinedBorder>(
          RoundedRectangleBorder(borderRadius: MemRadius.controlAll),
        ),
        textStyle: WidgetStatePropertyAll<TextStyle?>(text.labelLarge),
        minimumSize: const WidgetStatePropertyAll<Size>(
          Size(0, MemSize.touchTarget),
        ),
        animationDuration: MemMotion.press,
      ),
    ),

    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith<Color?>((states) {
        if (states.contains(WidgetState.selected)) return scheme.onPrimary;
        return scheme.onSurfaceVariant;
      }),
      trackColor: WidgetStateProperty.resolveWith<Color?>((states) {
        if (states.contains(WidgetState.selected)) return scheme.primary;
        return scheme.surfaceContainer;
      }),
      trackOutlineColor: WidgetStateProperty.resolveWith<Color?>((states) {
        return states.contains(WidgetState.selected)
            ? scheme.primary
            : scheme.outline;
      }),
      overlayColor: memPressOverlay(scheme),
    ),

    radioTheme: RadioThemeData(
      fillColor: WidgetStateProperty.resolveWith<Color?>((states) {
        return states.contains(WidgetState.selected)
            ? scheme.primary
            : scheme.onSurfaceVariant;
      }),
      overlayColor: memPressOverlay(scheme),
    ),

    checkboxTheme: CheckboxThemeData(
      fillColor: WidgetStateProperty.resolveWith<Color?>((states) {
        return states.contains(WidgetState.selected)
            ? scheme.primary
            : Colors.transparent;
      }),
      checkColor: WidgetStatePropertyAll<Color>(scheme.onPrimary),
      side: BorderSide(color: scheme.outline, width: hairline),
      shape: const RoundedRectangleBorder(borderRadius: MemRadius.tagAll),
      overlayColor: memPressOverlay(scheme),
    ),

    sliderTheme: SliderThemeData(
      activeTrackColor: scheme.primary,
      inactiveTrackColor: scheme.surfaceContainerHigh,
      thumbColor: scheme.primary,
      overlayColor: scheme.primary.withValues(alpha: kMemFocusRingOpacity),
    ),

    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: scheme.primary,
      linearTrackColor: scheme.surfaceContainerHigh,
      circularTrackColor: Colors.transparent,
    ),

    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: scheme.primaryContainer,
      foregroundColor: scheme.onPrimaryContainer,
      elevation: 0,
      focusElevation: 0,
      hoverElevation: 0,
      highlightElevation: 0,
      disabledElevation: 0,
      splashColor: Colors.transparent,
      extendedTextStyle: text.labelLarge,
      shape: const RoundedRectangleBorder(borderRadius: MemRadius.fabAll),
    ),

    listTileTheme: ListTileThemeData(
      tileColor: Colors.transparent,
      selectedTileColor: scheme.surfaceContainerHigh,
      iconColor: scheme.onSurfaceVariant,
      textColor: scheme.onSurface,
      titleTextStyle: text.titleMedium,
      subtitleTextStyle: text.bodyMedium?.copyWith(
        color: scheme.onSurfaceVariant,
      ),
      minVerticalPadding: 12,
      shape: const RoundedRectangleBorder(borderRadius: MemRadius.sectionAll),
    ),

    // Capture's advanced-config disclosure. No stray dividers, no tint.
    expansionTileTheme: ExpansionTileThemeData(
      backgroundColor: Colors.transparent,
      collapsedBackgroundColor: Colors.transparent,
      iconColor: scheme.onSurfaceVariant,
      collapsedIconColor: scheme.onSurfaceVariant,
      textColor: scheme.onSurface,
      collapsedTextColor: scheme.onSurface,
      shape: const Border(),
      collapsedShape: const Border(),
    ),

    popupMenuTheme: PopupMenuThemeData(
      color: scheme.surfaceContainerHighest,
      surfaceTintColor: Colors.transparent,
      shadowColor: Colors.transparent,
      elevation: 0,
      textStyle: text.bodyMedium,
      shape: RoundedRectangleBorder(
        borderRadius: MemRadius.sectionAll,
        side: BorderSide(color: scheme.outline, width: hairline),
      ),
    ),

    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color: scheme.inverseSurface,
        borderRadius: MemRadius.tagAll,
      ),
      textStyle: text.bodySmall?.copyWith(color: scheme.onInverseSurface),
    ),

    textSelectionTheme: TextSelectionThemeData(
      cursorColor: scheme.primary,
      selectionColor: scheme.primary.withValues(alpha: 0.35),
      selectionHandleColor: scheme.primary,
    ),
  );
}

/// Shared button geometry: radius 10, >=48 dp tall, `labelLarge`, zero
/// elevation, and the 80 ms press animation.
ButtonStyle _buttonStyle({
  required ColorScheme scheme,
  required TextTheme text,
  required WidgetStateProperty<Color?> overlay,
}) {
  return ButtonStyle(
    minimumSize: const WidgetStatePropertyAll<Size>(
      Size(64, MemSize.touchTarget),
    ),
    padding: const WidgetStatePropertyAll<EdgeInsetsGeometry>(
      EdgeInsets.symmetric(horizontal: 16),
    ),
    shape: const WidgetStatePropertyAll<OutlinedBorder>(
      RoundedRectangleBorder(borderRadius: MemRadius.controlAll),
    ),
    textStyle: WidgetStatePropertyAll<TextStyle?>(text.labelLarge),
    elevation: const WidgetStatePropertyAll<double>(0),
    shadowColor: const WidgetStatePropertyAll<Color>(Colors.transparent),
    surfaceTintColor: const WidgetStatePropertyAll<Color>(Colors.transparent),
    overlayColor: overlay,
    animationDuration: MemMotion.press,
    tapTargetSize: MaterialTapTargetSize.padded,
  );
}

/// The dark theme — the product default.
final ThemeData memDarkTheme = buildMemTheme(Brightness.dark);

/// The light theme — fully first-class, identical depth grammar.
final ThemeData memLightTheme = buildMemTheme(Brightness.light);
