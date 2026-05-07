import 'package:flutter/material.dart';

import 'app_state.dart';

/// Binds [AppState] to the tree so [notifyListeners] rebuilds dependents of
/// [AppScope.of] (via [InheritedNotifier]).
///
/// Prefer this over stacking [ListenableBuilder] + a separate [InheritedWidget]
/// keyed only on identity — that pairing can strand inherited dependents during
/// route/overlay teardown and trigger framework asserts.
class AppScope extends InheritedNotifier<AppState> {
  const AppScope({super.key, required AppState state, required super.child})
      : super(notifier: state);

  static AppState of(BuildContext context) {
    final s = context.dependOnInheritedWidgetOfExactType<AppScope>();
    assert(s != null, 'AppScope missing');
    final n = s!.notifier;
    assert(n != null, 'AppState missing');
    return n!;
  }
}
