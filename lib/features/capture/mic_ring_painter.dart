import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';

import '../../theme/mem_metrics.dart';
import '../../theme/mem_semantic_colors.dart';

/// The three things the mic can be doing. The ring renders each one
/// differently **on purpose**: an honest control tells you which of these is
/// true without you having to read a label.
enum MicRingState {
  /// Nothing is running. Only the 1 dp `outline` boundary ring is drawn.
  idle,

  /// The recorder is live and the 120 ms amplitude stream is feeding [MicRing].
  recording,

  /// Audio is uploaded and a model is producing the transcript.
  transcribing,
}

/// A 12-bar radial amplitude ring — the replacement for the old
/// `LinearProgressIndicator` level meter.
///
/// **Why bars and not an arc.** A bar-count that grows around the circle, or a
/// bar that travels around it, is the universal grammar of *loading*. The whole
/// point of this control is that it must never read as a progress bar: it is a
/// live level meter. So every bar answers the **same** amplitude sample at the
/// **same** instant, and nothing rotates. The only per-bar difference is a
/// fixed weight table that gives the ring a silhouette instead of making it
/// breathe as a featureless donut.
///
/// The painter is pure: no assets, no gradients, no `saveLayer`, no shadows.
/// It draws one stroked circle plus twelve stroked lines per frame — which is
/// what keeps it inside the §2.11 per-frame budget while it repaints at the
/// amplitude sample rate.
class MicRingPainter extends CustomPainter {
  const MicRingPainter({
    required this.state,
    required this.level,
    required this.pulse,
    required this.ringColor,
    required this.barColor,
    required this.hairline,
  });

  /// Exactly twelve bars, per §4.4.
  static const int barCount = 12;

  /// Fixed per-bar weights. Static, symmetric, and never rotated — see the
  /// class doc for why that matters.
  static const List<double> _weights = <double>[
    1.00,
    0.72,
    0.88,
    0.58,
    0.96,
    0.66,
    1.00,
    0.66,
    0.96,
    0.58,
    0.88,
    0.72,
  ];

  final MicRingState state;

  /// The normalised amplitude, already lerped between samples by [MicRing].
  /// `((db + 60) / 60).clamp(0, 1)` is computed by the page, not here.
  final double level;

  /// 0..1 breathing phase, used by [MicRingState.transcribing] only.
  final double pulse;

  /// The boundary ring — `colorScheme.outline` (§2.7).
  final Color ringColor;

  /// `recording` while the mic is live, `aiAccent` while a model transcribes.
  final Color barColor;

  /// `hairlineWidth(context)`, snapped to whole physical pixels.
  final double hairline;

  @override
  void paint(Canvas canvas, Size size) {
    final Offset center = size.center(Offset.zero);
    final double radius = size.shortestSide / 2;
    if (radius <= 0) return;

    // The button's own 1 dp boundary, drawn in every state so the control keeps
    // its identity as a distinct interactive surface.
    canvas.drawCircle(
      center,
      radius - hairline / 2,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = hairline
        ..color = ringColor,
    );

    if (state == MicRingState.idle) return;

    // The bars live in an annulus between the glyph and the boundary, so they
    // never collide with either.
    final double innerRadius = radius * 0.50;
    final double minLength = radius * 0.06;
    final double maxLength = radius * 0.30;

    final Paint bar = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = math.max(2.0, radius * 0.065);

    final bool live = state == MicRingState.recording;
    final Color color = live
        ? barColor
        // Transcribing settles into the skeleton grammar: a 0.55 -> 1.0 opacity
        // pulse, no shimmer sweep (§2.11).
        : barColor.withValues(alpha: 0.55 + 0.45 * pulse.clamp(0.0, 1.0));

    for (int i = 0; i < barCount; i++) {
      final double angle = -math.pi / 2 + i * (2 * math.pi / barCount);
      final double weight = _weights[i];
      final double t = live
          ? (level.clamp(0.0, 1.0) * weight)
          // A steady silhouette while transcribing: the length stops reporting
          // anything, because there is nothing left to report.
          : 0.45 * weight;
      final double length = minLength + (maxLength - minLength) * t;
      final Offset direction = Offset(math.cos(angle), math.sin(angle));
      bar.color = color;
      canvas.drawLine(
        center + direction * innerRadius,
        center + direction * (innerRadius + length),
        bar,
      );
    }
  }

