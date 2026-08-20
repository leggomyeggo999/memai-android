import 'package:flutter/material.dart';

import '../theme/mem_collection_ink.dart';
import '../theme/mem_metrics.dart';

/// The three shapes a collection's identity ink takes.
///
/// * [tag] — display / navigation, 24 dp tall, used in note-row meta rows and
///   on NoteDetail.
/// * [chip] — filter bars, 40 dp visual inside a 48 dp target.
/// * [dot] — a 10 dp circle for a row's `leading`, where the title is adjacent
///   in the same row.
enum CollectionTagVariant { tag, chip, dot }

/// Widest a `tag` variant may grow before its title ellipsizes. Also the bound
/// that lets the tag live inside an unbounded-width parent without asserting.
const double kCollectionTagMaxWidth = 160;

/// Widest a `chip` variant may grow before its title ellipsizes.
const double kCollectionChipMaxWidth = 220;

/// A collection rendered in its stable identity ink.
///
/// The ink is derived client-side from the collection id (see
/// [collectionInkFor]) — the Mem data model has no colour field. Past 8
/// collections two collections share an ink **by design**, which is safe only
/// because **colour is never the sole signifier**: the [tag] and [chip]
/// variants always render the [title] beside the dot, and the [dot] variant is
/// permitted only where the title sits next to it in the same row.
///
/// Titles come from a client-side join of `MemNoteListItem.collectionIds`
/// against the already-fetched collections list. If a title is missing, pass
/// the raw id rather than hiding the tag.
class CollectionTag extends StatelessWidget {
  const CollectionTag({
    super.key,
    required this.collectionId,
    required this.title,
    this.variant = CollectionTagVariant.tag,
    this.count,
    this.selected = false,
    this.onTap,
  });

  final String collectionId;
  final String title;
  final CollectionTagVariant variant;

  /// Shown in the [CollectionTagVariant.chip] variant only, tabular.
  final int? count;

