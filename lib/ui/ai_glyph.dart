import 'package:flutter/material.dart';

import '../theme/mem_semantic_colors.dart';

/// The AI-provenance mark (§2.10).
///
/// One violet marks everything a model produced or is producing: the assistant
/// message header sparkle, the streaming caret, the "Processing in Mem…" chip
/// glyph, prompt-job chips in the Chat strip, and the Capture primary CTA.
/// User-authored content is **never** violet.
///
/// **This file is the only place `tertiary` / `aiAccent` is read outside
/// `lib/theme/`.** The mechanical audit in §6.4 greps for exactly that, so if
/// you need the violet somewhere, use this widget rather than reaching for the
/// colour — and if it is not one of the permitted sites, you do not need it.
class AiGlyph extends StatelessWidget {
  const AiGlyph({super.key, this.size = 14});

  /// 14 inline with text, 16 in a chip, 20 in a message header.
  final double size;

  @override
  Widget build(BuildContext context) {
    return Icon(
      Icons.auto_awesome,
      size: size,
      // The glyph is decorative — the copy next to it already says what the
      // model did, so it carries no semantic label of its own.
      color: memSemanticColorsOf(context).aiAccent,
    );
  }
}
