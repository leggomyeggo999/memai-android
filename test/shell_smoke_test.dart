// A **headless mirror** of `integration_test/app_smoke_test.dart`.
//
// That file is the project's non-negotiable shell gate, but it needs a device or
// emulator. This file asserts the same shell contract on the Dart VM under
// `flutter test`, so the contract still has a guard on a machine with no
// Android target attached. It does not replace the integration test and must not
// be treated as permission to weaken it.
//
// Two deliberate differences from the integration test, both forced by the VM:
//
//  1. **No `pumpAndSettle`.** Neither test calls `AppState.load()`, so
//     `isHydrated` stays false and `MemShell` sits on `_HydrationGate`, whose
//     body is a `SkeletonList` driven by a *repeating* `AnimationController`.
//     `pumpAndSettle` cannot return while a repeating controller keeps
//     scheduling frames; it only unblocks once the 8 s `_kHydrationWatchdog`
//     fires and swaps the skeleton for the terminal `ErrorState` (verified: a
//     3 s settle throws, a 60 s settle succeeds). Explicit `pump`s assert the
//     same contract without hanging on that timer.
//
//     Worth knowing when reading the integration gate: because it never
//     hydrates either, what it actually exercises on a device is the shell
//     chrome and the nav bar — not `NotesPage` / `CapturePage` / `MemChatPage`,
//     which never mount. That is a property of the gate, not of this mirror.
//
//  2. **Plugin channels are mocked.** `shared_preferences` and
//     `flutter_secure_storage` have no VM implementation. They are stubbed with
//     in-memory handlers so that a pass means "the shell built and the taps
//     landed", never "a MissingPluginException got swallowed somewhere".
//
// The three unselected glyphs asserted here are a contract with
// `lib/features/shell/mem_shell.dart` (`_kShellTabs`). Note that a M3
// `NavigationDestination` only mounts *one* of `icon` / `selectedIcon` at a
// time, so each outlined glyph is asserted at the moment its tab is unselected —
// which is exactly the order the integration test taps them in.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:memai_android/app_scope.dart';
import 'package:memai_android/app_state.dart';
import 'package:memai_android/features/shell/mem_shell.dart';
import 'package:memai_android/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Plugin `MethodChannel`s the app can reach during shell construction.
/// Every one of them answers with an inert value instead of throwing.
const List<String> _kMockedChannels = <String>[
  // flutter_secure_storage (SecureVault).
  'plugins.it_nomads.com/flutter_secure_storage',
  // home_widget (syncHomePromptWidget / widget click stream). Guarded by
  // Platform.isAndroid in lib/, but mocked anyway so the guard is belt-and-braces.
  'home_widget',
  'home_widget/background',
  // flutter_local_notifications (MemJobNotifications).
  'dexterous.com/flutter/local_notifications',
  // package_info_plus.
  'dev.fluttercommunity.plus/package_info',
];

void _installChannelMocks() {
  final TestDefaultBinaryMessenger messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  for (final String name in _kMockedChannels) {
    messenger.setMockMethodCallHandler(MethodChannel(name), (
      MethodCall call,
    ) async {
      // `readAll` on the secure storage channel must be a map, not null.
      if (call.method == 'readAll') return <String, String>{};
      return null;
    });
  }
  // shared_preferences ships its own in-memory test store; using it is more
  // faithful than hand-decoding its pigeon codec.
  SharedPreferences.setMockInitialValues(<String, Object>{});
}

void _removeChannelMocks() {
  final TestDefaultBinaryMessenger messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  for (final String name in _kMockedChannels) {
    messenger.setMockMethodCallHandler(MethodChannel(name), null);
  }
}

