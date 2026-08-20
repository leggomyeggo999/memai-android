import 'package:flutter/material.dart';

import '../theme/mem_metrics.dart';
import '../theme/mem_semantic_colors.dart';
import 'inline_spinner.dart';

/// What a [StatusTile]'s pill is saying.
///
/// [ok]/[pending]/[attention] resolve to the `success`/`pending`/`warning`
/// semantic tokens, [error] to `colorScheme.error`, and [neutral] to
/// `onSurfaceVariant` on `surfaceContainer`.
enum StatusLevel { ok, pending, attention, error, neutral }

/// The replacement for every disabled-buttons-as-status pattern.
///
/// State is stated, not implied: a labelled row, a dot in the level colour, the
/// status in words, and **exactly one** action button. While [busy] the pill
/// shows an [InlineSpinner] beside the pending copy and the action is disabled
/// — that is what closes the OAuth browser-round-trip dead-air gap.
///
/// `success` / `warning` / `pending` may appear **only** as the 8 dp dot or as
/// this pill's text and container. They are never a button, row, or chip fill.
class StatusTile extends StatelessWidget {
  const StatusTile({
    super.key,
    required this.icon,
    required this.label,
    required this.level,
    required this.status,
    this.detail,
    this.actionLabel,
    this.onAction,
    this.busy = false,
    this.onTap,
  });

  /// Leading 20 dp glyph.
  final IconData icon;

  /// `titleSmall`.
  final String label;

  final StatusLevel level;

  /// E.g. `Connected`, `Key saved · ····4F2`, `Not set`.
  final String status;

  /// Optional `bodySmall` second line.
  final String? detail;

  final String? actionLabel;
  final VoidCallback? onAction;

  /// Shows an [InlineSpinner] in the pill AND disables the action.
  final bool busy;

  /// Optional whole-tile tap (used by the setup card).
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final TextTheme text = theme.textTheme;
    final MemSemanticColors sem = memSemanticColorsOf(context);

    final (Color dot, Color pillBg, Color pillFg) = switch (level) {
      StatusLevel.ok => (
        sem.success,
        sem.successContainer,
        sem.onSuccessContainer,
      ),
      StatusLevel.pending => (
        sem.pending,
        sem.pendingContainer,
        sem.onPendingContainer,
      ),
      StatusLevel.attention => (
        sem.warning,
        sem.warningContainer,
        sem.onWarningContainer,
      ),
      StatusLevel.error => (
        scheme.error,
        scheme.errorContainer,
        scheme.onErrorContainer,
      ),
      StatusLevel.neutral => (
        scheme.onSurfaceVariant,
        scheme.surfaceContainer,
        scheme.onSurfaceVariant,
      ),
    };

    final Widget pill = Container(
      constraints: const BoxConstraints(maxWidth: 200),
      padding: const EdgeInsets.symmetric(
        horizontal: MemSpace.x2 + 2,
        vertical: MemSpace.x1 + 2,
      ),
      decoration: BoxDecoration(
        color: pillBg,
        borderRadius: MemRadius.controlAll,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (busy)
            InlineSpinner(color: pillFg)
          else
            Container(
              width: MemSize.statusDot,
              height: MemSize.statusDot,
              decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
            ),
          const SizedBox(width: MemSpace.x2),
          Flexible(
            child: Text(
              status,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: text.labelMedium?.copyWith(color: pillFg),
            ),
          ),
        ],
      ),
    );

    final bool hasAction = actionLabel != null && onAction != null;

    Widget content = Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: MemSpace.x4,
        vertical: MemSpace.sectionPadV,
      ),
      child: Row(
        children: <Widget>[
          Icon(icon, size: 20, color: scheme.onSurfaceVariant),
          const SizedBox(width: MemSpace.x3),
          Expanded(
            flex: 3,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: text.titleSmall?.copyWith(color: scheme.onSurface),
                ),
                if (detail != null) ...<Widget>[
                  const SizedBox(height: 2),
                  Text(
                    detail!,
                    style: text.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: MemSpace.x2),
          // Loose flex: the pill takes its natural width, but can never crowd
          // the label off the row on a narrow screen.
          Flexible(flex: 2, child: pill),
          // Exactly one trailing action button.
          if (hasAction) ...<Widget>[
            const SizedBox(width: MemSpace.x1),
            TextButton(
              onPressed: busy ? null : onAction,
              child: Text(actionLabel!),
            ),
          ],
        ],
      ),
    );

    if (onTap != null) {
      content = Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onTap,
          overlayColor: memPressOverlay(scheme),
          child: content,
        ),
      );
    }

    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: MemSize.rowSettings),
      child: content,
    );
  }
}

/// Renders a secret as `····4F2` — the last three characters only.
///
/// **A full key is never rendered.** Callers compose the surrounding copy, e.g.
/// `'Key saved · ${memMaskedSecret(key)}'`.
String memMaskedSecret(String secret) {
  const String mask = '····';
  if (secret.isEmpty) return mask;
  final String tail = secret.length <= 3
      ? secret
      : secret.substring(secret.length - 3);
  return '$mask$tail';
}
