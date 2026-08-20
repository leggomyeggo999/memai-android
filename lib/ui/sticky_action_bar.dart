import 'package:flutter/material.dart';

import '../theme/mem_metrics.dart';

/// The bottom-docked action bar that keeps a screen's CTAs reachable.
///
/// `surfaceContainerLowest` with a 1 dp `outline` top hairline and 12 dp of
/// vertical padding — 72 dp of chrome ([MemInsets.stickyBarHeight]) before the
/// safe area. It animates above the keyboard by padding with
/// `MediaQuery.viewInsetsOf(context).bottom`, so it is visible above both the
/// NavigationBar and the IME.
///
/// [primary] takes `flex: 2` and [secondary] `flex: 1`; both are 48 dp tall.
/// The secondary sits on the left, leaving the promoted action in the reflex
/// position on the right — the same grammar as `confirmDestructive`.
class StickyActionBar extends StatelessWidget {
  const StickyActionBar({
    super.key,
    required this.primary,
    this.secondary,
    this.caption,
  });

  /// Usually a `FilledButton`.
  final Widget primary;

  /// Usually an `OutlinedButton` or `TextButton`.
  final Widget? secondary;

  /// One `bodySmall` line rendered ABOVE the buttons.
  final String? caption;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;

    return AnimatedPadding(
      duration: MemMotion.micro,
      curve: MemMotion.emphasized,
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: scheme.surfaceContainerLowest,
          border: Border(
            top: BorderSide(
              color: scheme.outline,
              width: hairlineWidth(context),
            ),
          ),
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: MemInsets.pageH,
              vertical: MemSpace.sectionPadV,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                if (caption != null) ...<Widget>[
                  Text(
                    caption!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: MemSpace.x2),
                ],
                // Both buttons inherit the theme's 48 dp minimum and grow with
                // the text scale, so no fixed height is imposed here.
                Row(
                  children: <Widget>[
                    if (secondary != null) ...<Widget>[
                      Expanded(flex: 1, child: secondary!),
                      const SizedBox(width: MemSpace.x3),
                    ],
                    Expanded(flex: 2, child: primary),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