/// Advances frames without requiring the scheduler to go idle.
Future<void> _pumpFrames(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 16));
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(_installChannelMocks);
  tearDown(_removeChannelMocks);

  testWidgets('bottom navigation switches tabs without crashing', (
    WidgetTester tester,
  ) async {
    final AppState state = AppState();
    addTearDown(state.dispose);

    await tester.pumpWidget(AppScope(state: state, child: const MemDroidApp()));
    await _pumpFrames(tester);

    // The two structural assertions the integration test makes, verbatim.
    expect(find.byType(MemShell), findsOneWidget);
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.byType(NavigationDestination), findsNWidgets(3));

    // Tab 0 (Notes) is selected, so Notes shows its *selected* glyph and the
    // other two show their outlined ones.
    expect(find.byIcon(Icons.article), findsOneWidget);
    expect(find.byIcon(Icons.add_circle_outline), findsOneWidget);
    expect(find.byIcon(Icons.chat_bubble_outline), findsOneWidget);

    // ---- Capture -----------------------------------------------------------
    expect(
      tester.widget<Icon>(find.byIcon(Icons.add_circle_outline)).icon,
      Icons.add_circle_outline,
    );
    await tester.tap(find.byIcon(Icons.add_circle_outline));
    await _pumpFrames(tester);
    expect(find.byIcon(Icons.add_circle), findsOneWidget);
    expect(find.text('Capture'), findsWidgets);
    expect(tester.takeException(), isNull);

    // ---- Chat --------------------------------------------------------------
    expect(find.byIcon(Icons.chat_bubble_outline), findsOneWidget);
    await tester.tap(find.byIcon(Icons.chat_bubble_outline));
    await _pumpFrames(tester);
    expect(find.byIcon(Icons.chat_bubble), findsOneWidget);
    expect(find.text('Chat'), findsWidgets);
    expect(tester.takeException(), isNull);

    // ---- back to Notes -----------------------------------------------------
    // Only reachable now: `article_outlined` is not in the tree while Notes is
    // the selected destination.
    expect(find.byIcon(Icons.article_outlined), findsOneWidget);
    await tester.tap(find.byIcon(Icons.article_outlined));
    await _pumpFrames(tester);
    expect(find.byIcon(Icons.article), findsOneWidget);
    expect(find.text('Notes'), findsWidgets);
    expect(tester.takeException(), isNull);

    // Still exactly one shell and one nav bar after three route-free swaps.
    expect(find.byType(MemShell), findsOneWidget);
    expect(find.byType(NavigationBar), findsOneWidget);
  });

  testWidgets('shell survives textScaleFactor 2.0 without overflowing', (
    WidgetTester tester,
  ) async {
    // 411 x 915 dp — the same phone the goldens are captured on. A larger test
    // surface would hide exactly the overflow this test is looking for.
    tester.view.devicePixelRatio = 2.0;
    tester.view.physicalSize = const Size(822, 1830);
    tester.platformDispatcher.textScaleFactorTestValue = 2.0;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    final AppState state = AppState();
    addTearDown(state.dispose);

    await tester.pumpWidget(AppScope(state: state, child: const MemDroidApp()));
    await _pumpFrames(tester);

    // A RenderFlex/RenderBox overflow is reported through FlutterError during
    // paint, which the test binding records; `takeException` is how we read it.
    expect(tester.takeException(), isNull);
    expect(
      MediaQuery.textScalerOf(tester.element(find.byType(MemShell))).scale(14),
      28.0,
      reason: 'the 2.0 scale must actually reach the shell subtree',
    );

    expect(find.byType(MemShell), findsOneWidget);
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.byIcon(Icons.add_circle_outline), findsOneWidget);

    // And the tabs still switch at that scale.
    await tester.tap(find.byIcon(Icons.add_circle_outline));
    await _pumpFrames(tester);
    expect(tester.takeException(), isNull);
    expect(find.byIcon(Icons.add_circle), findsOneWidget);

    await tester.tap(find.byIcon(Icons.chat_bubble_outline));
    await _pumpFrames(tester);
    expect(tester.takeException(), isNull);

    await tester.tap(find.byIcon(Icons.article_outlined));
    await _pumpFrames(tester);
    expect(tester.takeException(), isNull);
    expect(find.byType(NavigationBar), findsOneWidget);

    // Push past `_kHydrationWatchdog` (8 s) so the terminal state — ErrorState
    // stacked over an "Open Settings" TextButton, with the nav bar still below
    // it — is laid out at 2.0 as well. That is the taller of the two gate
    // bodies and the likelier place to overflow.
    await tester.pump(const Duration(seconds: 9));
    await _pumpFrames(tester);
    expect(tester.takeException(), isNull);
    expect(find.text('Try again'), findsOneWidget);
    expect(find.text('Open Settings'), findsOneWidget);
    expect(find.byType(NavigationBar), findsOneWidget);
  });
}
