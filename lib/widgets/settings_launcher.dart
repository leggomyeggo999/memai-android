import 'package:flutter/material.dart';

import '../app_scope.dart';
import '../app_state.dart';
import '../features/settings/settings_page.dart';
import '../ui/settings_gear_button.dart';

/// The shared settings entry point for every primary tab's `AppBar.actions`.
///
/// Contract (unchanged, three call sites depend on it): returns a
/// `List<Widget>` compatible with `AppBar.actions`, pushes `const
/// SettingsPage()` with **no arguments**, and targets the **nearest**
/// `Navigator` so the route covers the shell's NavigationBar.
///
/// New: the gear carries a setup-needed badge derived from [AppScope] —
/// `!hasMemRest || chatModels.isEmpty`, which is exactly [AppState.setupComplete]
/// inverted. Reading `AppScope` here registers the calling page as a dependent,
/// so the badge clears the moment setup completes.
List<Widget> settingsIconActions(BuildContext context) {
  final AppState app = AppScope.of(context);
  return <Widget>[
    SettingsGearButton(
      badge: !app.setupComplete,
      onPressed: () {
        Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => const SettingsPage()),
        );
      },
    ),
  ];
}
