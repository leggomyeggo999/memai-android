import 'package:flutter/material.dart';
import 'package:flutter_chat_core/flutter_chat_core.dart';
import 'package:flutter_chat_ui/flutter_chat_ui.dart';
import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:uuid/uuid.dart';

import '../../app_scope.dart';
import '../../app_state.dart';
import '../../core/llm/anthropic_mem_agent.dart';
import '../../core/llm/chat_model_profile.dart';
import '../../core/llm/gemini_mem_agent.dart';
import '../../core/llm/mem_tool_runner.dart';
import '../../core/llm/openai_mem_agent.dart';
import '../../core/mem/mem_api_client.dart';
import '../../core/mcp/mcp_session_client.dart';
import '../../core/notifications/mem_job_notifications.dart';
import '../../core/prompts/prompt_template.dart';
import '../../core/llm/curated_chat_models.dart';
import '../../widgets/settings_launcher.dart';
import 'chat_prompt_queue.dart';

const _kUserId = 'user';
const _kAssistantId = 'assistant';

const _systemPrompt =
    'You have tools to read and search the user '
    'Mem knowledge base. Always use tools instead of guessing. To update a note, '
    'call get_note first to read the current version number, then update_note with '
    'that exact version. Be concise.';

class MemChatPage extends StatefulWidget {
  const MemChatPage({super.key, required this.promptQueue});

  final ChatPromptQueue promptQueue;

  @override
  State<MemChatPage> createState() => _MemChatPageState();
}

