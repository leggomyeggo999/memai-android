import 'package:flutter/material.dart';

import '../features/settings/settings_page.dart';
import 'error_state.dart';
import 'feedback.dart';

/// The async contract, codified (§3.15, and the ASYNC HYGIENE constraint).
///
/// Async hygiene here is **load-bearing**, not style. Three rules, and every
/// one of them has already caused a use-after-dispose crash in this codebase:
///
/// 1. **Capture `ScaffoldMessenger` before every `await`.** After an await the
///    element may be gone and `ScaffoldMessenger.of(context)` throws — so hold
///    the state object, not the context. [messengerOf] is that capture; call it
///    on the line *above* the first await, never after.
/// 2. **Check `mounted` after every `await`** before `setState`, a snackbar, or
///    a pop. [ifMounted] and [setStateIfMounted] make the check impossible to
///    forget; [navigatorOf] is the same capture-first discipline for pops.
/// 3. **Defer `AppScope` reads to post-frame in `initState` paths.**
///    [postFrame] does it and re-checks `mounted` inside the callback, matching
///    the hand-written pattern the screens already use.
///
/// Every redesigned screen mixes this in so the contract cannot quietly
/// regress. It adds no state and no lifecycle of its own — it is the pattern,
/// spelled once.
mixin AsyncPageMixin<T extends StatefulWidget> on State<T> {
  /// Capture the messenger **before** awaiting. Holding the returned state is
  /// safe across an await; re-reading it from `context` afterwards is not.
  ScaffoldMessengerState messengerOf() => ScaffoldMessenger.of(context);

  /// Capture the navigator **before** awaiting, for the same reason. Used by
  /// the paths that pop after a successful mutation (hard delete, sheets).
  NavigatorState navigatorOf() => Navigator.of(context);

  /// Run [fn] only if this State is still mounted. The guard after an await.
  void ifMounted(VoidCallback fn) {
    if (mounted) fn();
  }

  /// `setState` with the post-await guard folded in.
  void setStateIfMounted(VoidCallback fn) {
    if (mounted) setState(fn);
  }

  /// Defer [fn] to after the current frame, then run it only if still mounted.
  ///
  /// This is the `initState` escape hatch: `AppScope.of(context)` registers an
  /// inherited-widget dependency and must not run during `initState`, and the
  /// callback can outlive the element if the route is popped in the same frame.
  void postFrame(VoidCallback fn) {
    WidgetsBinding.instance.addPostFrameCallback((Duration _) {
      if (mounted) fn();
    });
  }

  /// A confirmation snackbar (§3.12). Copy is "Noun verb-past."
  void showMessage(
    String message, {
    String? actionLabel,
    VoidCallback? onAction,
  }) {
    if (!mounted) return;
    memSnack(
      messengerOf(),
      message,
      actionLabel: actionLabel,
      onAction: onAction,
    );
  }

  /// An error snackbar (§3.6), with this page's context threaded through so the
  /// "Open Settings" deep link can actually push a route. The raw error still
  /// goes to `MemErrorReporter` at the call site — this is presentation only.
  void showError(
    Object error, {
    VoidCallback? onRetry,
    SettingsSection? openSettings,
  }) {
    if (!mounted) return;
    errSnack(
      messengerOf(),
      error,
      onRetry: onRetry,
      openSettings: openSettings,
      context: context,
    );
  }
}
