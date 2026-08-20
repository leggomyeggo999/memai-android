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
  final bool inSection;

  @override
  Widget build(BuildContext context) {
    final ColorScheme cs = Theme.of(context).colorScheme;
    final List<Widget> rows = <Widget>[];
    for (int i = 0; i < rowCount; i++) {
      if (i > 0 && inSection) {
        rows.add(const Hairline(indent: MemSpace.dividerIndent));
      }
      rows.add(SkeletonRow(height: rowHeight));
    }

    final Widget column = Column(
      mainAxisSize: MainAxisSize.min,
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
    // Below ~64 dp there is no room for the snippet lines; degrade rather than
    // overflow (settings/single-line rows use this).
    final bool compact = height < MemSize.rowSingleLine;

    return SizedBox(
      height: height,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: MemSpace.sectionPadH,
          vertical: MemSpace.x2 + 2,
        ),
        child: Column(
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
