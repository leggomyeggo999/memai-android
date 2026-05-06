import 'package:flutter/material.dart';
import 'package:flutter_chat_core/flutter_chat_core.dart';
import 'package:flutter_chat_ui/flutter_chat_ui.dart';
import 'package:uuid/uuid.dart';

import '../../app_scope.dart';
import '../../core/llm/anthropic_mem_agent.dart';
import '../../core/llm/chat_model_profile.dart';
import '../../core/llm/mem_tool_runner.dart';
import '../../core/llm/openai_mem_agent.dart';
import '../../core/mem/mem_api_client.dart';
import '../../core/mcp/mcp_session_client.dart';
import '../../widgets/settings_launcher.dart';

const _kUserId = 'user';
const _kAssistantId = 'assistant';

const _systemPrompt =
    'You have tools to read and search the user '
    'Mem knowledge base. Always use tools instead of guessing. To update a note, '
    'call get_note first to read the current version number, then update_note with '
    'that exact version. Be concise.';

class MemChatPage extends StatefulWidget {
  const MemChatPage({super.key});

  @override
  State<MemChatPage> createState() => _MemChatPageState();
}

class _MemChatPageState extends State<MemChatPage> {
  late final InMemoryChatController _chat;
  final List<Map<String, dynamic>> _openAiHist = [
    {'role': 'system', 'content': _systemPrompt},
  ];
  final List<Map<String, dynamic>> _anthropicHist = [];
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _chat = InMemoryChatController();
  }

  @override
  void dispose() {
    _chat.dispose();
    super.dispose();
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

  Future<void> _onSend(String text) async {
    final messenger = ScaffoldMessenger.of(context);
    final trimmed = text.trim();
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
      if (profile.provider == 'openai') {
        final agent = OpenAiMemAgent(
          apiKey: llmKey,
          model: profile.model,
          runner: runner,
        );
        final res = await agent.runConversation(
          priorOpenAiMessages: _openAiHist,
          userText: trimmed,
          onAssistantTextDelta: (accumulated) async {
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
          },
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
        );
        _anthropicHist
          ..clear()
          ..addAll(res.anthropicHistory);
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
    } catch (e) {
      await _failMessage(pendingId, e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
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

  @override
  Widget build(BuildContext context) {
    final profile = _activeProfile(context);
    final label = profile == null
        ? 'No model'
        : '${profile.displayName} (${profile.provider})';

    return Scaffold(
      appBar: AppBar(
        title: Text(label),
        actions: settingsIconActions(context),
      ),
      body: Chat(
        chatController: _chat,
        currentUserId: _kUserId,
        resolveUser: _resolve,
        onMessageSend: _onSend,
        theme: ChatTheme.dark(),
        backgroundColor: Theme.of(context).colorScheme.surface,
      ),
    );
  }
}
