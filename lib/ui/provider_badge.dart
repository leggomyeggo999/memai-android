import 'package:flutter/material.dart';

import '../core/llm/curated_chat_models.dart';
import '../theme/mem_metrics.dart';

/// A chat provider rendered as a 20 dp glyph plus its brand name.
///
/// The name comes from the existing-but-unused [chatProviderBrand], which is
/// what kills the raw `(openai)` strings in the Chat AppBar and the raw API
/// model ids in Settings.
///
/// The glyph is a stock Material icon — no new binary assets — and it is drawn
/// in `onSurfaceVariant`, **not** `tertiary`: a provider badge is a
/// configuration affordance, and violet is reserved for content a model
/// produced.
class ProviderBadge extends StatelessWidget {
  const ProviderBadge({
    super.key,
    required this.provider,
    this.showName = true,
  });

  /// The literal provider key: `openai`, `anthropic`, or `gemini`.
  final String provider;

  /// False renders the glyph alone — use it as an `AppRow.leading`.
  final bool showName;

  /// One distinct, neutral shape per provider.
  static IconData glyphFor(String provider) {
    switch (provider) {
      case 'openai':
        return Icons.hexagon_outlined;
      case 'anthropic':
        return Icons.change_history;
      case 'gemini':
        return Icons.diamond_outlined;
      default:
        return Icons.smart_toy_outlined;
    }
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final String brand = chatProviderBrand(provider);

    final Widget glyph = Icon(
      glyphFor(provider),
      size: 20,
      color: scheme.onSurfaceVariant,
    );

    if (!showName) {
      return Semantics(label: brand, child: glyph);
    }

    return ConstrainedBox(
      // Bounds the name so it ellipsizes rather than asserting when the badge
      // sits in an unbounded-width parent (an AppBar title row, a chip).
      constraints: const BoxConstraints(maxWidth: 160),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          glyph,
          const SizedBox(width: MemSpace.x2),
          Flexible(
            child: Text(
              brand,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelMedium?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
