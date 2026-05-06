import 'package:flutter/material.dart';

import '../features/settings/settings_page.dart';

List<Widget> settingsIconActions(BuildContext context) {
  return [
    IconButton(
      icon: const Icon(Icons.settings_outlined),
      onPressed: () {
        Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => const SettingsPage()),
        );
      },
    ),
  ];
}
