// Chat (§4.5). Presentation rebuilt on the app's own tokens; the send pipeline
// is byte-for-byte the pipeline that was here before.
//
// What changed: `ChatTheme.dark()` is gone (it clashed with the app theme and
// made light mode impossible), assistant turns are full-width blocks with an
// AI-provenance header instead of bubbles, errors render as error rows instead
// of fake assistant prose, background prompt-job work is visible above the
// composer, and the AppBar's debug-ish `'<name> (<provider>)'` string became a
// real model switcher that announces the conversation swap.
//
// What did NOT change, and must not: the send order, the in-place rewrite of
// the pending bubble under the same id, the byte-identical `'…'` sentinel, the
// persist filter (which gains exactly one clause), wholesale provider-history
// replacement, the HTTP-400 reset, the `'Error: '` prefix, per-profile session
// persistence with persist-old-then-restore, the 150 ms prompt-job poll, the
// notification on both success and failure, the `'chat'` / `'prompt_job'`
// telemetry contexts, and every listener/dispose pairing.
//
// There is deliberately **no Stop button** (§4.5, NEXT-2): none of the three
// provider paths in `lib/core/llm/` exposes a `CancelToken` or a way to cancel
// a stream, so the affordance would be a lie. The send button becomes a
// disabled `InlineSpinner` while a reply is in flight.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_chat_core/flutter_chat_core.dart';
import 'package:flutter_chat_ui/flutter_chat_ui.dart';
import 'package:uuid/uuid.dart';

import '../../app_scope.dart';
import '../../app_state.dart';
import '../../core/chat/chat_session_store.dart';
import '../../core/llm/anthropic_mem_agent.dart';
import '../../core/llm/chat_error_utils.dart';
import '../../core/llm/chat_model_profile.dart';
import '../../core/llm/gemini_mem_agent.dart';
import '../../core/llm/mem_tool_runner.dart';
import '../../core/llm/openai_mem_agent.dart';
import '../../core/mcp/mcp_session_client.dart';
import '../../core/mem/mem_api_client.dart';
import '../../core/notifications/mem_job_notifications.dart';
import '../../core/prompts/prompt_template.dart';
import '../../core/telemetry/mem_error_reporter.dart';
import '../../theme/mem_metrics.dart';
import '../../ui/ai_glyph.dart';
import '../../ui/app_list_section.dart';
import '../../ui/async_page_mixin.dart';
import '../../ui/chip_strip.dart';
import '../../ui/date_labels.dart';
import '../../ui/empty_state.dart';
import '../../ui/feedback.dart';
import '../../ui/hairline.dart';
import '../../ui/inline_spinner.dart';
import '../../widgets/settings_launcher.dart';
import '../settings/settings_page.dart';
import 'chat_message_builders.dart';
import 'chat_prompt_queue.dart';
import 'model_switcher_sheet.dart';

// Author ids. Aliased to the constants WP-S exported so the page and the
// message builders can never drift apart — these are persistence contracts,
// not copy.
const _kUserId = kMemChatUserAuthorId;
const _kAssistantId = kMemChatAssistantAuthorId;

/// Author id for the centred system rows (§4.5): model switch, session
/// restore. Rows carrying it are stripped by the persist filter and are
/// **never** added to any provider history.
const _kSystemId = kMemChatSystemAuthorId;

const _systemPrompt =
    'You have tools to read and search the user '
    'Mem knowledge base. Always use tools instead of guessing. To update a note, '
    'call get_note first to read the current version number, then update_note with '
    'that exact version. Be concise.';

/// Starter prompts on the empty conversation (§4.5 item 7). They are **real**
/// prompts: tapping one sends it through the unchanged pipeline.
const List<String> _kStarterPrompts = <String>[
  'What did I write down this week?',
  'Summarise my most recent note.',
  'What am I forgetting to follow up on?',
];

/// Job chips never grow past this, so one long title cannot eat the strip.
const double _kJobChipMaxWidth = 180;

/// Starter-prompt chips are bounded to the `EmptyState`'s 320 dp column minus
/// the chip's own padding.
const double _kStarterChipMaxWidth = 240;

/// Persistent job-status row height (§4.5 item 4). A minimum, not a fixed
/// height — the row grows with the text scale rather than clipping.
const double _kJobStatusMinHeight = 40;

/// Composer field height (§4.5 item 6): `bodyLarge`'s 26 dp line plus the
/// vertical content padding below.
const double _kComposerFieldPadV = MemSpace.x3;

/// The filled send button's visual size; the tap target around it is 48 dp.
const double _kSendButtonSize = 44;

class MemChatPage extends StatefulWidget {
  const MemChatPage({super.key, required this.promptQueue});

  final ChatPromptQueue promptQueue;

  @override
  State<MemChatPage> createState() => _MemChatPageState();
}

