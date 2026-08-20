import 'dart:math' as math;

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

// --- Pill geometry ---------------------------------------------------------

/// Horizontal padding inside the status pill.
const double _kPillPadH = MemSpace.x2 + 2;

/// Vertical padding inside the status pill. With `labelMedium` (12/16) this
/// makes a 28 dp pill; the 16 dp [InlineSpinner] of the busy state occupies the
/// same 16 dp line box, so the pill does **not** change height when work
/// starts.
const double _kPillPadV = MemSpace.x1 + 2;

/// Gap between the pill's dot/spinner and its text.
const double _kPillGap = MemSpace.x2;

/// The busy indicator's diameter — §3.10 fixes 16 inside buttons and pills.
const double _kPillSpinner = 16;

/// The pill's generous ceiling. Every realistic status string is far shorter:
/// at 411 dp with Roboto, `Waiting for browser…` measures ~132 dp of text plus
/// 44 dp of chrome, and `Key saved · ····4F2` ~113 + 36. The cap exists only so
/// a pathological caller string cannot swallow the whole row.
const double _kPillMaxWidth = 260;

/// The leading glyph (§3.9).
const double _kIconSize = 20;

/// The width the label column must keep before the inline arrangement is
/// allowed. Below this the label would ellipsize down to two or three
/// characters, so the pill moves to its own line instead of eating the label.
const double _kMinLabelWidth = 80;

/// The trailing `TextButton`'s geometry as pinned by the button theme
/// (`minimumSize` 64 x 48, 16 dp horizontal padding). Used only to *predict*
/// the button's width when choosing an arrangement — the button itself is
/// rendered by the theme, never restyled here. An underestimate is absorbed by
/// the label column, which is the flexible child, so it can never overflow.
const double _kActionMinWidth = 64;
const double _kActionPadH = 16;

