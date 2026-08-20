import 'package:flutter/material.dart';

import '../theme/mem_metrics.dart';

/// The "nothing here yet" surface (§3.5) — the app's answer to `#3`.
///
/// A 64 dp `primaryContainer` circle holding a 28 dp `onPrimaryContainer`
/// glyph, one headline, **one** line of body copy, and one CTA. Centred, max
/// width 320. `primaryContainer` is the *tonal* role here, not a selection —
/// selection is always `primary` fill (§2.12).
///
/// The CTA is wired by the caller, to `AppState.goToShellTab(…)` or a
/// `SettingsPage(focusSection: …)` push. An empty state without a way out is
/// just a blank screen with a picture on it.
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.headline,
    required this.body,
    this.ctaLabel,
    this.onCta,
    this.secondaryChips,
    this.firstRun = false,
  });

  final IconData icon;

  /// `titleMedium`, or `displaySmall` when [firstRun] is set.
  final String headline;

  /// `bodyMedium` `onSurfaceVariant` — **one** line of copy. Anything longer
  /// belongs in helper text next to the control it explains.
  final String body;

  final String? ctaLabel;
  final VoidCallback? onCta;

  /// Optional second tier — e.g. Chat's starter prompts. Each child is already
  /// its own ≥48 dp target.
  final List<Widget>? secondaryChips;

  /// First-run screens get the `displaySmall` headline; in-app empties (an
  /// empty filter, no search results) stay at `titleMedium`.
  final bool firstRun;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme cs = theme.colorScheme;
    final List<Widget>? chips = secondaryChips;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 320),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: MemInsets.pageH,
            vertical: MemSpace.x6,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Container(
                width: 64,
                height: 64,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: cs.primaryContainer,
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, size: 28, color: cs.onPrimaryContainer),
              ),
              const SizedBox(height: MemSpace.x4),
              Text(
                headline,
                textAlign: TextAlign.center,
                style: firstRun
                    ? theme.textTheme.displaySmall
                    : theme.textTheme.titleMedium,
              ),
              const SizedBox(height: MemSpace.x2),
              Text(
                body,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: cs.onSurfaceVariant,
                ),
              ),
              if (ctaLabel != null && onCta != null) ...<Widget>[
                const SizedBox(height: MemSpace.x6),
                FilledButton(onPressed: onCta, child: Text(ctaLabel!)),
              ],
              if (chips != null && chips.isNotEmpty) ...<Widget>[
                const SizedBox(height: MemSpace.x4),
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: MemSpace.chipGap,
                  runSpacing: MemSpace.chipGap,
                  children: chips,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
