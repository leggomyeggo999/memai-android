import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:home_widget/home_widget.dart';

import '../../app_scope.dart';
import '../../app_state.dart';
import '../../core/prompts/home_prompt_widget_sync.dart';
import '../../core/prompts/prompt_template.dart';
import '../capture/capture_page.dart';
import '../chat/chat_prompt_queue.dart';
import '../chat/mem_chat_page.dart';
import '../home/notes_page.dart';

/// Bottom navigation: **Notes · Capture · Chat**.
///
/// Each tab owns its own [Scaffold] so app bars stay contextual; settings opens
/// from the gear on every primary screen.
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
  }

  @override
  void dispose() {
    _app?.shellTabRequest.removeListener(_shellTabJumpListener);
    _widgetClickSub?.cancel();
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
    return Scaffold(
      body: IndexedStack(
        index: _index,
        children: [
          ..._tabsPrefix,
          MemChatPage(promptQueue: _promptQueue),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.article_outlined),
            selectedIcon: Icon(Icons.article),
            label: 'Notes',
          ),
          NavigationDestination(
            icon: Icon(Icons.add_circle_outline),
            selectedIcon: Icon(Icons.add_circle),
            label: 'Capture',
          ),
          NavigationDestination(
            icon: Icon(Icons.chat_bubble_outline),
            selectedIcon: Icon(Icons.chat_bubble),
            label: 'Chat',
          ),
        ],
      ),
    );
  }
}
