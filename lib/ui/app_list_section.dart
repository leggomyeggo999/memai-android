import 'package:flutter/material.dart';

import '../theme/mem_metrics.dart';

/// The grouped-section list primitive.
///
/// Replaces every hand-rolled `Material(color: cardTheme.color, radius 14)`
/// per-row card. **A section is one `surfaceContainerLow` container, radius 12,
/// with a 1 dp `outline` border; rows are full-bleed inside it, separated by
/// 1 dp `outlineVariant` dividers inset 16 dp from the left.** Depth comes from
/// the surface step plus the hairline — never from elevation or a shadow.
class AppListSection extends StatelessWidget {
  const AppListSection({
    super.key,
    required this.children,
    this.header,
    this.margin = MemSpace.pageHorizontal,
    this.dividerIndent = MemSpace.dividerIndent,
    this.showDividers = true,
  });

  /// Usually [AppRow], but any widget is allowed.
  final List<Widget> children;

  /// Optional header rendered **above** the bordered container (typically a
  /// `SectionHeader`), so the eyebrow sits on the canvas, not inside the box.
  final Widget? header;

  final EdgeInsetsGeometry margin;

  /// Left inset of the 1 dp `outlineVariant` dividers between rows.
  final double dividerIndent;

  /// Set false for sections whose children draw their own separation.
  final bool showDividers;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final double hairline = hairlineWidth(context);

    if (children.isEmpty) {
      // An empty bordered box reads as a broken section; render the header
      // alone (or nothing) instead.
      if (header == null) return const SizedBox.shrink();
      return Padding(padding: margin, child: header);
    }

    final List<Widget> rows = <Widget>[];
    for (int i = 0; i < children.length; i++) {
      rows.add(children[i]);
      final bool isLast = i == children.length - 1;
      if (showDividers && !isLast) {
        rows.add(
          Divider(
            height: hairline,
            thickness: hairline,
            indent: dividerIndent,
            endIndent: 0,
            color: scheme.outlineVariant,
          ),
        );
      }
    }

    // `Material` (not `Container`) so the rows' ink is clipped to the section
    // and so `shape` carries the boundary hairline in one pass.
    final Widget section = Material(
      color: scheme.surfaceContainerLow,
      elevation: 0,
      surfaceTintColor: Colors.transparent,
      shadowColor: Colors.transparent,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: MemRadius.sectionAll,
        side: BorderSide(color: scheme.outline, width: hairline),
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: rows),
    );

    return Padding(
      padding: margin,
      child: header == null
          ? section
          : Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                header!,
                const SizedBox(height: MemSpace.headerGap),
                section,
              ],
            ),
    );
  }
}

/// How much of an [AppRow]'s content the current text scale allows.
///
/// The degradation order is mandatory and is specified once, here:
///
/// 1. [compact] — drop the second snippet line.
/// 2. [condensed] — additionally collapse collection tags to `+n` and let the
///    meta row wrap.
///
/// [AppRow] applies the parts it owns (subtitle line count, where
/// `trailingText` is placed, and the fact that no row ever has a fixed height).
/// The parts it cannot own — the caller-built `meta` row — read the density
/// from [AppRowDensityScope] and degrade themselves.
enum AppRowDensity {
  normal,
  compact,
  condensed;

  /// True once collection tags must collapse to a single `+n` tag.
  bool get collapseTags => this == AppRowDensity.condensed;

  /// True once the meta row must wrap instead of staying on one line.
  bool get wrapMeta => this == AppRowDensity.condensed;
}

/// Publishes the [AppRowDensity] an [AppRow] resolved for the current text
/// scale, so caller-built `meta` content can degrade in step with it.
class AppRowDensityScope extends InheritedWidget {
  const AppRowDensityScope({
    super.key,
    required this.density,
    required super.child,
  });

  final AppRowDensity density;

  /// Defaults to [AppRowDensity.normal] outside an [AppRow].
  static AppRowDensity of(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<AppRowDensityScope>()
          ?.density ??
      AppRowDensity.normal;

  @override
  bool updateShouldNotify(AppRowDensityScope oldWidget) =>
      oldWidget.density != density;
}

/// One full-bleed row inside an [AppListSection].
///
/// The **whole row** is the tap target. `trailing` must never hold the row's
/// primary action — primary actions are the row tap or a visible icon button;
/// kebabs hold *secondary* verbs only.
class AppRow extends StatelessWidget {
  const AppRow({
    super.key,
    this.leading,
    required this.title,
    this.subtitle,
    this.subtitleMaxLines = 2,
    this.meta,
    this.trailingText,
    this.trailing,
    this.onTap,
    this.onLongPress,
    this.minHeight = MemSize.rowSettings,
    this.enabled = true,
    this.selected = false,
  });

  /// <=24 dp glyph or a `CollectionTag(dot)`.
  ///
  /// Aligned to the **title line**, not to the row: on a two-line row it sits
  /// beside the title, never beside the snippet.
  final Widget? leading;

  /// Styled `titleMedium`, 1 line, ellipsis — a bare `Text` inherits all three.
  /// Pass a `Hero` wrapping the `Text` where a flight is specified; it inherits
  /// the same default style, so nothing restyles mid-flight.
  final Widget title;

  /// Styled `bodyMedium` `onSurfaceVariant`, [subtitleMaxLines] lines.
  final Widget? subtitle;

  final int subtitleMaxLines;

  /// Widget row under the subtitle (tags + right-aligned time). Read
  /// [AppRowDensityScope.of] inside it to honour the degradation order.
  final Widget? meta;

  /// `bodySmall` `onSurfaceVariant`, tabular, right-aligned.
  final String? trailingText;

  /// ONE control max — never the row's primary action.
  final Widget? trailing;

  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  final double minHeight;

