import 'package:flutter/material.dart';

import 'app_state.dart';

class AppScope extends InheritedWidget {
  const AppScope({super.key, required this.state, required super.child});

  final AppState state;

  static AppState of(BuildContext context) {
    final s = context.dependOnInheritedWidgetOfExactType<AppScope>();
    assert(s != null, 'AppScope missing');
    return s!.state;
  }

  @override
  bool updateShouldNotify(covariant AppScope oldWidget) =>
      oldWidget.state != state;
}
