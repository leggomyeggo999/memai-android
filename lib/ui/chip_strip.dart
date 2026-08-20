import 'package:flutter/material.dart';

import '../theme/mem_metrics.dart';

/// A horizontal strip of chips with real 48 dp touch targets.
///
/// **Visual.** Exactly [MemSize.chipStrip] (56 dp) tall — 48 dp targets plus
/// 4 dp above and below — sitting on `surface`. The old tinted
/// `surfaceContainerHighest @ 35 %` band is retired: the strip is not a
/// separate surface, it is content on the canvas.
///
/// **Scroll hint.** A 16 dp static [LinearGradient] overlay (background colour
/// to transparent) on each overflowing edge, inside an [IgnorePointer]. There
/// is deliberately **no `ShaderMask`** — it would force a `saveLayer` every
/// frame on a strip that scrolls.
///
/// **Behaviour.** [leadingPinned] renders outside the scroll view on the left
/// and never scrolls away; [trailingAction] renders outside on the right. The
/// strip owns its own [ScrollController] (or uses [controller]) so a parent
/// vertical scroller cannot steal its horizontal drags.
///
/// Stateful rather than stateless because "show the hint only when the strip
/// actually overflows" requires reading scroll metrics after layout.
class ChipStrip extends StatefulWidget {
  const ChipStrip({
    super.key,
    required this.children,
    this.leadingPinned,
    this.trailingAction,
    this.height = MemSize.chipStrip,
    this.backgroundColor,
    this.controller,
  });

  /// Chips; each is already a >=48 dp target (`CollectionTag(chip)`,
  /// `ActionChip`, etc.). The strip additionally forces
  /// [MaterialTapTargetSize.padded] on any stock chip inside it.
  final List<Widget> children;

  /// E.g. the `All` chip — never scrolls away.
  final Widget? leadingPinned;

  /// E.g. the manage-collections icon button.
  final Widget? trailingAction;

  final double height;

  /// Defaults to `colorScheme.surface` — the scroll-hint gradient fades to
  /// this colour, so it must match whatever is actually behind the strip.
  final Color? backgroundColor;

  final ScrollController? controller;

  @override
  State<ChipStrip> createState() => _ChipStripState();
}

class _ChipStripState extends State<ChipStrip> {
  ScrollController? _owned;
  bool _overflows = false;

  ScrollController get _controller => widget.controller ?? _owned!;

  @override
  void initState() {
    super.initState();
    if (widget.controller == null) _owned = ScrollController();
    WidgetsBinding.instance.addPostFrameCallback((_) => _syncOverflow());
  }

  @override
  void didUpdateWidget(covariant ChipStrip oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      if (widget.controller != null) {
        _owned?.dispose();
        _owned = null;
      } else {
        _owned ??= ScrollController();
      }
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _syncOverflow());
  }

  @override
  void dispose() {
    _owned?.dispose();
    super.dispose();
  }

  void _syncOverflow() {
    if (!mounted) return;
    final ScrollController c = _controller;
    final bool next = c.hasClients && c.position.maxScrollExtent > 0;
    if (next != _overflows) setState(() => _overflows = next);
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color background = widget.backgroundColor ?? theme.colorScheme.surface;

    // 16 dp leading/trailing padding belongs to whatever sits at each end: the
    // pinned chip when there is one, otherwise the scroll view itself.
    final double scrollLeadPad = widget.leadingPinned == null
        ? MemInsets.pageH
        : MemSpace.chipGap;
    final double scrollTrailPad = widget.trailingAction == null
        ? MemInsets.pageH
        : MemSpace.chipGap;

    final Widget scroller = NotificationListener<ScrollMetricsNotification>(
      onNotification: (ScrollMetricsNotification n) {
        // Fires when the extent changes (chips added/removed, width changed).
        WidgetsBinding.instance.addPostFrameCallback((_) => _syncOverflow());
        return false;
      },
      child: ListView.separated(
        controller: _controller,
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.only(left: scrollLeadPad, right: scrollTrailPad),
        itemCount: widget.children.length,
        separatorBuilder: (BuildContext context, int index) =>
            const SizedBox(width: MemSpace.chipGap),
        itemBuilder: (BuildContext context, int index) =>
            Center(child: widget.children[index]),
      ),
    );

    final List<Widget> row = <Widget>[];
    if (widget.leadingPinned != null) {
      row
        ..add(const SizedBox(width: MemInsets.pageH))
        ..add(Center(child: widget.leadingPinned));
    }
    row.add(
      Expanded(
        child: Stack(
          children: <Widget>[
            Positioned.fill(child: scroller),
            if (_overflows) ...<Widget>[
              _ScrollHint(background: background, atStart: true),
              _ScrollHint(background: background, atStart: false),
            ],
          ],
        ),
      ),
    );
    if (widget.trailingAction != null) {
      row
        ..add(Center(child: widget.trailingAction))
        ..add(const SizedBox(width: MemInsets.pageH));
    }

    return Theme(
      // Stock chips read their tap-target size from ThemeData, not from
      // ChipThemeData — so the padded target is pinned here, for the whole
      // strip. This is the fix for the old ~32 px chips.
      data: theme.copyWith(materialTapTargetSize: MaterialTapTargetSize.padded),
      child: SizedBox(
        height: widget.height,
        child: ColoredBox(
          color: background,
          child: Row(children: row),
        ),
      ),
    );
  }
}

/// One edge of the scroll hint: a static gradient, never a `ShaderMask`.
class _ScrollHint extends StatelessWidget {
  const _ScrollHint({required this.background, required this.atStart});

  final Color background;
  final bool atStart;

  @override
  Widget build(BuildContext context) {
    return PositionedDirectional(
      top: 0,
      bottom: 0,
      start: atStart ? 0 : null,
      end: atStart ? null : 0,
      child: IgnorePointer(
        child: Container(
          width: MemSize.scrollHint,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: atStart
                  ? AlignmentDirectional.centerStart
                  : AlignmentDirectional.centerEnd,
              end: atStart
                  ? AlignmentDirectional.centerEnd
                  : AlignmentDirectional.centerStart,
              colors: <Color>[background, background.withValues(alpha: 0)],
            ),
          ),
        ),
      ),
    );
  }
}
