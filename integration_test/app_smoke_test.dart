import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:memai_android/app_scope.dart';
import 'package:memai_android/app_state.dart';
import 'package:memai_android/features/shell/mem_shell.dart';
import 'package:memai_android/main.dart';

/// Runs **on a device / emulator** (not the Dart VM unit-test harness):
/// `flutter test integration_test/app_smoke_test.dart`
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('bottom navigation switches tabs without crashing', (
    WidgetTester tester,
  ) async {
    final state = AppState();
    await tester.pumpWidget(
      AppScope(state: state, child: const MemDroidApp()),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byType(MemShell), findsOneWidget);
    expect(find.byType(NavigationBar), findsOneWidget);

    await tester.tap(find.byIcon(Icons.add_circle_outline));
    await tester.pumpAndSettle(const Duration(seconds: 2));

    await tester.tap(find.byIcon(Icons.chat_bubble_outline));
    await tester.pumpAndSettle(const Duration(seconds: 2));

    await tester.tap(find.byIcon(Icons.article_outlined));
    await tester.pumpAndSettle(const Duration(seconds: 2));
  });
}
