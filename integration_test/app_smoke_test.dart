import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:memai_android/app_scope.dart';
import 'package:memai_android/app_state.dart';
import 'package:memai_android/features/shell/mem_shell.dart';
import 'package:memai_android/main.dart';

/// Runs **on a device / emulator** (not the Dart VM unit-test harness):
/// `flutter test integration_test/app_smoke_test.dart`
///
/// NOTE: this test never calls [AppState.load], so `isHydrated` stays false and
/// the shell renders its pre-hydration state, which contains a REPEATING
/// skeleton animation. `pumpAndSettle` waits for the frame queue to drain and
/// therefore never returns against a repeating animation (it hung CI for the
/// full job timeout). Frames are advanced with fixed [_settle] pumps instead —
/// the assertions are unchanged.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  /// Advances a fixed number of frames instead of waiting for the frame queue
  /// to go idle. 12 x 100ms comfortably covers the NavigationBar's tab-switch
  /// transition (< 500ms) without ever blocking on a repeating animation.
  Future<void> settle(WidgetTester tester) async {
    for (int i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

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
    await settle(tester);

    await tester.tap(find.byIcon(Icons.chat_bubble_outline));
    await settle(tester);

    await tester.tap(find.byIcon(Icons.article_outlined));
    await settle(tester);

    // The shell survived a full lap of the tabs.
    expect(find.byType(MemShell), findsOneWidget);
    expect(find.byType(NavigationBar), findsOneWidget);
  });
}
