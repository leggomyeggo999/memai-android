import 'package:flutter/material.dart';

/// The one inline progress token (§3.10).
///
/// Sizes: **16** inside buttons and status pills, **24** in list footers.
/// Anything bigger is a screen-level loading state and belongs in a skeleton
/// (§3.11) — a spinner never replaces content that already exists.
///
/// `CircularProgressIndicator` is banned everywhere else in `lib/` (the only
/// other permitted host is `RefreshIndicator`), so every inline spinner routes
/// through here. This replaces the five hardcoded 18/20 dp variants.
class InlineSpinner extends StatelessWidget {
  const InlineSpinner({super.key, this.size = 16, this.color});

  /// Diameter in logical pixels. 16 in buttons/pills, 24 in list footers.
  final double size;

  /// Defaults to the surrounding foreground colour, so a spinner dropped into
  /// a `FilledButton` picks up `onPrimary` without being told.
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final Color fg =
        color ??
        IconTheme.of(context).color ??
        DefaultTextStyle.of(context).style.color ??
        Theme.of(context).colorScheme.onSurface;
    return SizedBox(
      width: size,
      height: size,
      child: CircularProgressIndicator(strokeWidth: 2, color: fg),
    );
  }
}