/// The replacement for every disabled-buttons-as-status pattern.
///
/// State is stated, not implied: a labelled row, a dot in the level colour, the
/// status in words, and **exactly one** action button. While [busy] the pill
/// shows an [InlineSpinner] beside the pending copy and the action is disabled
/// — that is what closes the OAuth browser-round-trip dead-air gap.
///
/// `success` / `warning` / `pending` may appear **only** as the 8 dp dot or as
/// this pill's text and container. They are never a button, row, or chip fill.
///
/// ## Layout contract
///
/// **The pill is never squeezed and never wraps.** Its text is one line,
/// `softWrap: false` — a status can therefore not break inside a word, which is
/// what a flex-starved two-line pill used to do (`Waitin` / `g for …`). The
/// pill is laid out at its **natural** width (capped by [_kPillMaxWidth]) and
/// the label column, not the pill, is the flexible child that yields.
///
/// When even that cannot fit — a long status *and* an action button on a 411 dp
/// screen, or any large text scale — the tile switches to a **stacked**
/// arrangement: label (and detail) on the first line, pill and action on their
/// own line beneath, indented to the label's left edge. That is the degradation
/// path at `textScaleFactor` 2.0 as well, where the pill+action line is a
/// [Wrap], so the action drops below the pill rather than clipping. Nothing is
/// ever clipped and no arrangement can overflow: the only inflexible children
/// are measured before they are committed to.
///
/// Truncation is the last resort, and it happens **at a word boundary** (see
/// `_ellipsizeAtWordBoundary`), so a masked secret degrades to `Key saved` and
/// never to the meaningless `Key saved ·…`.
///
/// **Touch targets (§0.1 rule 4).** The pill is decoration, not a control — it
/// has no gesture of its own. The interactive surfaces are the whole tile
/// ([onTap]), which is at least `MemSize.rowSettings` = 56 dp tall, and the
/// trailing action, which the button theme pins to a 48 dp minimum with
/// `MaterialTapTargetSize.padded`.
///
/// **The leading glyph belongs to the first text line**, not to the column: it
/// sits in a box exactly one `titleSmall` line tall and is optically centred
/// inside it, so it stays level with the label whether or not a [detail] line
/// is present, at every text scale.
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

  /// Leading 20 dp glyph, aligned to the [label] line.
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
    final TextScaler scaler = MediaQuery.textScalerOf(context);
    final TextDirection direction = Directionality.of(context);

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

    final TextStyle? pillStyle = text.labelMedium?.copyWith(color: pillFg);
    final TextStyle? labelStyle = text.titleSmall?.copyWith(
      color: scheme.onSurface,
    );

    final bool hasAction = actionLabel != null && onAction != null;

    // --- Measurements -----------------------------------------------------
    // Short, single-line strings measured with the live text scaler. This is
    // what lets the pill be an *inflexible* child (natural width, never
    // starved) without ever risking an overflow: the arrangement is chosen
    // from real widths rather than from a flex ratio that knows nothing about
    // the copy.
    final double indicator = busy ? _kPillSpinner : MemSize.statusDot;
    final double pillChrome = _kPillPadH * 2 + indicator + _kPillGap;
    final double pillNatural =
        pillChrome + _measureText(status, pillStyle, scaler, direction);
    final double pillWanted = math.min(pillNatural, _kPillMaxWidth);

    final double labelNatural = _measureText(
      label,
      labelStyle,
      scaler,
      direction,
    );
    // A label shorter than the floor never forces the stacked arrangement.
    final double labelFloor = math.min(labelNatural, _kMinLabelWidth);

    final double actionWidth = hasAction
        ? math.max(
            _kActionMinWidth,
            _measureText(actionLabel!, text.labelLarge, scaler, direction) +
                _kActionPadH * 2,
          )
        : 0;
    final double actionSlot = hasAction ? MemSpace.x2 + actionWidth : 0;

    // --- Slots ------------------------------------------------------------
    // One `titleSmall` line box, derived from the live scaler so the glyph
    // tracks the label at every text scale.
    final double labelLine =
        scaler.scale(text.titleSmall?.fontSize ?? 14) *
        (text.titleSmall?.height ?? 20 / 14);
    final double leadWidth = _kIconSize + MemSpace.x3;

    final Widget leadingAndLabel = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        SizedBox(
          height: labelLine,
          // `Center` loosens the constraint, so the glyph keeps its own size
          // and overhangs symmetrically rather than being squashed.
          child: Center(
            widthFactor: 1,
            child: Icon(icon, size: _kIconSize, color: scheme.onSurfaceVariant),
          ),
        ),
        const SizedBox(width: MemSpace.x3),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: labelStyle,
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
      ],
    );

    Widget buildPill(double maxWidth) {
      // Word-boundary truncation, applied only when the pill genuinely cannot
      // hold the copy. The widget's own `ellipsis` stays on as a backstop for
      // the single-unbreakable-word case.
      final String shown = _ellipsizeAtWordBoundary(
        status,
        maxWidth - pillChrome,
        pillStyle,
        scaler,
        direction,
      );
      return ConstrainedBox(
        constraints: BoxConstraints(maxWidth: math.max(0, maxWidth)),
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: _kPillPadH,
            vertical: _kPillPadV,
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
              const SizedBox(width: _kPillGap),
              Flexible(
                child: Text(
                  shown,
                  maxLines: 1,
                  softWrap: false,
                  overflow: TextOverflow.ellipsis,
                  style: pillStyle,
                ),
              ),
            ],
          ),
        ),
      );
    }

    Widget? buildAction() => hasAction
        ? TextButton(
            onPressed: busy ? null : onAction,
            child: Text(actionLabel!),
          )
        : null;

    Widget content = Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: MemSpace.x4,
        vertical: MemSpace.sectionPadV,
      ),
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          final double avail = constraints.maxWidth;
          final double inlineNeed =
              leadWidth + labelFloor + MemSpace.x2 + pillWanted + actionSlot;
          final bool inline = !avail.isFinite || inlineNeed <= avail;

          if (inline) {
            // The pill is inflexible here — it gets its natural width and the
            // label column absorbs the remainder. The ceiling below is inert
            // whenever the measurement was right, and is the safety net when
            // it was not.
            final double pillBox = avail.isFinite
                ? math.min(
                    pillWanted,
                    avail - leadWidth - MemSpace.x2 - actionSlot - labelFloor,
                  )
                : pillWanted;
            return Row(
              // Row-level slots centre against the row; the leading glyph does
              // not — it is aligned to the label line inside [leadingAndLabel].
              crossAxisAlignment: CrossAxisAlignment.center,
              children: <Widget>[
                Expanded(child: leadingAndLabel),
                const SizedBox(width: MemSpace.x2),
                buildPill(pillBox),
                if (hasAction) ...<Widget>[
                  const SizedBox(width: MemSpace.x2),
                  buildAction()!,
                ],
              ],
            );
          }

          // Stacked: the pill keeps its full copy on a line of its own rather
          // than truncating, or starving the label to three characters.
          final double stackedWidth = avail - leadWidth;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              leadingAndLabel,
              const SizedBox(height: MemSpace.x2),
              Padding(
                padding: EdgeInsetsDirectional.only(start: leadWidth),
                child: Wrap(
                  spacing: MemSpace.x2,
                  runSpacing: MemSpace.x1,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: <Widget>[
                    buildPill(math.min(_kPillMaxWidth, stackedWidth)),
                    if (hasAction) buildAction()!,
                  ],
                ),
              ),
            ],
          );
        },
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
      // A minimum, never a fixed height: the stacked arrangement and large
      // text scales grow the tile instead of clipping it.
      constraints: const BoxConstraints(minHeight: MemSize.rowSettings),
      child: content,
    );
  }
}

