import 'package:flutter/material.dart';

import '../theme/mem_metrics.dart';
import 'hairline.dart';

/// First-load placeholders (§3.11).
///
/// **A skeleton is shown only when there is nothing else to show.** Never
/// during a refresh that still has stale content (that keeps its rows, §5.3),
/// never for an infinite-scroll append — that gets three tail rows, which
/// preserve scroll continuity far better than a spinner does.
///
/// The pulse is an **opacity animation on the bar colours themselves**
/// (0.55 → 1.0 over `MemMotion.skeleton`, `MemMotion.pulse`), not an `Opacity`
/// layer and not a shimmer sweep: both are banned by the per-frame cost budget
/// (§2.11) because they force a `saveLayer` every frame. One
/// `AnimationController` drives a whole [SkeletonList]; the rows read the
/// current alpha out of an inherited scope.
///
/// **Why the row rules are `outline`, not `outlineVariant` (§2.7).** In a
/// loaded [AppListSection] the row rhythm is carried by the text — title,
/// snippet, tags — and `outlineVariant` only *decorates* a boundary the reader
/// already perceives; 1.5 : 1 is enough for that job. A skeleton has no text.
/// The rule is the **only** thing dividing one placeholder surface from the
/// next, so here it is doing boundary duty, and §2.7 assigns boundary duty to
/// `outline` (≥3 : 1 against its host — 3.2 : 1 on dark `surfaceContainerLow`,
/// 3.6 : 1 on light). With `outlineVariant` the dark skeleton collapsed into one
/// continuous grey block and stopped previewing the shape of the arriving
/// content. Same token in both themes, so the rows read as discrete in both.
class SkeletonList extends StatelessWidget {
  const SkeletonList({
    super.key,
    this.rowCount = 8,
    this.rowHeight = MemSize.rowNote,
    this.inSection = true,
  });

  final int rowCount;
  final double rowHeight;

  /// Draws the rows inside the same bounded container real rows live in —
  /// `surfaceContainerLow`, radius 12, 1 dp `outline` — so the section does not
  /// pop into existence when the data lands. Off for a bare tail of rows
  /// appended inside an existing section.
  ///
  /// Row rules are drawn either way: a tail of three placeholder rows with no
  /// rules between them is exactly the continuous-grey-block failure this
  /// component exists to avoid.
  final bool inSection;

  @override
  Widget build(BuildContext context) {
    final ColorScheme cs = Theme.of(context).colorScheme;
    final List<Widget> rows = <Widget>[];
    for (int i = 0; i < rowCount; i++) {
      if (i > 0) {
        // `outline`, not the `Hairline` default — see the class doc. The rule
        // is the only thing separating two contentless surfaces here, so it is
        // a boundary, not a decorative divider.
        rows.add(
          Hairline(color: cs.outline, indent: MemSpace.dividerIndent),
        );
      }
      rows.add(SkeletonRow(height: rowHeight));
    }

    final Widget column = Column(
      mainAxisSize: MainAxisSize.min,
      // `stretch`, and it is load-bearing. A [Hairline] is a `SizedBox(height:)`
      // wrapping a childless `ColoredBox`, which takes the *smallest* width its
      // constraints allow. Under `Column`'s default `center` cross-alignment
      // those constraints are loose, so every rule collapsed to zero width: the
      // rows still reserved the 1 dp of vertical space but nothing was painted,
      // and the skeleton went back to being one continuous block. Stretching
      // gives the rules a tight width. `AppListSection` does the same, for the
      // same reason — the two must match or the swap to loaded content moves
      // the boundaries.
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: rows,
    );

    return ExcludeSemantics(
      child: _SkeletonPulse(
        child: inSection
            ? Container(
                margin: MemSpace.pageHorizontal,
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  color: cs.surfaceContainerLow,
                  borderRadius: MemRadius.sectionAll,
                  border: Border.all(
                    color: cs.outline,
                    width: hairlineWidth(context),
                  ),
                ),
                child: column,
              )
            : column,
      ),
    );
  }
}