class _MemChatPageState extends State<MemChatPage> with AsyncPageMixin {
  late final InMemoryChatController _chat;
  final List<Map<String, dynamic>> _openAiHist = [
    {'role': 'system', 'content': _systemPrompt},
  ];
  final List<Map<String, dynamic>> _anthropicHist = [];
  final List<Map<String, dynamic>> _geminiHist = [];
  bool _busy = false;
  final List<QueuedPromptJob> _queuedPromptRuns = [];
  bool _drainingPromptRuns = false;

  final _sessionStore = ChatSessionStore();
  String? _sessionProfileId;
  AppState? _app;
  VoidCallback? _appListener;

  // ---- Presentation state (new; none of it feeds the pipeline) -------------

  /// The composer field. The library `Composer` is not used (it wraps itself in
  /// a per-frame `BackdropFilter`, banned by §2.11), so the page owns the input.
  final TextEditingController _input = TextEditingController();
  final FocusNode _inputFocus = FocusNode();

  /// Id of the bubble currently receiving stream deltas; drives the streaming
  /// caret. Set after the pending bubble is inserted, cleared in the `finally`.
  String? _streamingId;

  /// Ids that failed this session. Pins the error-row classification so it does
  /// not rely on the `'Error'` text heuristic alone.
  final Set<String> _failedMessageIds = <String>{};

  /// Ids whose run was declared dead by the stall watchdog. A late delta or a
  /// late terminal reply for one of these must not overwrite the error row the
  /// user is already looking at (and may already have retried from).
  final Set<String> _abandonedPendingIds = <String>{};

  /// The 90 s (`MemMotion.streamStall`) watchdog. Re-armed on every delta.
  Timer? _stallTimer;

  /// Monotonic run token. Only the newest run is allowed to clear `_busy` /
  /// cancel the watchdog, so a stalled run that completes late cannot unlock
  /// the composer underneath the run the user started after it.
  int _runSeq = 0;

  /// Title of the prompt job in flight, for the status row. Null when the run
  /// is a plain user send.
  String? _jobLabel;

  /// Template id of the job in flight, so its chip can show a spinner.
  String? _jobTemplateId;

  /// True while a prompt job is parked in the 150 ms poll waiting for the
  /// current reply to finish. "Waiting" and "Running" are different facts and
  /// the row says which one it is.
  bool _jobWaiting = false;