  /// [CollectionTagVariant.chip] variant only.
  final bool selected;

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final CollectionInk ink = collectionInkFor(context, collectionId);
    switch (variant) {
      case CollectionTagVariant.dot:
        return _buildDot(context, ink);
      case CollectionTagVariant.tag:
        return _buildTag(context, ink);
      case CollectionTagVariant.chip:
        return _buildChip(context, ink);
    }
  }

  Widget _buildDot(BuildContext context, CollectionInk ink) {
    final Widget dot = Container(
      width: 10,
      height: 10,
      decoration: BoxDecoration(color: ink.fg, shape: BoxShape.circle),
    );
    // The title is adjacent in the row, so the dot itself is decorative — but
    // it still names the collection for screen readers.
    final Widget labelled = Semantics(label: title, child: dot);
    if (onTap == null) return labelled;
    return _wrapTarget(context, labelled);
  }

  Widget _buildTag(BuildContext context, CollectionInk ink) {
    final TextTheme text = Theme.of(context).textTheme;
    final Widget visual = Container(
      height: 24,
      // Bounds the title so it ellipsizes instead of asserting when the tag
      // lands in an unbounded-width parent (a horizontal strip, a Wrap run).
      constraints: const BoxConstraints(maxWidth: kCollectionTagMaxWidth),
      padding: const EdgeInsets.symmetric(horizontal: MemSpace.x2),
      decoration: BoxDecoration(
        color: ink.bg,
        borderRadius: MemRadius.tagAll,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: ink.fg, shape: BoxShape.circle),
          ),
          const SizedBox(width: MemSpace.x1 + 2),
          Flexible(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: text.labelMedium?.copyWith(color: ink.fg),
            ),
          ),
        ],
      ),
    );
    if (onTap == null) return visual;
    // The visual stays 24 dp; the widget is padded out to a 48 dp target.
    return _wrapTarget(context, visual);
  }

  Widget _buildChip(BuildContext context, CollectionInk ink) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final double hairline = hairlineWidth(context);

    // Selection salience is one rule app-wide: primary fill + onPrimary content
    // + a 16 dp check + w600 label. The ink dot survives selection so the
    // collection's identity does not disappear when you filter by it.
    final Color fill = selected ? scheme.primary : ink.bg;
    final Color label = selected ? scheme.onPrimary : ink.fg;

    final List<Widget> children = <Widget>[];
    if (selected) {
      children
        ..add(
          Icon(Icons.check, size: MemSize.selectionCheck, color: label),
        )
        ..add(const SizedBox(width: MemSpace.x1 + 2));
    }
    children
      ..add(
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: ink.fg, shape: BoxShape.circle),
        ),
      )
      ..add(const SizedBox(width: MemSpace.x2))
      ..add(
        Flexible(
          child: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelMedium?.copyWith(color: label),
          ),
        ),
      );
    if (count != null) {
      children
        ..add(const SizedBox(width: MemSpace.x1 + 2))
        ..add(
          Text(
            '· $count',
            style: theme.textTheme.labelMedium?.copyWith(color: label),
          ),
        );
    }

    final Widget visual = Container(
      height: 40,
      constraints: const BoxConstraints(maxWidth: kCollectionChipMaxWidth),
      padding: const EdgeInsets.symmetric(horizontal: MemSpace.x3),
      decoration: BoxDecoration(
        color: fill,
        borderRadius: MemRadius.controlAll,
        border: Border.all(color: scheme.outline, width: hairline),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: children),
    );

    return _wrapTarget(context, visual, selected: selected);
  }

  /// Pads a smaller visual out to the app-wide 48 dp minimum touch target and
  /// gives it the 80 ms press flash.
  Widget _wrapTarget(
    BuildContext context,
    Widget visual, {
    bool selected = false,
  }) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Semantics(
      button: onTap != null,
      selected: selected,
      label: title,
      // Both axes. `Center(widthFactor: 1)` shrink-wraps the visual's width, so
      // a height-only box leaves a short title — a 1–2 character collection in
      // the 24 dp `tag` variant — under 48 dp horizontally.
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          minWidth: MemSize.touchTarget,
          minHeight: MemSize.touchTarget,
        ),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            onTap: onTap,
            borderRadius: MemRadius.controlAll,
            overlayColor: memPressOverlay(scheme),
            child: Center(widthFactor: 1, child: visual),
          ),
        ),
      ),
    );
  }
}

/// The `+n` tag that stands in for the collection tags a note row could not
/// fit. Note rows show at most **2** [CollectionTag]s, then this.
///
/// It is deliberately *not* inked: it represents several collections at once,
/// so it renders in `surfaceContainer` / `onSurfaceVariant`.
class CollectionOverflowTag extends StatelessWidget {
  const CollectionOverflowTag({super.key, required this.count, this.onTap});

  /// How many collections are hidden behind this tag.
  final int count;

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;

    final Widget visual = Container(
      height: 24,
      padding: const EdgeInsets.symmetric(horizontal: MemSpace.x2),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: scheme.surfaceContainer,
        borderRadius: MemRadius.tagAll,
      ),
      child: Text(
        '+$count',
        style: theme.textTheme.labelMedium?.copyWith(
          color: scheme.onSurfaceVariant,
        ),
      ),
    );

    if (onTap == null) {
      return Semantics(label: '$count more collections', child: visual);
    }
    return Semantics(
      button: true,
      label: '$count more collections',
      // Same both-axes minimum: `+9` is narrower than 48 dp on its own.
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          minWidth: MemSize.touchTarget,
          minHeight: MemSize.touchTarget,
        ),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            onTap: onTap,
            borderRadius: MemRadius.controlAll,
            overlayColor: memPressOverlay(scheme),
            child: Center(widthFactor: 1, child: visual),
          ),
        ),
      ),
    );
  }
}
