import 'package:flutter/material.dart';

import '../theme/mem_metrics.dart';
import 'error_state.dart';
import 'inline_spinner.dart';

/// The handle a sheet's fields get, so they can re-evaluate validity, close the
/// sheet at the right moment, and reach the **page's** messenger after the
/// sheet is gone.
abstract class EditorSheetState {
  /// True from the moment `onSave` is entered until it settles.
  bool get saving;

  /// Rebuilds the sheet — call it from every `onChanged` so the Save button's
  /// `isValid()` gate is re-read.
  void refresh();

  /// Pops the sheet via its own `sheetContext`.
  ///
  /// The save ordering contract is: do the write, `close()`, then `await` the
  /// page-side reload. Calling it is a no-op once the sheet is gone.
  void close([Object? result]);

  /// The `ScaffoldMessenger` captured from the **page** before the sheet was
  /// ever built, so a snackbar still lands after [close].
  ScaffoldMessengerState get messenger;
}

/// The one modal editor scaffold — Collections editor, Prompt-job editor,
/// chat-model editor, secret-key editors, jobs picker.
///
/// **Contracts baked in (do not deviate):**
/// * `isScrollControlled: true` and bottom padding
///   `MediaQuery.viewInsetsOf(context).bottom + 20`, so the keyboard never
///   covers the fields or the Save button.
/// * **Save is disabled until [isValid] returns true** — this replaces every
///   silent no-op on empty input.
/// * **Save ordering:** the page's [ScaffoldMessenger] is captured *before*
///   anything async (here, before `showModalBottomSheet` is even called), then
///   [onSave] runs. [onSave] receives the `sheetContext` precisely so it can
///   pop the sheet between its write and the page-side reload — see
///   [EditorSheetState.close].
/// * **On error the sheet stays open and the message shows.** If [onSave]
///   throws before it closed the sheet, the sheet is still there with the
///   user's input intact.
/// * Controllers are seeded from `existing` and disposed in the caller's own
///   `State` (or in a `StatefulWidget` returned from [fieldsBuilder]).
/// * Values are trimmed on save — by [onSave], which owns the payload.
///
/// Fields use the global `InputDecorationTheme`; **never** re-declare an
/// `OutlineInputBorder()` inline.
///
/// The shape [onSave] must have:
///
/// ```dart
/// onSave: (sheetContext) async {
///   await client.updateCollection(id: id, title: title.trim());
///   if (!sheetContext.mounted) return;   // mounted check after every await
///   state.close();                       // pop BEFORE the page-side reload
///   await reloadAndBumpRevision();       // page reload + notesListRevision
///   state.messenger.showSnackBar(...);   // captured before the sheet existed
/// }
/// ```
///
/// A throw from the write leaves the sheet open with the input intact; a throw
/// after [EditorSheetState.close] still reports on the page's messenger.
Future<T?> showEditorSheet<T>({
  required BuildContext context,
  required String title,
  required List<Widget> Function(BuildContext sheetContext, EditorSheetState state)
  fieldsBuilder,
  required bool Function() isValid,
  required Future<void> Function(BuildContext sheetContext) onSave,
  String saveLabel = 'Save',
  Widget? footerNote,
}) {
  // Captured BEFORE anything async, from the page — not from the sheet — so it
  // survives the sheet being popped mid-save.
  final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);

  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (BuildContext sheetContext) => _EditorSheet(
      title: title,
      fieldsBuilder: fieldsBuilder,
      isValid: isValid,
      onSave: onSave,
      saveLabel: saveLabel,
      footerNote: footerNote,
      messenger: messenger,
    ),
  );
}

class _EditorSheet extends StatefulWidget {
  const _EditorSheet({
    required this.title,
    required this.fieldsBuilder,
    required this.isValid,
    required this.onSave,
    required this.saveLabel,
    required this.footerNote,
    required this.messenger,
  });

  final String title;
  final List<Widget> Function(BuildContext, EditorSheetState) fieldsBuilder;
  final bool Function() isValid;
  final Future<void> Function(BuildContext) onSave;
  final String saveLabel;
  final Widget? footerNote;
  final ScaffoldMessengerState messenger;

  @override
  State<_EditorSheet> createState() => _EditorSheetState();
}

class _EditorSheetState extends State<_EditorSheet> implements EditorSheetState {
  bool _saving = false;

  @override
  bool get saving => _saving;

  @override
  ScaffoldMessengerState get messenger => widget.messenger;

  @override
  void refresh() {
    if (mounted) setState(() {});
  }

  @override
  void close([Object? result]) {
    if (!mounted) return;
    Navigator.of(context).pop(result);
  }

  Future<void> _save(BuildContext sheetContext) async {
    if (_saving || !widget.isValid()) return;
    setState(() => _saving = true);
    try {
      await widget.onSave(sheetContext);
    } catch (e) {
      // The sheet is still open (onSave threw before it closed): keep the
      // user's input and surface the failure on the page's messenger. No raw
      // exception text ever reaches the user — errSnack routes it.
      errSnack(widget.messenger, e);
    } finally {
      // `mounted` is false when onSave popped the sheet — nothing to reset.
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final bool canSave = !_saving && widget.isValid();

    return Padding(
      // The keyboard-avoidance contract, verbatim.
      padding: EdgeInsets.only(
        left: MemSpace.x5,
        right: MemSpace.x5,
        top: MemSpace.x2,
        bottom: MediaQuery.viewInsetsOf(context).bottom + MemSpace.x5,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  widget.title,
                  style: theme.textTheme.titleSmall,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              SizedBox(
                width: MemSize.touchTarget,
                height: MemSize.touchTarget,
                child: IconButton(
                  tooltip: 'Close',
                  icon: const Icon(Icons.close),
                  onPressed: _saving ? null : () => close(),
                ),
              ),
            ],
          ),
          const SizedBox(height: MemSpace.x3),
          Flexible(
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: widget.fieldsBuilder(context, this),
              ),
            ),
          ),
          if (widget.footerNote != null) ...<Widget>[
            const SizedBox(height: MemSpace.x3),
            DefaultTextStyle.merge(
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
              child: widget.footerNote!,
            ),
          ],
          const SizedBox(height: MemSpace.x4),
          // Sticky footer: the save button never scrolls away.
          SizedBox(
            height: MemSize.touchTarget,
            child: FilledButton(
              onPressed: canSave ? () => _save(context) : null,
              child: _saving
                  ? InlineSpinner(color: scheme.onPrimary)
                  : Text(widget.saveLabel),
            ),
          ),
        ],
      ),
    );
  }
}