  @override
  void initState() {
    super.initState();
    _chat = InMemoryChatController();
    widget.promptQueue.addListener(_onPromptQueueChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _bindAppListener();
      unawaited(
        _switchSessionProfile(AppScope.of(context).activeModelId, initial: true),
      );
    });
  }

  void _bindAppListener() {
    final app = AppScope.of(context);
    _app = app;
    if (_appListener != null) return;
    _appListener = () {
      final id = app.activeModelId;
      if (id != _sessionProfileId) {
        unawaited(_switchSessionProfile(id));
      }
    };
    app.addListener(_appListener!);
  }

  Future<void> _switchSessionProfile(String? profileId, {bool initial = false}) async {
    if (!initial && _sessionProfileId != null) {
      await _persistSession();
    }
    _sessionProfileId = profileId;
    if (profileId == null || !mounted) {
      await _chat.setMessages([]);
      return;
    }
    final ChatSessionSnapshot? restored = await _restoreSession(profileId);
    // The swap is announced, never silent (`#2`, §5.5) — but only for a real
    // switch. The initial bind is not a switch.
    if (initial || !mounted) return;
    await _announceModelSwitch(profileId, restored);
  }

  Future<ChatSessionSnapshot?> _restoreSession(String profileId) async {
    final snap = await _sessionStore.load(profileId);
    if (!mounted) return null;

    if (snap == null) {
      _openAiHist
        ..clear()
        ..add({'role': 'system', 'content': _systemPrompt});
      _anthropicHist.clear();
      _geminiHist.clear();
      await _chat.setMessages([]);
      return null;
    }

    _openAiHist
      ..clear()
      ..addAll(
        snap.openAiHist.isEmpty
            ? [
                {'role': 'system', 'content': _systemPrompt},
              ]
            : snap.openAiHist,
      );
    _anthropicHist
      ..clear()
      ..addAll(snap.anthropicHist);
    _geminiHist
      ..clear()
      ..addAll(snap.geminiHist);
    await _chat.setMessages(snap.uiMessages);
    return snap;
  }

  /// Inserts the centred system row naming the model that was just switched to,
  /// plus the date the restored conversation was saved — the first use of
  /// `ChatSessionSnapshot.savedAt`.
  ///
  /// The row is a `Message.text` authored by [_kSystemId], so the single added
  /// persist-filter clause is what keeps it out of `ChatSessionStore`. It is
  /// never appended to `_openAiHist` / `_anthropicHist` / `_geminiHist`.
  Future<void> _announceModelSwitch(
    String profileId,
    ChatSessionSnapshot? restored,
  ) async {
    final ChatModelProfile? profile = _profileById(profileId);
    final String name = profile?.displayName ?? 'this model';
    final String detail = restored == null
        ? 'new conversation'
        : 'conversation restored from ${memDayLabel(restored.savedAt)}';
    await _chat.insertMessage(
      memChatSystemMessage(
        id: const Uuid().v4(),
        text: 'Switched to $name — $detail',
      ),
    );
  }

  Future<void> _persistSession() async {
    final profileId = _sessionProfileId;
    if (profileId == null) return;

    final ui = _chat.messages.where((m) {
      if (m is! TextMessage) return false;
      final t = m.text.trim();
      // The one added clause is `m.authorId != _kSystemId` (§4.5). The sentinel
      // comparison is the same byte-identical U+2026 it always was — imported
      // rather than retyped so it cannot drift.
      return t.isNotEmpty &&
          t != kMemChatPendingSentinel &&
          m.authorId != _kSystemId;
    }).toList();

    await _sessionStore.save(
      profileId: profileId,
      uiMessages: ui,
      openAiHist: List<Map<String, dynamic>>.from(_openAiHist),
      anthropicHist: List<Map<String, dynamic>>.from(_anthropicHist),
      geminiHist: List<Map<String, dynamic>>.from(_geminiHist),
    );
  }

  @override
  void dispose() {
    // Reads `_chat.messages` synchronously before the first await, so it must
    // stay ahead of `_chat.dispose()`.
    unawaited(_persistSession());
    _stallTimer?.cancel();
    if (_appListener != null) {
      _app?.removeListener(_appListener!);
    }
    widget.promptQueue.removeListener(_onPromptQueueChanged);
    _input.dispose();
    _inputFocus.dispose();
    _chat.dispose();
    super.dispose();
  }

  void _onPromptQueueChanged() {
    final jobs = widget.promptQueue.drainAll();
    if (jobs.isEmpty || !mounted) return;
    _queuedPromptRuns.addAll(jobs);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(_drainQueuedPromptRuns());
    });
  }

  Future<void> _drainQueuedPromptRuns() async {
    if (_drainingPromptRuns || !mounted) return;
    _drainingPromptRuns = true;
    while (_queuedPromptRuns.isNotEmpty && mounted) {
      final job = _queuedPromptRuns.removeAt(0);
      await _runUserPrompt(
        job.text,
        notifyTitle: job.notifyOnComplete ? job.notificationTitle : null,
        fromPromptJob: true,
        jobLabel: job.notificationTitle,
      );
    }
    _drainingPromptRuns = false;
  }

  Future<User?> _resolve(UserID id) async {
    if (id == _kUserId) {
      return const User(id: _kUserId, name: 'You');
    }
    if (id == _kSystemId) {
      return const User(id: _kSystemId, name: 'Mem');
    }
    return const User(id: _kAssistantId, name: 'Assistant');
  }

  ChatModelProfile? _activeProfile(BuildContext context) {
    final app = AppScope.of(context);
    if (app.activeModelId == null) return null;
    try {
      return app.chatModels.firstWhere((m) => m.id == app.activeModelId);
    } catch (_) {
      return app.chatModels.isEmpty ? null : app.chatModels.first;
    }
  }

  /// Same fall-back-to-first-model rule as [_activeProfile], but resolved off
  /// the cached `_app` so it is safe to call from an async continuation.
  ChatModelProfile? _profileById(String id) {
    final AppState? app = _app;
    if (app == null) return null;
    for (final ChatModelProfile m in app.chatModels) {
      if (m.id == id) return m;
    }
    return app.chatModels.isEmpty ? null : app.chatModels.first;
  }

  Future<void> _handleSendFromInput(String text) async {
    await _runUserPrompt(text.trim(), notifyTitle: null);
  }

  Future<void> _runFromTemplate(PromptTemplate t) async {
    await _runUserPrompt(
      t.body,
      notifyTitle: null,
      jobLabel: t.title,
      jobTemplateId: t.id,
    );
  }

  /// Wraps the pipeline with the job-status bookkeeping the status row and the
  /// chip spinner read. The label is set before the busy gate so a job parked
  /// in the 150 ms poll is visible, and cleared in a `finally` so no early
  /// return can strand it.
  Future<void> _runUserPrompt(
    String trimmed, {
    String? notifyTitle,
    bool fromPromptJob = false,
    String? jobLabel,
    String? jobTemplateId,
  }) async {
    if (jobLabel != null) {
      setStateIfMounted(() {
        _jobLabel = jobLabel;
        _jobTemplateId = jobTemplateId;
      });
    }
    try {
      await _runPipeline(
        trimmed,
        notifyTitle: notifyTitle,
        fromPromptJob: fromPromptJob,
      );
    } finally {
      if (jobLabel != null) {
        setStateIfMounted(() {
          _jobLabel = null;
          _jobTemplateId = null;
          _jobWaiting = false;
        });
      }
    }
  }

  /// The send pipeline. **Order is a contract:** trim → busy gate → profile
  /// gate → backend gate → vault key gate → insert user msg → insert pending
  /// `'…'` bubble → `refreshMcpIfNeeded` → `MemToolRunner` (REST preferred; MCP
  /// only when `!hasMemRest && mcpConnected`) → `hasBackend` → dispatch on the
  /// literal `'openai' | 'anthropic' | 'gemini'`.
  Future<void> _runPipeline(
    String trimmed, {
    String? notifyTitle,
    bool fromPromptJob = false,
  }) async {
    final messenger = messengerOf();
    if (trimmed.isEmpty) return;
    if (_busy) {
      if (fromPromptJob) {
        setStateIfMounted(() => _jobWaiting = true);
        while (_busy && mounted) {
          await Future<void>.delayed(const Duration(milliseconds: 150));
        }
        setStateIfMounted(() => _jobWaiting = false);
      } else {
        memSnack(messenger, 'Wait for the current reply to finish.');
        return;
      }
    }
    if (!mounted) return;

    final app = AppScope.of(context);
    final profile = _activeProfile(context);
    if (profile == null) {
      memSnack(messenger, 'Add a chat model in Settings and select it.');
      return;
    }

    if (!app.hasMemRest && !app.mcpConnected) {
      memSnack(
        messenger,
        'Connect Mem via REST API key and/or MCP OAuth so tools can reach your notes.',
      );
      return;
    }

    String? llmKey;
    try {
      llmKey = await app.vault.getLlmApiKey(profile.id);
    } catch (_) {}
    if (llmKey == null || llmKey.isEmpty) {
      if (!mounted) return;
      memSnack(messenger, 'Missing LLM API key for this model profile.');
      return;
    }
    // Async hygiene: the vault read is an await, so re-check before the first
    // setState of the run.
    if (!mounted) return;

    // Telemetry context, resolved once and used by both the watchdog and the
    // catch block so the two can never disagree.
    final String errorContext = fromPromptJob || notifyTitle != null
        ? 'prompt_job'
        : 'chat';
    final int runToken = ++_runSeq;

    setState(() => _busy = true);
    final uid = const Uuid().v4();
    await _chat.insertMessage(
      Message.text(
        id: uid,
        authorId: _kUserId,
        text: trimmed,
        createdAt: DateTime.now(),
      ),
    );

    final pendingId = const Uuid().v4();
    await _chat.insertMessage(
      Message.text(
        id: pendingId,
        authorId: _kAssistantId,
        text: kMemChatPendingSentinel,
        createdAt: DateTime.now(),
      ),
    );
    setStateIfMounted(() => _streamingId = pendingId);
    _armStallWatchdog(pendingId, profile, errorContext);

    try {
      await app.refreshMcpIfNeeded();

      MemApiClient? memApi;
      if (app.hasMemRest) {
        memApi = MemApiClient(apiKey: app.memApiKey!);
      }
      McpSessionClient? mcp;
      if (!app.hasMemRest && app.mcpConnected) {
        final t = await app.vault.getMcpAccessToken();
        if (t != null && t.isNotEmpty) {
          mcp = McpSessionClient(accessToken: t);
        }
      }

      final runner = MemToolRunner(api: memApi, mcp: mcp);
      if (!runner.hasBackend) {
        throw StateError('No Mem backend resolved');
      }

      String reply;
      Future<void> streamBubble(String accumulated) async {
        if (!mounted) return;
        // A delta for a run the watchdog already buried must not resurrect it.
        if (_abandonedPendingIds.contains(pendingId)) return;
        // Every token restarts the 90 s clock.
        _armStallWatchdog(pendingId, profile, errorContext);
        final old = _pendingById(pendingId);
        if (old == null) return;
        final display = accumulated.isEmpty
            ? kMemChatPendingSentinel
            : accumulated;
        await _chat.updateMessage(
          old,
          Message.text(
            id: pendingId,
            authorId: _kAssistantId,
            text: display,
            createdAt: DateTime.now(),
          ),
        );
      }

      if (profile.provider == 'openai') {
        final agent = OpenAiMemAgent(
          apiKey: llmKey,
          model: profile.model,
          runner: runner,
        );
        final res = await agent.runConversation(
          priorOpenAiMessages: _openAiHist,
          userText: trimmed,
          onAssistantTextDelta: streamBubble,
        );
        _openAiHist
          ..clear()
          ..addAll(res.openAiHistory);
        reply = res.reply;
      } else if (profile.provider == 'anthropic') {
        final agent = AnthropicMemAgent(
          apiKey: llmKey,
          model: profile.model,
          runner: runner,
        );
        final res = await agent.runConversation(
          system: _systemPrompt,
          priorAnthropicMessages: _anthropicHist,
          userText: trimmed,
          onAssistantTextDelta: streamBubble,
        );
        _anthropicHist
          ..clear()
          ..addAll(res.anthropicHistory);
        reply = res.reply;
      } else if (profile.provider == 'gemini') {
        final agent = GeminiMemAgent(
          apiKey: llmKey,
          model: profile.model,
          runner: runner,
        );
        final res = await agent.runConversation(
          system: _systemPrompt,
          priorGeminiContents: _geminiHist,
          userText: trimmed,
          onAssistantTextDelta: streamBubble,
        );
        _geminiHist
          ..clear()
          ..addAll(res.geminiContents);
        reply = res.reply;
      } else {
        throw StateError('Unsupported provider: ${profile.provider}');
      }

      final pending = _pendingById(pendingId);
      if (pending != null && !_abandonedPendingIds.contains(pendingId)) {
        await _chat.updateMessage(
          pending,
          Message.text(
            id: pendingId,
            authorId: _kAssistantId,
            text: reply,
            createdAt: DateTime.now(),
          ),
        );
      }

      if (notifyTitle != null) {
        await MemJobNotifications.showPromptJobFinished(
          title: notifyTitle,
          ok: true,
          detail: reply,
        );
      }
    } catch (e, st) {
      final ctx = errorContext;
      final details = formatChatError(e, profile: profile, context: ctx);
      if (details.httpStatus == 400) {
        _resetProviderHistory(profile.provider);
      }
      MemErrorReporter.report(
        message: details.userMessage,
        stack: st.toString(),
        context: ctx,
        provider: profile.provider,
        httpStatus: details.httpStatus,
      );
      await _failMessage(pendingId, details.userMessage);
      if (notifyTitle != null) {
        await MemJobNotifications.showPromptJobFinished(
          title: notifyTitle,
          ok: false,
          detail: details.userMessage,
        );
      }
    } finally {
      // Only the newest run owns the busy flag and the watchdog. Without this,
      // a stalled run completing late would unlock the composer while the run
      // the user started after it is still streaming.
      if (runToken == _runSeq) {
        _stallTimer?.cancel();
        _stallTimer = null;
        if (mounted) {
          setState(() {
            _busy = false;
            _streamingId = null;
          });
          unawaited(_persistSession());
        }
      }
    }
  }

  void _resetProviderHistory(String provider) {
    switch (provider) {
      case 'openai':
        _openAiHist
          ..clear()
          ..add({'role': 'system', 'content': _systemPrompt});
        break;
      case 'anthropic':
        _anthropicHist.clear();
        break;
      case 'gemini':
        _geminiHist.clear();
        break;
    }
  }

  Message? _pendingById(String messageId) {
    for (final m in _chat.messages) {
      if (m.id == messageId) return m;
    }
    return null;
  }

  Future<void> _failMessage(String messageId, String err) async {
    if (_abandonedPendingIds.contains(messageId)) return;
    final pending = _pendingById(messageId);
    if (pending == null) return;
    final display = err.startsWith('Error') ? err : 'Error: $err';
    await _chat.updateMessage(
      pending,
      Message.text(
        id: messageId,
        authorId: _kAssistantId,
        text: display,
        createdAt: DateTime.now(),
      ),
    );
    // Pins the error-row classification for this session; a restored session
    // falls back to the `'Error'` prefix the line above guarantees.
    _failedMessageIds.add(messageId);
  }

  // ---- Streaming death path (§4.5, mandatory) -----------------------------

  void _armStallWatchdog(
    String pendingId,
    ChatModelProfile profile,
    String errorContext,
  ) {
    _stallTimer?.cancel();
    _stallTimer = Timer(MemMotion.streamStall, () {
      unawaited(_onStreamStalled(pendingId, profile, errorContext));
    });
  }

  /// No token for 90 s: convert the pending bubble into an error row with a
  /// Retry, rather than leaving an animation that never ends and offers no way
  /// out.
  ///
  /// It routes through [_failMessage] precisely so the persisted `'Error: '`
  /// prefix contract still holds. `_busy` is released here because a Retry the
  /// busy gate would reject is not a recovery.
  Future<void> _onStreamStalled(
    String pendingId,
    ChatModelProfile profile,
    String errorContext,
  ) async {
    if (!mounted || _abandonedPendingIds.contains(pendingId)) return;
    MemErrorReporter.report(
      message:
          'Chat stream stalled: no token for '
          '${MemMotion.streamStall.inSeconds}s',
      context: errorContext,
      provider: profile.provider,
    );
    await _failMessage(
      pendingId,
      'The reply stopped arriving. Tap retry to ask again.',
    );
    if (!mounted) return;
    setState(() {
      // Marked after the rewrite, so the rewrite itself is not suppressed.
      _abandonedPendingIds.add(pendingId);
      if (_streamingId == pendingId) _streamingId = null;
      _busy = false;
    });
  }

  // ---- Message actions (§4.5 item 5, fixes `#15`) -------------------------

  /// Re-sends the user message preceding [failed] through the unchanged
  /// pipeline. There is no second send path.
  void _retryFailedTurn(TextMessage failed) {
    final List<Message> all = _chat.messages;
    final int ix = all.indexWhere((Message m) => m.id == failed.id);
    final int from = (ix < 0 ? all.length : ix) - 1;
    String? userText;
    for (int i = from; i >= 0; i--) {
      final Message m = all[i];
      if (m is TextMessage && m.authorId == _kUserId) {
        userText = m.text;
        break;
      }
    }
    if (userText == null || userText.trim().isEmpty) {
      showMessage('Nothing to retry.');
      return;
    }
    unawaited(_runUserPrompt(userText.trim(), notifyTitle: null));
  }

  /// Copy / Retry / Select text — the replacement for the old long-press that
  /// silently wrote to the clipboard (`#15`).
  void _showMessageMenu(BuildContext anchorContext, TextMessage message) {
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(anchorContext);
    final bool isUser = message.authorId == _kUserId;
    final bool canRetry = !isUser && message.authorId != _kSystemId;
    // The `'Error: '` prefix is storage, not copy — never hand it to the user.
    final String text = isUser
        ? message.text
        : memChatStripErrorPrefix(message.text);

    showModalBottomSheet<void>(
      context: anchorContext,
      showDragHandle: true,
      builder: (BuildContext sheetContext) => SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            ListTile(
              leading: const Icon(Icons.copy_all_outlined),
              title: const Text('Copy'),
              onTap: () {
                Navigator.pop(sheetContext);
                Clipboard.setData(ClipboardData(text: text));
                memSnack(messenger, 'Message copied.');
              },
            ),
            if (canRetry)
              ListTile(
                leading: const Icon(Icons.refresh),
                title: const Text('Retry'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _retryFailedTurn(message);
                },
              ),
            ListTile(
              leading: const Icon(Icons.text_fields),
              title: const Text('Select text'),
              onTap: () {
                Navigator.pop(sheetContext);
                _showSelectableText(text);
              },
            ),
            const SizedBox(height: MemSpace.x2),
          ],
        ),
      ),
    );
  }

  void _showSelectableText(String text) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (BuildContext sheetContext) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(sheetContext).bottom + MemSpace.x5,
        ),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(sheetContext).height * 0.6,
          ),
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: MemInsets.pageH),
            child: SelectableText(
              text,
              style: Theme.of(sheetContext).textTheme.bodyLarge,
            ),
          ),
        ),
      ),
    );
  }

  void _showJobsSheet(AppState app) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetCtx) => _PromptJobsPickerSheet(
        app: app,
        onPick: (t) {
          // Pop BEFORE running — the sheet must not outlive the tap.
          Navigator.pop(sheetCtx);
          _runFromTemplate(t);
        },
      ),
    );
  }

  void _openSettings(SettingsSection section) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (BuildContext _) => SettingsPage(focusSection: section),
      ),
    );
  }

  // ---- Composer -----------------------------------------------------------

  void _submitFromComposer() {
    final String text = _input.text;
    if (text.trim().isEmpty) return;
    // Only clear on a send that can actually proceed: the busy path aborts with
    // a snackbar and the draft must survive it.
    if (!_busy) _input.clear();
    unawaited(_handleSendFromInput(text));
  }

  // ---- Build --------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final AppState app = AppScope.of(context);
    final ChatModelProfile? profile = _activeProfile(context);
    final List<PromptTemplate> jobs = app.promptTemplates;
    final List<PromptTemplate> stripJobs = jobs.length <= 12
        ? jobs
        : jobs.take(12).toList();

    // The switcher strip grows with the text scale instead of clipping inside
    // a fixed-height AppBar bottom.
    final double textScale = MediaQuery.textScalerOf(context).scale(12) / 12;
    final double switcherHeight =
        MemSize.touchTarget * textScale.clamp(1.0, 1.6).toDouble() +
        MemSpace.x2;

    final Widget? statusRow = _buildJobStatusRow(theme, scheme);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Chat'),
        actions: settingsIconActions(context),
        bottom: PreferredSize(
          preferredSize: Size.fromHeight(switcherHeight),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              MemInsets.pageH,
              0,
              MemInsets.pageH,
              MemSpace.x2,
            ),
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: ModelSwitcherPill(
                profile: profile,
                onTap: () => showModelSwitcherSheet(context, app: app),
              ),
            ),
          ),
        ),
      ),
      body: Column(
        children: <Widget>[
          if (jobs.isNotEmpty) _buildJobsStrip(app, stripJobs),
          Expanded(
            child: Chat(
              chatController: _chat,
              currentUserId: _kUserId,
              resolveUser: _resolve,
              // No `onMessageSend` / `onMessageLongPress`: both are read only by
              // the library widgets this page replaces. Sending is the page's
              // own composer; long-press arrives via `onOpenMessageMenu`.
              theme: ChatTheme.fromThemeData(theme),
              backgroundColor: scheme.surface,
              builders:
                  memChatBuilders(
                    MemChatBuilderConfig(
                      assistantLabel: profile?.displayName ?? 'Assistant',
                      aiGlyph: const AiGlyph(size: 16),
                      streamingMessageId: _streamingId,
                      errorMessageIds: _failedMessageIds,
                      onRetry: _retryFailedTurn,
                      onOpenMessageMenu: _showMessageMenu,
                    ),
                  ).copyWith(
                    // The library composer wraps itself in a per-frame
                    // `BackdropFilter` (§2.11 bans the `saveLayer`), so the page
                    // owns the composer and this slot stays empty.
                    composerBuilder: (BuildContext _) => const SizedBox.shrink(),
                    emptyChatListBuilder: (BuildContext _) =>
                        _buildEmptyConversation(app, profile),
                  ),
            ),
          ),
          ?statusRow,
          _buildComposer(theme, scheme),
        ],
      ),
    );
  }

  /// The jobs strip (§4.5 item 3): 56 dp with real 48 dp targets, replacing the
  /// 52 dp band whose chips were ~32 px behind a `top: 10` nudge (`#8`).
  Widget _buildJobsStrip(AppState app, List<PromptTemplate> stripJobs) {
    return ChipStrip(
      leadingPinned: ActionChip(
        avatar: const Icon(Icons.list_alt, size: 18),
        label: const Text('All'),
        materialTapTargetSize: MaterialTapTargetSize.padded,
        onPressed: _busy ? null : () => _showJobsSheet(app),
      ),
      children: <Widget>[
        for (final PromptTemplate t in stripJobs)
          ActionChip(
            // A running job shows a spinner where its AI glyph was.
            avatar: _jobTemplateId == t.id
                ? const InlineSpinner(size: 16)
                : const AiGlyph(size: 16),
            label: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: _kJobChipMaxWidth),
              child: Text(t.title, maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
            materialTapTargetSize: MaterialTapTargetSize.padded,
            onPressed: _busy
                ? null
                : () {
                    unawaited(_runFromTemplate(t));
                  },
          ),
      ],
    );
  }

  /// The persistent job-status row (§4.5 item 4, fixes `#13`).
  ///
  /// It sits directly above the composer rather than inside the horizontally
  /// scrolling strip, because a chip that can scroll out of view is invisible
  /// exactly when the user wants to know what is running. Returns null when
  /// there is nothing in flight.
  Widget? _buildJobStatusRow(ThemeData theme, ColorScheme scheme) {
    final String? label = _jobLabel;
    // Queue depth, read passively. `hasPending` is the never-used signal the
    // queue already exposes; the drained-but-not-yet-run jobs live here.
    final int queued =
        _queuedPromptRuns.length + (widget.promptQueue.hasPending ? 1 : 0);
    if (label == null && queued == 0) return null;

    final String primary;
    if (label == null) {
      primary = queued == 1 ? '1 job queued' : '$queued jobs queued';
    } else {
      primary = _jobWaiting ? 'Waiting: $label' : 'Running: $label';
    }
    final String? trailing = label == null || queued == 0
        ? null
        : '+$queued queued';

    return ColoredBox(
      color: scheme.surfaceContainer,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: _kJobStatusMinHeight),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: MemInsets.pageH,
            vertical: MemSpace.x2,
          ),
          child: Row(
            children: <Widget>[
              if (label != null) ...<Widget>[
                InlineSpinner(size: 16, color: scheme.onSurfaceVariant),
                const SizedBox(width: MemSpace.x3),
              ],
              Expanded(
                child: Text(
                  primary,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurface,
                  ),
                ),
              ),
              if (trailing != null) ...<Widget>[
                const SizedBox(width: MemSpace.x2),
                Text(
                  trailing,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// The composer (§4.5 item 6): `surfaceContainerLowest` bar, 1 dp `outline`
  /// top hairline, pill field, filled send button.
  Widget _buildComposer(ThemeData theme, ColorScheme scheme) {
    return ColoredBox(
      color: scheme.surfaceContainerLowest,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          // Boundary, not divider: the composer is a distinct surface.
          Hairline(color: scheme.outline),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                MemInsets.pageH,
                MemSpace.x2,
                MemSpace.x2,
                MemSpace.x2,
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: <Widget>[
                  Expanded(
                    child: TextField(
                      controller: _input,
                      focusNode: _inputFocus,
                      minLines: 1,
                      maxLines: 5,
                      keyboardType: TextInputType.multiline,
                      textCapitalization: TextCapitalization.sentences,
                      style: theme.textTheme.bodyLarge,
                      scrollPadding: const EdgeInsets.all(
                        MemInsets.editorScrollPad,
                      ),
                      // Borders come from the global InputDecorationTheme; only
                      // the padding is tuned, to land the pill at ~52 dp.
                      decoration: const InputDecoration(
                        hintText: 'Ask about your notes',
                        isDense: false,
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: MemSpace.x4,
                          vertical: _kComposerFieldPadV,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: MemSpace.x2),
                  _buildSendButton(scheme),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSendButton(ColorScheme scheme) {
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: _input,
      builder: (BuildContext context, TextEditingValue value, Widget? _) {
        final bool canSend = !_busy && value.text.trim().isNotEmpty;
        return SizedBox(
          width: MemSize.touchTarget,
          height: MemSize.touchTarget,
          child: Center(
            child: IconButton.filled(
              onPressed: canSend ? _submitFromComposer : null,
              iconSize: 20,
              // No stop button: nothing in `lib/core/llm/` can cancel a run, so
              // the button simply reports that one is in flight (NEXT-2).
              tooltip: _busy ? 'Waiting for the reply' : 'Send',
              style: IconButton.styleFrom(
                padding: EdgeInsets.zero,
                minimumSize: const Size(_kSendButtonSize, _kSendButtonSize),
                maximumSize: const Size(_kSendButtonSize, _kSendButtonSize),
              ),
              icon: _busy
                  ? InlineSpinner(size: 16, color: scheme.onSurfaceVariant)
                  : const Icon(Icons.arrow_upward_rounded),
            ),
          ),
        );
      },
    );
  }

  /// Empty conversation (§4.5 item 7). The gates mirror the send pipeline's own
  /// order — model first, then backend — so the empty state can never offer a
  /// CTA the next send would reject for a different reason.
  Widget _buildEmptyConversation(AppState app, ChatModelProfile? profile) {
    if (profile == null) {
      return EmptyState(
        icon: Icons.smart_toy_outlined,
        headline: 'No chat model yet',
        body: 'Add a model and its API key, then ask about your notes.',
        ctaLabel: 'Add a chat model',
        onCta: () => _openSettings(SettingsSection.models),
        firstRun: true,
      );
    }
    if (!app.hasMemRest && !app.mcpConnected) {
      return EmptyState(
        icon: Icons.link_off,
        headline: 'Mem is not connected',
        body: 'Connect Mem so the model can read and search your notes.',
        ctaLabel: 'Connect Mem',
        onCta: () => _openSettings(SettingsSection.account),
      );
    }
    return EmptyState(
      icon: Icons.question_answer_outlined,
      headline: 'Ask about your notes',
      body: 'The model searches your Mem knowledge base before it answers.',
      secondaryChips: <Widget>[
        for (final String prompt in _kStarterPrompts)
          ActionChip(
            // Bounded and two-line so a 2.0 text scale wraps the chip instead
            // of overflowing the 320 dp empty-state column.
            label: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: _kStarterChipMaxWidth),
              child: Text(prompt, maxLines: 2, overflow: TextOverflow.ellipsis),
            ),
            materialTapTargetSize: MaterialTapTargetSize.padded,
            onPressed: _busy
                ? null
                : () {
                    unawaited(_runUserPrompt(prompt, notifyTitle: null));
                  },
          ),
      ],
    );
  }
}

/// The searchable jobs picker behind the `All` chip.
///
/// `onPick` pops the sheet **before** the run starts — that ordering is a
/// contract, not a preference.
class _PromptJobsPickerSheet extends StatefulWidget {
  const _PromptJobsPickerSheet({
    required this.app,
    required this.onPick,
  });

  final AppState app;
  final void Function(PromptTemplate t) onPick;

  @override
  State<_PromptJobsPickerSheet> createState() => _PromptJobsPickerSheetState();
}

class _PromptJobsPickerSheetState extends State<_PromptJobsPickerSheet> {
  late List<PromptTemplate> _shown;
  final _q = TextEditingController();

  @override
  void initState() {
    super.initState();
    _shown = List<PromptTemplate>.from(widget.app.promptTemplates);
  }

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  void _applyFilter(String s) {
    final st = s.toLowerCase().trim();
    setState(() {
      if (st.isEmpty) {
        _shown = List<PromptTemplate>.from(widget.app.promptTemplates);
      } else {
        _shown = widget.app.promptTemplates
            .where(
              (t) =>
                  t.title.toLowerCase().contains(st) ||
                  t.body.toLowerCase().contains(st),
            )
            .toList();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(
              MemInsets.pageH,
              0,
              MemInsets.pageH,
              MemSpace.x3,
            ),
            child: Text('Run a job', style: theme.textTheme.titleSmall),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              MemInsets.pageH,
              0,
              MemInsets.pageH,
              MemSpace.x3,
            ),
            child: TextField(
              controller: _q,
              autofocus: true,
              // Borders are the global InputDecorationTheme's job.
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'Search jobs',
              ),
              onChanged: _applyFilter,
            ),
          ),
          SizedBox(
            height: MediaQuery.sizeOf(context).height * 0.45,
            child: _shown.isEmpty
                ? const EmptyState(
                    icon: Icons.search_off,
                    headline: 'No matching jobs',
                    body: 'Prompt jobs are created in Settings.',
                  )
                : SingleChildScrollView(
                    padding: const EdgeInsets.only(bottom: MemSpace.x6),
                    child: AppListSection(
                      children: <Widget>[
                        for (final PromptTemplate t in _shown)
                          AppRow(
                            title: Text(t.title),
                            subtitle: Text(t.body),
                            subtitleMaxLines: 3,
                            onTap: () => widget.onPick(t),
                          ),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}
