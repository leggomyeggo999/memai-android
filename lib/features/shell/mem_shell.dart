import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:home_widget/home_widget.dart';

import '../../app_scope.dart';
import '../../app_state.dart';
import '../../core/prompts/home_prompt_widget_sync.dart';
import '../../core/prompts/prompt_template.dart';
import '../../theme/mem_metrics.dart';
import '../../ui/error_state.dart';
import '../../ui/skeleton.dart';
import '../../widgets/settings_launcher.dart';
import '../capture/capture_page.dart';
import '../chat/chat_prompt_queue.dart';
import '../chat/mem_chat_page.dart';
import '../home/notes_page.dart';
import '../settings/settings_page.dart';

/// How long the shell waits for [AppState.load] before it stops promising that
/// content is on the way (§4.1).
///
/// `_bootstrap` in `main.dart` swallows a failed `load()`, which leaves
/// `isHydrated == false` **forever** — the shell is the only place that can
/// notice. `load()` itself is capped at 10 s there, so a shell that gives up at
/// 8 s can still be overtaken by a slow-but-successful hydration: that is fine,
/// `isHydrated` is re-read on every rebuild and the gate disappears on its own.
const Duration _kHydrationWatchdog = Duration(seconds: 8);

/// One bottom-nav destination. The label doubles as the pre-hydration AppBar
/// title, so the chrome the user sees before the tabs exist names the same tab
/// the nav bar has selected.
class _ShellTab {
  const _ShellTab({
    required this.label,
    required this.icon,
    required this.selectedIcon,
  });

  final String label;
  final IconData icon;
  final IconData selectedIcon;
}

/// The three tabs, in `IndexedStack` order. The unselected glyphs are a
/// contract: the integration smoke test taps `Icons.article_outlined`,
/// `Icons.add_circle_outline`, and `Icons.chat_bubble_outline` by icon.
const List<_ShellTab> _kShellTabs = <_ShellTab>[
  _ShellTab(
    label: 'Notes',
    icon: Icons.article_outlined,
    selectedIcon: Icons.article,
  ),
  _ShellTab(
    label: 'Capture',
    icon: Icons.add_circle_outline,
    selectedIcon: Icons.add_circle,
  ),
  _ShellTab(
    label: 'Chat',
    icon: Icons.chat_bubble_outline,
    selectedIcon: Icons.chat_bubble,
  ),
];

/// Bottom navigation: **Notes · Capture · Chat**.
///
/// Each tab owns its own [Scaffold] so app bars stay contextual; settings opens
/// from the gear on every primary screen.
///
/// The [NavigationBar] is styled entirely by `navigationBarTheme` (§4.1) — the
/// only local chrome is a decoration-only top hairline. Tab switching is
/// instant: the whole point of the [IndexedStack] is a zero-cost,
/// state-preserving switch, so there is deliberately **no** cross-fade (§2.11).
class MemShell extends StatefulWidget {
  const MemShell({super.key});

  @override
  State<MemShell> createState() => _MemShellState();
}

class _MemShellState extends State<MemShell> {
  int _index = 0;
  final ChatPromptQueue _promptQueue = ChatPromptQueue();
  StreamSubscription<Uri?>? _widgetClickSub;
  AppState? _app;
  bool _shellTabListenerAdded = false;
  bool _homeWidgetHooked = false;
  bool _widgetDataSynced = false;

  /// Latches the first time [AppState.isHydrated] is true. From that build on,
  /// the [IndexedStack] exists and is **never** torn down again — Capture
  /// drafts, in-progress recordings, and all Chat state live inside it and must
  /// survive every tab switch for the rest of the process.
  bool _tabsMounted = false;

  /// Fires [_kHydrationWatchdog] after the shell's first frame; only relevant
  /// while hydration has not landed.
  Timer? _hydrationWatchdog;
  bool _hydrationTimedOut = false;
  bool _retryingHydration = false;

  late final VoidCallback _shellTabJumpListener = _onShellJump;

  void _onShellJump() {
    final app = _app;
    if (app == null || !mounted) return;
    final idx = app.shellTabRequest.value;
    if (idx == null || idx < 0 || idx > 2) return;
    setState(() => _index = idx);
    scheduleMicrotask(() {
      app.shellTabRequest.value = null;
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _app ??= AppScope.of(context);
    if (_app != null && !_shellTabListenerAdded) {
      _shellTabListenerAdded = true;
      _app!.shellTabRequest.addListener(_shellTabJumpListener);
    }
    if (!_homeWidgetHooked &&
        _app != null &&
        (Platform.isAndroid || Platform.isIOS)) {
      _homeWidgetHooked = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        HomeWidget.initiallyLaunchedFromHomeWidget().then(_handleWidgetUri);
        _widgetClickSub = HomeWidget.widgetClicked.listen(_handleWidgetUri);
      });
    }
    // AppState notifies through AppScope (an InheritedNotifier), so this runs
    // again the moment hydration lands — which is when the watchdog is retired.
    _syncHydrationWatchdog();
  }

  @override
  void dispose() {
    _app?.shellTabRequest.removeListener(_shellTabJumpListener);
    _widgetClickSub?.cancel();
    _hydrationWatchdog?.cancel();
    super.dispose();
  }

  void _handleWidgetUri(Uri? uri) {
    if (!mounted || uri == null) return;
    final app = _app ?? AppScope.of(context);
    if (uri.scheme == 'memai' && uri.host == 'open') {
      app.goToShellTab(0);
      return;
    }
    PromptTemplate? tpl;
    if (uri.scheme == 'memai' &&
        uri.host == 'prompt' &&
        uri.queryParameters.containsKey('templateId')) {
      final id = uri.queryParameters['templateId'];
      if (id != null) tpl = app.promptById(id);
    }
    if (tpl == null) return;
    app.goToShellTab(2);
    _promptQueue.enqueue(
      QueuedPromptJob(
        text: tpl.body,
        notificationTitle: tpl.title,
        notifyOnComplete: true,
      ),
    );
  }