class _MemChatPageState extends State<MemChatPage> {
  late final InMemoryChatController _chat;
  final List<Map<String, dynamic>> _openAiHist = [
    {'role': 'system', 'content': _systemPrompt},
  ];
  final List<Map<String, dynamic>> _anthropicHist = [];
  final List<Map<String, dynamic>> _geminiHist = [];
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _chat = InMemoryChatController();
    widget.promptQueue.addListener(_onPromptQueueChanged);
  }

  @override
  void dispose() {
    widget.promptQueue.removeListener(_onPromptQueueChanged);
    _chat.dispose();
    super.dispose();
  }

  void _onPromptQueueChanged() {
    final job = widget.promptQueue.consume();
    if (job == null || !mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _runUserPrompt(
        job.text,
        notifyTitle: job.notifyOnComplete ? job.notificationTitle : null,
      );
    });
  }

  Future<User?> _resolve(UserID id) async {
    if (id == _kUserId) {
      return const User(id: _kUserId, name: 'You');
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

  Future<void> _handleSendFromInput(String text) async {
    await _runUserPrompt(text.trim(), notifyTitle: null);
  }

  Future<void> _runFromTemplate(PromptTemplate t) async {
    await _runUserPrompt(t.body, notifyTitle: null);
  }

  Future<void> _runUserPrompt(
    String trimmed, {
    String? notifyTitle,
  }) async {
    final messenger = ScaffoldMessenger.of(context);
    if (trimmed.isEmpty || _busy) return;

    final app = AppScope.of(context);
    final profile = _activeProfile(context);
    if (profile == null) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Add a chat model in Settings and select it.'),
        ),
      );
      return;
    }

    if (!app.hasMemRest && !app.mcpConnected) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text(
            'Connect Mem via REST API key and/or MCP OAuth so tools can reach your notes.',
          ),
        ),
      );
      return;
    }

    String? llmKey;
    try {
      llmKey = await app.vault.getLlmApiKey(profile.id);
    } catch (_) {}
    if (llmKey == null || llmKey.isEmpty) {
      if (!mounted) return;
      messenger.showSnackBar(
        const SnackBar(content: Text('Missing LLM API key for this model profile.')),
      );
      return;
    }

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
        text: '…',
        createdAt: DateTime.now(),
      ),
    );

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
        final old = _pendingById(pendingId);
        if (old == null) return;
        final display = accumulated.isEmpty ? '…' : accumulated;
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
      if (pending != null) {
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
    } catch (e) {
      await _failMessage(pendingId, _formatChatError(e, profile: profile));
      if (notifyTitle != null) {
        await MemJobNotifications.showPromptJobFinished(
          title: notifyTitle,
          ok: false,
          detail: _formatChatError(e, profile: profile),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _formatChatError(Object e, {required ChatModelProfile profile}) {
    if (e is DioException) {
      final code = e.response?.statusCode;
      if (code == 404) {
        return 'Error: ${chatProviderBrand(profile.provider)} returned 404. '
            'This usually means the model id is not available: "${profile.model}". '
            'Pick a different model in Settings → Chat models.';
      }
      final msg = e.message ?? 'Network error';
      return 'Error: $msg (HTTP ${code ?? "?"})';
    }
    return 'Error: $e';
  }

  Message? _pendingById(String messageId) {
    for (final m in _chat.messages) {
      if (m.id == messageId) return m;
    }
    return null;
  }

  Future<void> _failMessage(String messageId, String err) async {
    final pending = _pendingById(messageId);
    if (pending == null) return;
    await _chat.updateMessage(
      pending,
      Message.text(
        id: messageId,
        authorId: _kAssistantId,
        text: 'Error: $err',
        createdAt: DateTime.now(),
      ),
    );
  }

  void _onMessageLongPress(
    BuildContext context,
    Message message, {
    required int index,
    required LongPressStartDetails details,
  }) {
    final text = switch (message) {
      TextMessage(:final text) => text,
      _ => null,
    };
    if (text == null || text.trim().isEmpty) return;

    Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(this.context).showSnackBar(
      const SnackBar(content: Text('Message copied.')),
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
          Navigator.pop(sheetCtx);
          _runFromTemplate(t);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final profile = _activeProfile(context);
    final label = profile == null
        ? 'No model'
        : '${profile.displayName} (${profile.provider})';
    final app = AppScope.of(context);
    final jobs = app.promptTemplates;
    final stripJobs = jobs.length <= 12 ? jobs : jobs.take(12).toList();

    return Scaffold(
      appBar: AppBar(
        title: Text(label),
        actions: settingsIconActions(context),
      ),
      body: Column(
        children: [
          if (jobs.isNotEmpty)
            Material(
              color: Theme.of(context).colorScheme.surfaceContainerHighest
                  .withValues(alpha: 0.35),
              child: SizedBox(
                height: 52,
                child: Row(
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(left: 12, right: 4),
                      child: Icon(
                        Icons.bolt_outlined,
                        size: 20,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                    Text(
                      'Jobs',
                      style: Theme.of(context).textTheme.labelLarge,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.only(right: 8),
                        itemCount: stripJobs.length + 1,
                        separatorBuilder: (context, index) =>
                            const SizedBox(width: 6),
                        itemBuilder: (ctx, i) {
                          if (i == 0) {
                            return Padding(
                              padding: const EdgeInsets.only(top: 10),
                              child: ActionChip(
                                avatar: const Icon(Icons.list_alt, size: 18),
                                label: const Text('All'),
                                onPressed: _busy
                                    ? null
                                    : () => _showJobsSheet(app),
                              ),
                            );
                          }
                          final t = stripJobs[i - 1];
                          return Padding(
                            padding: const EdgeInsets.only(top: 10),
                            child: ActionChip(
                              label: Text(
                                t.title,
                                overflow: TextOverflow.ellipsis,
                              ),
                              onPressed:
                                  _busy ? null : () => _runFromTemplate(t),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
          Expanded(
            child: Chat(
              chatController: _chat,
              currentUserId: _kUserId,
              resolveUser: _resolve,
              onMessageSend: _handleSendFromInput,
              onMessageLongPress: _onMessageLongPress,
              theme: ChatTheme.dark(),
              backgroundColor: Theme.of(context).colorScheme.surface,
            ),
          ),
        ],
      ),
    );
  }
}

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
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
            child: TextField(
              controller: _q,
              autofocus: true,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'Search jobs',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              onChanged: _applyFilter,
            ),
          ),
          SizedBox(
            height: MediaQuery.of(context).size.height * 0.45,
            child: _shown.isEmpty
                ? Center(
                    child: Text(
                      'No matches · add jobs in Settings',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
                    itemCount: _shown.length,
                    separatorBuilder: (context, index) =>
                        const Divider(height: 1),
                    itemBuilder: (c, i) {
                      final t = _shown[i];
                      return ListTile(
                        title: Text(t.title),
                        subtitle: Text(
                          t.body,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                        ),
                        onTap: () => widget.onPick(t),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