/// One placeholder row, shaped to the real row geometry: a 60 % title bar, two
/// snippet bars, a tag stub, and a time stub.
///
/// **Geometry is copied from `AppRow`, not approximated** — 16 dp horizontal /
/// `sectionPadV` vertical padding, and [height] as a *minimum* rather than a
/// fixed box, which is `AppRow`'s own contract. The bars therefore land on the
/// same baselines the real title, snippet and meta row will occupy, so the
/// swap to loaded content does not shift anything.
///
/// Inside a [SkeletonList] it shares the list's single pulse; standalone (the
/// three tail rows of an infinite-scroll append) it brings its own.
class SkeletonRow extends StatelessWidget {
  const SkeletonRow({super.key, this.height = MemSize.rowNote});

  final double height;

  @override
  Widget build(BuildContext context) {
    final double? alpha = _SkeletonPulseScope.maybeOf(context);
    if (alpha == null) {
      // No list above us — wrap ourselves so a lone row still pulses. The inner
      // build finds the scope and takes the branch below.
      return ExcludeSemantics(
        child: _SkeletonPulse(child: SkeletonRow(height: height)),
      );
    }

    final ColorScheme cs = Theme.of(context).colorScheme;
    final Color ink = cs.surfaceContainerHigh.withValues(alpha: alpha);
    // The title + two snippet bars + meta stub only fit a 76 dp note row once
    // AppRow's 12 dp vertical padding is paid for. Anything shorter is a
    // settings or single-line row, which really is one line of text — degrade
    // to the title bar rather than overflow the row.
    final bool compact = height < MemSize.rowNote;

    return ConstrainedBox(
      // A minimum, never a fixed height — the same contract AppRow states, so
      // neither side of the swap can clip the other.
      constraints: BoxConstraints(minHeight: height),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: MemSpace.x4,
          vertical: MemSpace.sectionPadV,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: FractionallySizedBox(
                      widthFactor: 0.6,
                      child: _Bar(height: 14, color: ink),
                    ),
                  ),
                ),
                const SizedBox(width: MemSpace.x2),
                _Bar(height: 10, width: 32, color: ink),
              ],
            ),
            if (!compact) ...<Widget>[
              const SizedBox(height: MemSpace.x2),
              _Bar(height: 10, color: ink),
              const SizedBox(height: 6),
              Row(
                children: <Widget>[
                  Expanded(
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: FractionallySizedBox(
                        widthFactor: 0.55,
                        child: _Bar(height: 10, color: ink),
                      ),
                    ),
                  ),
                  const SizedBox(width: MemSpace.x2),
                  _Bar(height: 12, width: 48, color: ink),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// One placeholder bar. Radius 6 — the small-badge step of the radius scale.
class _Bar extends StatelessWidget {
  const _Bar({required this.height, required this.color, this.width});

  final double height;
  final double? width;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      width: width,
      decoration: BoxDecoration(
        color: color,
        borderRadius: MemRadius.tagAll,
      ),
    );
  }
}

/// Owns the single [AnimationController] and republishes its value to the rows
/// below through an inherited scope. Only the scope rebuilds each tick — the
/// subtree is passed through as a captured `child`.
class _SkeletonPulse extends StatefulWidget {
  const _SkeletonPulse({required this.child});

  final Widget child;

  @override
  State<_SkeletonPulse> createState() => _SkeletonPulseState();
}

class _SkeletonPulseState extends State<_SkeletonPulse>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: MemMotion.skeleton,
  )..repeat(reverse: true);

  late final Animation<double> _alpha = Tween<double>(begin: 0.55, end: 1.0)
      .animate(CurvedAnimation(parent: _controller, curve: MemMotion.pulse));

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _alpha,
      builder: (BuildContext context, Widget? child) =>
          _SkeletonPulseScope(alpha: _alpha.value, child: child!),
      child: widget.child,
    );
  }
}

class _SkeletonPulseScope extends InheritedWidget {
  const _SkeletonPulseScope({required this.alpha, required super.child});

  final double alpha;

  static double? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<_SkeletonPulseScope>()
      ?.alpha;

  @override
  bool updateShouldNotify(_SkeletonPulseScope oldWidget) =>
      oldWidget.alpha != alpha;
}