  /// False => non-tappable AND rendered at reduced emphasis (via colour tokens,
  /// never an `Opacity` layer).
  final bool enabled;

  /// True adds a 2 dp `primary` left bar and a `primary` check glyph.
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final TextTheme text = theme.textTheme;

    final TextScaler scaler = MediaQuery.textScalerOf(context);

    // The degradation trigger: how far a 14 dp body line has been stretched.
    final double scaled = scaler.scale(14);
    final AppRowDensity density = scaled > 14 * 1.6
        ? AppRowDensity.condensed
        : scaled > 14 * 1.3
        ? AppRowDensity.compact
        : AppRowDensity.normal;

    // Reduced emphasis is a colour token, not an opacity layer.
    final Color titleColor = enabled
        ? scheme.onSurface
        : scheme.onSurfaceVariant;
    final Color secondaryColor = enabled
        ? scheme.onSurfaceVariant
        : scheme.outline;

    final int effectiveSubtitleLines = density == AppRowDensity.normal
        ? subtitleMaxLines
        : 1;

    final Widget titleSlot = DefaultTextStyle.merge(
      style: text.titleMedium?.copyWith(color: titleColor),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      child: title,
    );

    final Widget? subtitleSlot = subtitle == null
        ? null
        : DefaultTextStyle.merge(
            style: text.bodyMedium?.copyWith(color: secondaryColor),
            maxLines: effectiveSubtitleLines,
            overflow: TextOverflow.ellipsis,
            child: subtitle!,
          );

    final Widget? trailingTextSlot = trailingText == null
        ? null
        : Text(
            trailingText!,
            style: text.bodySmall?.copyWith(color: secondaryColor),
            textAlign: TextAlign.end,
          );

    // At condensed scale the trailing text moves under the content instead of
    // competing with the title for horizontal space — that is what keeps the
    // row from clipping at text scale 2.0.
    final bool trailingTextInline =
        trailingTextSlot != null && density != AppRowDensity.condensed;

    final List<Widget> column = <Widget>[titleSlot];
    if (subtitleSlot != null) {
      column
        ..add(const SizedBox(height: 2))
        ..add(subtitleSlot);
    }
    if (meta != null) {
      column
        ..add(const SizedBox(height: MemSpace.x1 + 2))
        ..add(meta!);
    }
    if (trailingTextSlot != null && !trailingTextInline) {
      column
        ..add(const SizedBox(height: MemSpace.x1))
        ..add(Align(alignment: Alignment.centerRight, child: trailingTextSlot));
    }

    final Widget contentColumn = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: column,
    );

    // The leading slot belongs to the TITLE, not to the row. Centring it
    // against the whole row floats a dot or glyph down beside the snippet on
    // any two-line row. So: the leading + content pair is top-aligned, and the
    // leading sits in a box exactly one `titleMedium` line tall and is
    // optically centred inside it. Because the box is derived from the live
    // text scaler it tracks the title line at every scale, and a <=24 dp glyph
    // stays centred on the title whether the row is one line, two lines, or
    // carries tags underneath. `trailingText`, the selection check and
    // `trailing` stay centred against the row — they are row-level, not
    // title-level — so the outer row keeps `center`.
    final double titleLine =
        scaler.scale(text.titleMedium?.fontSize ?? 16) *
        (text.titleMedium?.height ?? 22 / 16);

    final Widget leadingAndContent = leading == null
        ? contentColumn
        : Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              SizedBox(
                height: titleLine,
                // `Center` loosens the constraint, so a leading widget taller
                // than the line box (a 24 dp glyph against a 22 dp line) keeps
                // its own size and overhangs symmetrically instead of being
                // squashed or clipped.
                child: Center(
                  widthFactor: 1,
                  child: IconTheme.merge(
                    data: IconThemeData(size: 24, color: secondaryColor),
                    child: leading!,
                  ),
                ),
              ),
              const SizedBox(width: MemSpace.x3),
              Expanded(child: contentColumn),
            ],
          );

    final List<Widget> rowChildren = <Widget>[
      Expanded(child: leadingAndContent),
    ];
    if (trailingTextInline) {
      rowChildren
        ..add(const SizedBox(width: MemSpace.x2))
        ..add(trailingTextSlot);
    }
    if (selected) {
      rowChildren
        ..add(const SizedBox(width: MemSpace.x2))
        ..add(
          Icon(
            Icons.check,
            size: MemSize.selectionCheck,
            color: scheme.primary,
          ),
        );
    }
    if (trailing != null) {
      rowChildren
        ..add(const SizedBox(width: MemSpace.x1))
        ..add(trailing!);
    }

    Widget content = Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: MemSpace.x4,
        vertical: MemSpace.sectionPadV,
      ),
      child: Row(
        // Row-level slots centre; the leading slot does not — see
        // [leadingAndContent] above.
        crossAxisAlignment: CrossAxisAlignment.center,
        children: rowChildren,
      ),
    );

    if (selected) {
      // 2 dp primary left bar, drawn outside the row padding.
      content = Stack(
        children: <Widget>[
          content,
          PositionedDirectional(
            top: 0,
            bottom: 0,
            start: 0,
            child: Container(width: 2, color: scheme.primary),
          ),
        ],
      );
    }

    final bool tappable = enabled && (onTap != null || onLongPress != null);
    if (tappable) {
      content = Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onTap,
          onLongPress: onLongPress,
          overlayColor: memPressOverlay(scheme),
          child: content,
        ),
      );
    }

    return AppRowDensityScope(
      density: density,
      child: ConstrainedBox(
        // A minimum, never a fixed height: content grows at large text scales
        // rather than clipping.
        constraints: BoxConstraints(minHeight: minHeight),
        child: content,
      ),
    );
  }
}
