import 'package:flutter/material.dart';

import 'app_scope.dart';
import 'app_state.dart';
import 'features/shell/mem_shell.dart';
import 'theme/mem_app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final state = AppState();
  await state.load();
  runApp(AppScope(state: state, child: const MemAiApp()));
}

class MemAiApp extends StatelessWidget {
  const MemAiApp({super.key});

  @override
  Widget build(BuildContext context) {
    final appState = AppScope.of(context);
    return ListenableBuilder(
      listenable: appState,
      builder: (context, _) {
        return MaterialApp(
          title: 'Mem AI',
          theme: buildMemAppTheme(),
          home: const MemShell(),
        );
      },
    );
  }
}