/// Natural single-line width of [value] in [style] at the live text scale.
double _measureText(
  String value,
  TextStyle? style,
  TextScaler scaler,
  TextDirection direction,
) {
  final TextPainter painter = TextPainter(
    text: TextSpan(text: value, style: style),
    textDirection: direction,
    textScaler: scaler,
    maxLines: 1,
  )..layout();
  final double width = painter.width;
  painter.dispose();
  return width;
}

/// Trims [value] back to whole words until it fits [maxWidth].
///
/// `TextOverflow.ellipsis` cuts mid-word (`Key saved ·…`), which is exactly the
/// truncation that destroys a masked secret's meaning. Dropping whole words
/// instead keeps every rendered character legible. Returns [value] unchanged
/// when it already fits, or when the first word alone does not — the `Text`
/// widget's own ellipsis handles that degenerate case.
String _ellipsizeAtWordBoundary(
  String value,
  double maxWidth,
  TextStyle? style,
  TextScaler scaler,
  TextDirection direction,
) {
  if (maxWidth <= 0) return value;
  if (_measureText(value, style, scaler, direction) <= maxWidth) return value;

  final List<String> words = value
      .split(RegExp(r'\s+'))
      .where((String w) => w.isNotEmpty)
      .toList(growable: false);

  for (int end = words.length - 1; end >= 1; end--) {
    final String head = _trimTrailingSeparators(words.take(end).join(' '));
    if (head.isEmpty) break;
    final String candidate = head.endsWith('…') ? head : '$head…';
    if (_measureText(candidate, style, scaler, direction) <= maxWidth) {
      return candidate;
    }
  }
  return value;
}

/// Drops the dangling separators a truncation can leave behind, so the result
/// reads `Key saved…` rather than `Key saved ·…`.
String _trimTrailingSeparators(String value) {
  const String separators = '·,-—:;';
  String out = value.trimRight();
  while (out.isNotEmpty && separators.contains(out[out.length - 1])) {
    out = out.substring(0, out.length - 1).trimRight();
  }
  return out;
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