  @override
  bool shouldRepaint(covariant MicRingPainter oldDelegate) {
    return oldDelegate.state != state ||
        oldDelegate.level != level ||
        oldDelegate.pulse != pulse ||
        oldDelegate.ringColor != ringColor ||
        oldDelegate.barColor != barColor ||
        oldDelegate.hairline != hairline;
  }
}

/// Hosts [MicRingPainter] and owns the **single** [AnimationController] that
/// lerps between the 120 ms amplitude samples.
///
/// One controller does both jobs, because there is never more than one running:
/// while [MicRingState.recording] it runs once per sample (120 ms,
/// [MemMotion.emphasized]) to smooth the step between samples; while
/// [MicRingState.transcribing] it repeats in reverse ([MemMotion.skeleton],
/// [MemMotion.pulse]) to drive the breathing; while idle it is stopped, so an
/// unfocused Capture tab costs nothing.
///
/// [child] is the button face (fill + glyph). The ring is a **foreground**
/// painter so the bars and the boundary land on top of the fill.
class MicRing extends StatefulWidget {
  const MicRing({
    super.key,
    required this.state,
    required this.level,
    required this.child,
    this.size = MemSize.micButton,
  });

  final MicRingState state;

  /// The latest normalised amplitude sample, 0..1.
  final double level;

  /// The button face this ring is drawn over.
  final Widget child;

  /// 96 dp by default and deliberately not smaller: this is the app's
  /// eyes-free, one-handed, often-in-motion control.
  final double size;

  @override
  State<MicRing> createState() => _MicRingState();
}

class _MicRingState extends State<MicRing>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: MemMotion.micro,
    value: 1,
  );

  double _from = 0;
  double _to = 0;

  /// The smoothed level for the current frame.
  double get _current =>
      lerpDouble(_from, _to, MemMotion.emphasized.transform(_controller.value)) ??
      _to;

  @override
  void initState() {
    super.initState();
    _from = _to = widget.state == MicRingState.recording ? widget.level : 0;
    _applyState();
  }

  void _applyState() {
    switch (widget.state) {
      case MicRingState.transcribing:
        _controller.duration = MemMotion.skeleton;
        _controller.repeat(reverse: true);
      case MicRingState.recording:
        _controller.duration = MemMotion.micro;
        _controller.value = 1;
      case MicRingState.idle:
        _controller.stop();
        _controller.duration = MemMotion.micro;
        _controller.value = 1;
    }
  }

  @override
  void didUpdateWidget(covariant MicRing oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.state != widget.state) {
      _from = _to = widget.state == MicRingState.recording ? widget.level : 0;
      _applyState();
      return;
    }
    if (widget.state == MicRingState.recording &&
        widget.level != oldWidget.level) {
      // Lerp from wherever the last sample had got to, not from the last
      // sample's target — otherwise a fast run of samples snaps.
      _from = _current;
      _to = widget.level;
      _controller.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final MemSemanticColors semantics = memSemanticColorsOf(context);
    final double hairline = hairlineWidth(context);

    // `recording` is deliberately a different red from `colorScheme.error` — a
    // live mic is not a failure. `aiAccent` marks the transcript as
    // model-produced, which is the §4.4 rule for this state.
    final Color barColor = widget.state == MicRingState.transcribing
        ? semantics.aiAccent
        : semantics.recording;

    // Isolated so the amplitude repaint never dirties the page around it.
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _controller,
        builder: (BuildContext context, Widget? child) {
          return CustomPaint(
            foregroundPainter: MicRingPainter(
              state: widget.state,
              level: widget.state == MicRingState.recording ? _current : 0,
              pulse: widget.state == MicRingState.transcribing
                  ? MemMotion.pulse.transform(_controller.value)
                  : 0,
              ringColor: scheme.outline,
              barColor: barColor,
              hairline: hairline,
            ),
            child: child,
          );
        },
        child: SizedBox.square(dimension: widget.size, child: widget.child),
      ),
    );
  }
}
