import 'package:flutter/material.dart';

/// Metric tokens: radii, spacing, sizing, chrome insets, hairlines, motion.
///
/// One scale, one place. The historical 14-vs-16 radius clash and the magic
/// `120` / `96` / `12` bottom insets are gone — read them from here.

/// Radius scale. One scale for the whole app.
///
/// * [tag] 6 — inline code, collection tags, small badges
/// * [control] 10 — buttons, chips, status pills, segmented buttons
/// * [section] 12 — list sections, input fields, cards
/// * [dialog] 16 — dialogs
/// * [sheet] 20 — bottom-sheet top corners
/// * [fab] 28 — standard FAB (M3)
///
/// Search pill, extended FAB, mic button, NavigationBar indicator, and
/// circular icon buttons use [stadium] instead.
abstract final class MemRadius {
  static const double tag = 6;
  static const double control = 10;
  static const double section = 12;
  static const double dialog = 16;
  static const double sheet = 20;
  static const double fab = 28;

  static const BorderRadius tagAll = BorderRadius.all(Radius.circular(tag));
  static const BorderRadius controlAll = BorderRadius.all(
    Radius.circular(control),
  );
  static const BorderRadius sectionAll = BorderRadius.all(
    Radius.circular(section),
  );
  static const BorderRadius dialogAll = BorderRadius.all(
    Radius.circular(dialog),
  );
  static const BorderRadius fabAll = BorderRadius.all(Radius.circular(fab));

  /// Bottom sheets round only their top corners.
  static const BorderRadius sheetTop = BorderRadius.vertical(
    top: Radius.circular(sheet),
  );

  static const StadiumBorder stadium = StadiumBorder();
}

/// Spacing. Base grid is 4 dp — [x1] through [x6] are the grid steps; the
/// named values below them are the ones the spec fixes.
abstract final class MemSpace {
  static const double x1 = 4;
  static const double x2 = 8;
  static const double x3 = 12;
  static const double x4 = 16;
  static const double x5 = 20;
  static const double x6 = 24;

  /// Section internal padding: 14 horizontal / 12 vertical.
  static const double sectionPadH = 14;
  static const double sectionPadV = 12;

  /// Gap between two sections.
  static const double sectionGap = 24;

  /// Gap from a section header down to its section.
  static const double headerGap = 8;

  /// Gap between two chips in a strip.
  static const double chipGap = 8;

  /// Row dividers inside a bounded section are inset this far from the left.
  static const double dividerIndent = 16;

  static const EdgeInsets pageHorizontal = EdgeInsets.symmetric(
    horizontal: MemInsets.pageH,
  );
  static const EdgeInsets sectionPadding = EdgeInsets.symmetric(
    horizontal: sectionPadH,
    vertical: sectionPadV,
  );
}

/// Fixed sizes. Every interactive element gets a >=48 dp touch target — visual
/// size may be smaller, pad it out.
abstract final class MemSize {
  /// Minimum touch target, app-wide.
  static const double touchTarget = 48;

  /// Settings / status rows.
  static const double rowSettings = 56;

  /// Single-line list rows.
  static const double rowSingleLine = 64;

  /// Note rows — fixed, and the density claim rests on it.
  static const double rowNote = 76;

  /// Chip strips are exactly this tall (48 dp targets + 4 dp above/below).
  static const double chipStrip = 56;

  /// Status dot. `success` / `warning` / `pending` may appear at this size and
  /// as status-pill text, and nowhere else.
  static const double statusDot = 8;

  /// The 16 dp check glyph that marks every selected affordance.
  static const double selectionCheck = 16;

  /// NavigationBar selection indicator, 64 x 32 stadium.
  static const double navIndicatorWidth = 64;
  static const double navIndicatorHeight = 32;

  /// Hold-to-talk mic button.
  static const double micButton = 96;

  /// Scroll-hint gradient width on an overflowing horizontal strip.
  static const double scrollHint = 16;
}

/// Chrome insets — the single source of truth for bottom clearance.
///
/// **Bottom-stack budget (verified, must not regress):** Notes = 104 only (the
/// nav bar is the sole chrome). Capture = sticky bar 72 + nav 64 = 136, and the
/// content field is the flexible child so it shrinks rather than pushing the
/// CTAs off-screen. Collections / Prompt Jobs are pushed routes with no nav
/// bar: FAB inset 96 only. NoteDetail edit = sticky bar 72 + keyboard.
/// **No screen composes more than 140 dp of bottom chrome.**
abstract final class MemInsets {
  static const double navBarHeight = 64;
  static const double listBottomForNav = 104; // 64 nav + 40 breathing room
  static const double listBottomForFab = 96; // 56 dp FAB + 16 margin + 24
  static const double stickyBarHeight = 72;
  static const double pageH = 16;
  static const double editorScrollPad = 140; // scrollPadding on tall fields
}

/// Motion. Durations and curves for the whole app.
///
/// **The 80 ms press is the signature.** Globally the theme sets
/// `splashFactory: NoSplash.splashFactory`; every tappable surface sets
/// `overlayColor` to `surfaceContainerHigh` when pressed, resolved in [press].
/// No 300 ms ripple spread anywhere.
abstract final class MemMotion {
  static const Duration press = Duration(milliseconds: 80);
  static const Duration micro = Duration(milliseconds: 120);
  static const Duration standard = Duration(milliseconds: 220);
  static const Duration route = Duration(milliseconds: 220);
  static const Duration skeleton = Duration(milliseconds: 1100);
  static const Duration snack = Duration(milliseconds: 2500);
  static const Duration snackAction = Duration(seconds: 4);
  static const Duration undo = Duration(seconds: 6);
  static const Duration revealTimeout = Duration(seconds: 10);
  static const Duration streamStall = Duration(seconds: 90);

  static const Curve emphasized = Curves.easeOutCubic;
  static const Curve pulse = Curves.easeInOut;
}

/// Hairline width — the mdpi fix.
///
/// Never specify a thickness below `1.0`. Snapping 1 dp to whole physical
/// pixels means the line can neither vanish (sub-pixel on mdpi) nor fatten
/// (rounded up on a fractional dpr). Use this for every `Border.all(width:)`,
/// `BorderSide(width:)`, and `Divider(thickness:)`.
double hairlineWidth(BuildContext context) {
  final double dpr = MediaQuery.devicePixelRatioOf(context);
  if (dpr <= 1.0) return 1.0;
  return (1.0 * dpr).roundToDouble() / dpr;
}

/// The 80 ms press flash, as a [WidgetStateProperty] for any widget that takes
/// an `overlayColor` (buttons, `InkWell`, `ListTile`, chips).
///
/// Pressed and focused resolve to `surfaceContainerHigh`; nothing else paints,
/// because `NoSplash` handles the rest.
WidgetStateProperty<Color?> memPressOverlay(ColorScheme scheme) {
  return WidgetStateProperty.resolveWith<Color?>((Set<WidgetState> states) {
    if (states.contains(WidgetState.pressed)) {
      return scheme.surfaceContainerHigh;
    }
    if (states.contains(WidgetState.focused)) {
      return scheme.surfaceContainerHigh;
    }
    return null;
  });
}
