import 'package:flutter/material.dart';

import '../theme/mem_metrics.dart';

/// The one destructive confirmation (§3.7).
///
/// **The grammar is inverted from the old code and must be identical at all
/// six call sites** (trash note, delete forever, delete collection, remove
/// model, disconnect MCP, discard recording / discard changes):
///
/// * **Cancel is promoted** — `FilledButton.tonal`, on the right, where the
///   reflex tap lands.
/// * **The destructive action is demoted** — a `TextButton` in
///   `colorScheme.error`, on the left, still a full 48 dp target and still
///   `labelLarge` w600 so it is findable rather than hidden.
/// * An outside tap resolves `false`.
///
/// Returns `false` for every non-confirmation (outside tap, back button,
/// dismissed route), so call sites read `if (ok == true && mounted)` — the
/// `mounted` half is the caller's, because the dialog awaited across a frame.
///
/// Chrome comes from `dialogTheme`: radius 16, `surfaceContainerHighest`, and
/// a 60 % scrim. Nothing here overrides it.
Future<bool> confirmDestructive(
  BuildContext context, {
  required String title,
  required String consequence,
  required String actionLabel,
  String cancelLabel = 'Cancel',
}) async {
  final ColorScheme cs = Theme.of(context).colorScheme;
  final bool? ok = await showDialog<bool>(
    context: context,
    // Outside tap → null → false.
    barrierDismissible: true,
    builder: (BuildContext dialogContext) {
      return AlertDialog(
        title: Text(title),
        content: Text(consequence),
        // `actions` are laid out start-to-end and aligned to the end, so the
        // destructive verb sits on the left and Cancel takes the right.
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: TextButton.styleFrom(
              foregroundColor: cs.error,
              minimumSize: const Size(64, MemSize.touchTarget),
            ),
            child: Text(actionLabel),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(cancelLabel),
          ),
        ],
      );
    },
  );
  return ok ?? false;
}