  /// Arms the watchdog while we are un-hydrated, cancels it once we are.
  void _syncHydrationWatchdog() {
    final app = _app;
    if (app == null) return;
    if (app.isHydrated) {
      _hydrationWatchdog?.cancel();
      _hydrationWatchdog = null;
      return;
    }
    _hydrationWatchdog ??= Timer(_kHydrationWatchdog, () {
      _hydrationWatchdog = null;
      if (!mounted) return;
      final current = _app;
      if (current == null || current.isHydrated || _hydrationTimedOut) return;
      setState(() => _hydrationTimedOut = true);
    });
  }

  /// The terminal state's real recovery: run the same startup load again.
  ///
  /// `AppState.load()` is idempotent — it re-reads the vault, re-decodes the
  /// profiles, and flips `isHydrated` — so calling it a second time is safe.
  /// The messenger is captured before the await, and `mounted` is re-checked
  /// after it (§0.1 rule 7).
  Future<void> _retryHydration() async {
    final app = _app;
    if (app == null || _retryingHydration) return;
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    setState(() => _retryingHydration = true);
    try {
      await app.load();
    } catch (e) {
      if (mounted) errSnack(messenger, e);
    } finally {
      if (mounted) setState(() => _retryingHydration = false);
    }
  }

  static const _tabsPrefix = [
    NotesPage(),
    CapturePage(),
  ];

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    if (!_widgetDataSynced) {
      _widgetDataSynced = true;
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!mounted) return;
        await syncHomePromptWidget(
          all: app.promptTemplates,
          pinnedIds: app.pinnedTemplateIds,
        );
      });
    }
    // Latched, not conditional: once the tabs exist they stay, so no rebuild
    // can ever drop a Capture draft or a live recording.
    if (app.isHydrated) _tabsMounted = true;

    final ColorScheme scheme = Theme.of(context).colorScheme;

    return Scaffold(
      body: _tabsMounted
          ? IndexedStack(
              index: _index,
              children: [
                ..._tabsPrefix,
                MemChatPage(promptQueue: _promptQueue),
              ],
            )
          : _HydrationGate(
              tab: _kShellTabs[_index],
              // A retry puts the skeleton back: the app is loading again, and
              // saying so beats leaving a stale error under a dead button.
              failed: _hydrationTimedOut && !_retryingHydration,
              onRetry: _retryHydration,
            ),
      // Decoration only (§4.1): a top hairline, nothing else. It adds no
      // NavigationBar, wraps no destination, and — being a bare DecoratedBox —
      // absorbs no pointer events, so the three tab icons stay tappable.
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          border: Border(
            top: BorderSide(
              color: scheme.outline,
              width: hairlineWidth(context),
            ),
          ),
        ),
        child: NavigationBar(
          selectedIndex: _index,
          onDestinationSelected: (i) => setState(() => _index = i),
          destinations: <Widget>[
            for (final _ShellTab tab in _kShellTabs)
              NavigationDestination(
                icon: Icon(tab.icon),
                selectedIcon: Icon(tab.selectedIcon),
                label: tab.label,
              ),
          ],
        ),
      ),
    );
  }
}

/// What the shell shows before [AppState.isHydrated] — the tab's **normal
/// chrome** (AppBar + gear, with the shell's nav bar still below) over a
/// [SkeletonList], and, once the watchdog gives up, an actionable error.
///
/// Never a naked centred spinner: the pre-hydration shell is a first-run
/// surface, and a bare spinner that can hang forever is exactly the blank-shell
/// hole this fixes (§4.1, `#3`/`#4`).
class _HydrationGate extends StatelessWidget {
  const _HydrationGate({
    required this.tab,
    required this.failed,
    required this.onRetry,
  });

  final _ShellTab tab;

  /// True once hydration has been given up on. Swaps the skeleton for the
  /// terminal error.
  final bool failed;

  final VoidCallback onRetry;

  void _openSettings(BuildContext context) {
    // Same push as `settingsIconActions`: `const SettingsPage()`, no arguments,
    // on the nearest Navigator so the route covers the NavigationBar.
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const SettingsPage()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(tab.label),
        actions: settingsIconActions(context),
      ),
      body: failed ? _terminal(context) : _loading(),
    );
  }

  Widget _loading() {
    // Not scrollable — there is nothing to reach. The scroll view is only here
    // so a tall text scale cannot overflow the body.
    return const SingleChildScrollView(
      physics: NeverScrollableScrollPhysics(),
      padding: EdgeInsets.symmetric(vertical: MemSpace.x4),
      child: SkeletonList(rowCount: 6),
    );
  }

  Widget _terminal(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        return SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                ErrorState(
                  // main.dart's `_bootstrap` swallows whatever `load()` threw,
                  // so the shell genuinely does not know — and this resolves to
                  // the generic line rather than inventing a cause.
                  error: const _HydrationFailure(),
                  title: "Couldn't load your settings",
                  onRetry: onRetry,
                ),
                Padding(
                  padding: const EdgeInsets.only(bottom: MemSpace.x6),
                  child: TextButton(
                    onPressed: () => _openSettings(context),
                    child: const Text('Open Settings'),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Marker for "startup hydration never finished". [memErrorText] maps anything
/// it does not recognise to the generic user-facing line, which is the honest
/// answer here — the throwing object was swallowed at the bootstrap.
class _HydrationFailure implements Exception {
  const _HydrationFailure();
}
