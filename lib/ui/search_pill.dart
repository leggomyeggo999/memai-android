import 'package:flutter/material.dart';

import '../theme/mem_metrics.dart';

/// The search affordance: a 44 dp stadium pill on `surfaceContainer` with a
/// 1 dp `outline` boundary and a leading 20 dp search glyph.
///
/// Collapsed ([active] false) it is a tap target that teaches search exists and
/// costs nothing; tapping calls [onTap], and the owner flips [active] to expand
/// it into a live text field with a trailing clear **X** and a `Cancel` text
/// button beside the pill.
///
/// The pill deliberately does **not** declare an `OutlineInputBorder` — the
/// global `InputDecorationTheme` owns field borders, and this control draws its
/// own stadium boundary, so the inner field is borderless.
class SearchPill extends StatelessWidget {
  const SearchPill({
    super.key,
    required this.hint,
    required this.onTap,
    this.focusNode,
    this.controller,
    this.onChanged,
    this.onClear,
    this.onCancel,
    this.active = false,
  });

  /// `bodyMedium` placeholder, e.g. `Search notes`.
  final String hint;

  /// Tapping the collapsed pill. The owner uses it to enter search mode.
  final VoidCallback onTap;

  final FocusNode? focusNode;
  final TextEditingController? controller;
  final ValueChanged<String>? onChanged;

  /// The trailing **X**: empties the query but stays in search mode.
  final VoidCallback? onClear;

  /// The `Cancel` button: leaves search mode entirely. Falls back to [onClear]
  /// when null, so a caller that treats the two as one action still works.
  final VoidCallback? onCancel;

  final bool active;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final TextStyle? hintStyle = theme.textTheme.bodyMedium?.copyWith(
      color: scheme.onSurfaceVariant,
    );

    // The clear X tracks the controller directly, so it appears and disappears
    // without the owner having to rebuild the pill on every keystroke.
    final Widget clearSlot = (active && controller != null)
        ? ValueListenableBuilder<TextEditingValue>(
            valueListenable: controller!,
            builder: (BuildContext context, TextEditingValue value, _) {
              if (value.text.isEmpty) {
                return const SizedBox(width: MemSpace.x2);
              }
              return IconButton(
                iconSize: 20,
                padding: EdgeInsets.zero,
                // 48 dp wide; 44 dp tall is the pill's own height, and the pill
                // sits inside a 48 dp target box.
                constraints: const BoxConstraints(
                  minWidth: MemSize.touchTarget,
                  minHeight: 44,
                ),
                tooltip: 'Clear',
                icon: const Icon(Icons.close),
                onPressed: onClear,
              );
            },
          )
        : const SizedBox(width: MemSpace.x2);

    final Widget pill = Container(
      height: 44,
      padding: const EdgeInsetsDirectional.only(
        start: MemSpace.x3,
        end: MemSpace.x1,
      ),
      decoration: ShapeDecoration(
        color: scheme.surfaceContainer,
        shape: StadiumBorder(
          side: BorderSide(
            color: scheme.outline,
            width: hairlineWidth(context),
          ),
        ),
      ),
      child: Row(
        children: <Widget>[
          Icon(Icons.search, size: 20, color: scheme.onSurfaceVariant),
          const SizedBox(width: MemSpace.x2),
          Expanded(
            child: active
                ? TextField(
                    controller: controller,
                    focusNode: focusNode,
                    onChanged: onChanged,
                    textInputAction: TextInputAction.search,
                    style: theme.textTheme.bodyMedium,
                    decoration: InputDecoration(
                      isCollapsed: true,
                      filled: false,
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      contentPadding: EdgeInsets.zero,
                      hintText: hint,
                      hintStyle: hintStyle,
                    ),
                  )
                : Text(
                    hint,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: hintStyle,
                  ),
          ),
          clearSlot,
        ],
      ),
    );

    // 44 dp visual, 48 dp target.
    final Widget target = SizedBox(
      height: MemSize.touchTarget,
      child: Center(
        child: active
            ? pill
            : Material(
                type: MaterialType.transparency,
                child: InkWell(
                  onTap: onTap,
                  customBorder: MemRadius.stadium,
                  overlayColor: memPressOverlay(scheme),
                  child: pill,
                ),
              ),
      ),
    );

    if (!active) {
      return Semantics(button: true, label: hint, child: target);
    }

    return Row(
      children: <Widget>[
        Expanded(child: target),
        const SizedBox(width: MemSpace.x1),
        TextButton(
          onPressed: onCancel ?? onClear,
          child: const Text('Cancel'),
        ),
      ],
    );
  }
}
