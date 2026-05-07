import 'dart:async';

import 'package:flutter/material.dart';

import 'app_scope.dart';
import 'app_state.dart';
import 'core/notifications/mem_job_notifications.dart';
import 'features/shell/mem_shell.dart';
import 'theme/mem_app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final state = AppState();
  MemJobNotifications.onOpenHomeTab = () => state.goToShellTab(0);
  runApp(AppScope(state: state, child: const MemDroidApp()));
  unawaited(_bootstrap(state));
}

Future<void> _bootstrap(AppState state) async {
  try {
    await state.load().timeout(const Duration(seconds: 10));
  } catch (_) {
    // Keep app usable even if startup storage/plugin calls are slow or fail.
  }
  try {
    await MemJobNotifications.ensureInitialized().timeout(
      const Duration(seconds: 8),
    );
  } catch (_) {
    // Notifications are optional for startup.
  }
}

class MemDroidApp extends StatelessWidget {
  const MemDroidApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MemDroid',
      theme: buildMemAppTheme(),
      home: const MemShell(),
    );
  }
}
