import 'package:flutter/material.dart';

import '../theme/mem_metrics.dart';

/// A section eyebrow (§3.8).
///
/// `labelSmall` UPPERCASE `onSurfaceVariant`, 24 dp above and 8 dp below, with
/// an optional trailing text button. Replaces the ~10 hand-rolled
/// `titleMedium` + prose-paragraph pairs; **the prose paragraphs are deleted**
/// — anything worth keeping becomes field helper text.
///
/// `uppercase: false` switches to `labelMedium` **sentence case**, which is the
/// register the date group headers use (§2.4). ALL-CAPS is reserved for
/// structural eyebrows (`ACCOUNT`, `CHAT MODELS`, `PINNED · 2/4`) — it is the
/// named problem in `#15` everywhere else.
class SectionHeader extends StatelessWidget {
  const SectionHeader({
    super.key,
    required this.label,
    this.trailing,
    this.uppercase = true,
    this.padding = const EdgeInsets.fromLTRB(
      MemInsets.pageH,
      MemSpace.sectionGap,
      MemInsets.pageH,
      MemSpace.headerGap,
    ),
  });

  final String label;

  /// One trailing control — a `TextButton`, never a second primary action.
  final Widget? trailing;

  final bool uppercase;

  /// Defaults to the page inset horizontally so a bare header in a `ListView`
  /// lines up with the sections under it. Pass a horizontally-zero inset when
  /// the caller already supplies the margin (e.g. `AppListSection.header`).
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final TextStyle? style = (uppercase
            ? theme.textTheme.labelSmall
            : theme.textTheme.labelMedium)
        ?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    return Padding(
      padding: padding,
      child: Row(
        children: <Widget>[
          Expanded(
            child: Semantics(
              header: true,
              child: Text(
                uppercase ? label.toUpperCase() : label,
                style: style,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}
