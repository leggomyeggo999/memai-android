import 'dart:async';

import 'package:flutter/material.dart';

import '../theme/mem_metrics.dart';

/// Transient feedback (§3.12).
///
/// **Copy system: "Noun verb-past."** — `Note saved.` · `Collection deleted.` ·
/// `Moved to trash.` · `Captured — Mem is processing it.` Never a bare verb,
/// never an exclamation mark, never the raw text of an exception (that is
/// `errSnack`'s job, §3.6).
///
/// Both helpers hide the current snackbar first: a 6 s undo window must not
/// queue behind an earlier message, and a queued message must not appear
/// seconds after the action that caused it.

/// A plain confirmation, with an optional single action.
void memSnack(
  ScaffoldMessengerState m,
  String message, {
  String? actionLabel,
  VoidCallback? onAction,
}) {
  final bool hasAction = actionLabel != null && onAction != null;
  m.hideCurrentSnackBar();
  m.showSnackBar(
    SnackBar(
      content: Text(message),
      duration: hasAction ? MemMotion.snackAction : MemMotion.snack,
      action: hasAction
          ? SnackBarAction(label: actionLabel, onPressed: onAction)
          : null,
    ),
  );
}

/// A confirmation with a **real** undo (§5.2).
///
/// Used in exactly two places — trashing a note and clearing the capture draft
/// — and in both the undo does the actual work: `restoreNote` + reload + a
/// `notesListRevision` bump, or a restore of the *complete* draft (body,
/// guidance, collection ids, replace/append mode, language). An undo that only
/// looks like an undo is worse than no undo.
///
/// [onUndo] is fired and deliberately not awaited — `SnackBarAction.onPressed`
/// is synchronous, so the caller's future owns its own error handling (and
/// must capture its messenger before its awaits like everything else).
/// [secondaryLabel] renders inline in the content, because a `SnackBar` has
/// room for exactly one `action` and Undo owns it.
void undoSnack(
  ScaffoldMessengerState m,
  String message, {
  required Future<void> Function() onUndo,
  String? secondaryLabel,
  VoidCallback? onSecondary,
}) {
  final bool hasSecondary = secondaryLabel != null && onSecondary != null;
  m.hideCurrentSnackBar();
  m.showSnackBar(
    SnackBar(
      duration: MemMotion.undo,
      content: hasSecondary
          ? _SnackContentWithSecondary(
              message: message,
              secondaryLabel: secondaryLabel,
              onSecondary: onSecondary,
            )
          : Text(message),
      action: SnackBarAction(
        label: 'Undo',
        onPressed: () => unawaited(onUndo()),
      ),
    ),
  );
}

/// Message plus a demoted secondary verb, sized to a 48 dp target.
class _SnackContentWithSecondary extends StatelessWidget {
  const _SnackContentWithSecondary({
    required this.message,
    required this.secondaryLabel,
    required this.onSecondary,
  });

  final String message;
  final String secondaryLabel;
  final VoidCallback onSecondary;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color fg =
        theme.snackBarTheme.actionTextColor ?? theme.colorScheme.inversePrimary;
    return Row(
      children: <Widget>[
        Expanded(child: Text(message)),
        const SizedBox(width: MemSpace.x2),
        TextButton(
          onPressed: onSecondary,
          style: TextButton.styleFrom(
            foregroundColor: fg,
            minimumSize: const Size(48, MemSize.touchTarget),
            padding: const EdgeInsets.symmetric(horizontal: MemSpace.x3),
          ),
          child: Text(secondaryLabel),
        ),
      ],
    );
  }
}
