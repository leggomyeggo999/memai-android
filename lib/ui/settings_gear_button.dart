import 'package:flutter/material.dart';

import '../features/settings/settings_page.dart';
import '../theme/mem_metrics.dart';

/// The app's single settings entry point, present on every primary tab.
///
/// A 48 dp icon button with a `Settings` tooltip and an explicit
/// `Semantics(label: 'Settings')`. When [badge] is true it carries an 8 dp
/// `error` dot — the first-run signal that setup is incomplete
/// (`!hasMemRest || chatModels.isEmpty`, i.e. `!AppState.setupComplete`).
///
/// With [onPressed] omitted it pushes `const SettingsPage()` on the **nearest**
/// `Navigator`, so the route covers the shell's NavigationBar. That is the
/// contract `settingsIconActions` depends on, and it is why every tab can use
/// the bare `SettingsGearButton(badge: …)` form.
class SettingsGearButton extends StatelessWidget {
  const SettingsGearButton({super.key, this.badge = false, this.onPressed});

  /// Shows the 8 dp `error` dot.
  final bool badge;

  /// Overrides the default push. Leave null for the standard behaviour.
  final VoidCallback? onPressed;

  void _openSettings(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const SettingsPage()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;

    final Widget glyph = badge
        ? Stack(
            clipBehavior: Clip.none,
            children: <Widget>[
              const Icon(Icons.settings_outlined),
              PositionedDirectional(
                top: -1,
                end: -1,
                child: Container(
                  width: MemSize.statusDot,
                  height: MemSize.statusDot,
                  decoration: BoxDecoration(
                    color: scheme.error,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            ],
          )
        : const Icon(Icons.settings_outlined);

    return Semantics(
      label: 'Settings',
      value: badge ? 'Setup incomplete' : null,
      button: true,
      child: IconButton(
        tooltip: 'Settings',
        icon: glyph,
        onPressed: onPressed ?? () => _openSettings(context),
      ),
    );
  }
}
