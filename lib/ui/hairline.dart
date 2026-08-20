import 'package:flutter/material.dart';

import '../theme/mem_metrics.dart';

/// [hairlineWidth] is a metric token and lives with the other metrics; it is
/// re-exported here so a widget file can pull the whole hairline vocabulary
/// from one import. It is **never** redefined — one implementation, one place.
export '../theme/mem_metrics.dart' show hairlineWidth;

/// A 1 dp rule, snapped to whole physical pixels (§2.7).
///
/// **Two hairline tokens, two jobs.** This distinction is load-bearing on a
/// true-black canvas and the widget does not choose for you:
///
/// * `colorScheme.outlineVariant` — the **divider** (the default here). Row
///   dividers *inside* an already-bounded section, and nothing else.
/// * `colorScheme.outline` — the **boundary**. Any container that must be
///   identified as a distinct interactive surface. A boundary is normally a
///   `Border` on the container itself; pass `color: colorScheme.outline` when
///   it genuinely is a free-standing rule (the NavigationBar top edge, a
///   sticky action bar's top edge).
///
/// Thickness always comes from [hairlineWidth] so the line can neither vanish
/// on mdpi nor fatten on a fractional device pixel ratio.
class Hairline extends StatelessWidget {
  const Hairline({super.key, this.color, this.indent = 0, this.endIndent = 0})
    : axis = Axis.horizontal;

  /// A vertical rule — chip-strip separators, split action bars.
  const Hairline.vertical({
    super.key,
    this.color,
    this.indent = 0,
    this.endIndent = 0,
  }) : axis = Axis.vertical;

  final Axis axis;

  /// Defaults to `colorScheme.outlineVariant` — the divider token.
  final Color? color;

  /// Inset from the leading edge (left for a horizontal rule, top for a
  /// vertical one). Section row dividers use [MemSpace.dividerIndent].
  final double indent;

  /// Inset from the trailing edge.
  final double endIndent;

  @override
  Widget build(BuildContext context) {
    final double width = hairlineWidth(context);
    final Color ink = color ?? Theme.of(context).colorScheme.outlineVariant;
    if (axis == Axis.horizontal) {
      return SizedBox(
        height: width,
        child: Padding(
          padding: EdgeInsets.only(left: indent, right: endIndent),
          child: ColoredBox(color: ink),
        ),
      );
    }
    return SizedBox(
      width: width,
      child: Padding(
        padding: EdgeInsets.only(top: indent, bottom: endIndent),
        child: ColoredBox(color: ink),
      ),
    );
  }
}
