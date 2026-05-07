import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_appauth/flutter_appauth.dart';
import 'package:uuid/uuid.dart';

import '../../app_scope.dart';
import '../../core/llm/chat_model_profile.dart';
import '../../core/llm/curated_chat_models.dart';
import '../../core/mcp/mem_oauth.dart' show MemMcpOAuth;
import 'prompt_jobs_page.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final _apiKeyCtrl = TextEditingController();
  final _voiceOpenAiKeyCtrl = TextEditingController();
  static const List<(String id, String label)> _voiceModels = [
    ('whisper-1', 'Whisper-1'),
    ('gpt-4o-mini-transcribe', 'GPT-4o mini transcribe'),
  ];
  bool _maskKey = true;
  bool _maskVoiceKey = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final app = AppScope.of(context);
      final k = app.memApiKey;
      if (k != null && mounted) _apiKeyCtrl.text = k;
      final voiceKey = app.voiceOpenAiApiKey;
      if (voiceKey != null && mounted) _voiceOpenAiKeyCtrl.text = voiceKey;
    });
  }

  @override
  void dispose() {
    _apiKeyCtrl.dispose();
    _voiceOpenAiKeyCtrl.dispose();
    super.dispose();
  }

  Future<void> _saveApiKey() async {
    final app = AppScope.of(context);
    await app.setMemApiKey(_apiKeyCtrl.text.trim().isEmpty ? null : _apiKeyCtrl.text.trim());
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Mem API key saved securely on-device.')),
      );
    }
  }

  Future<void> _connectMcp() async {
    final app = AppScope.of(context);
    try {
      await app.connectMcp();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('MCP OAuth complete. Access token stored.')),
        );
      }
    } on FlutterAppAuthUserCancelledException {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Sign-in cancelled.')),
        );
      }
    } on PlatformException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('OAuth error: ${e.message}')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.toString())));
      }
    }
  }

  Future<void> _saveVoiceSettings() async {
    final app = AppScope.of(context);
    await app.setVoiceOpenAiApiKey(
      _voiceOpenAiKeyCtrl.text.trim().isEmpty ? null : _voiceOpenAiKeyCtrl.text.trim(),
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Voice transcription settings saved.')),
    );
  }

  Future<void> _showChatModelEditor({ChatModelProfile? existing}) async {
    final isEdit = existing != null;
    final keyCtrl = TextEditingController();
    var provider = existing?.provider ?? 'openai';
    var catalog = curatedModelsForProvider(provider);
    CuratedChatModel? selected = existing == null
        ? (catalog.isEmpty ? null : catalog.first)
        : (curatedModelByApiId(provider, existing.model) ??
              (catalog.isEmpty ? null : catalog.first));

    await showDialog<void>(
      context: context,
      builder: (dialogRouteContext) {
        return StatefulBuilder(
          builder: (dialogContext, setLocal) {
            return AlertDialog(
              title: Text(isEdit ? 'Edit chat model' : 'Add chat model'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Pick provider and model. The display title is chosen automatically.',
                      style: Theme.of(dialogContext).textTheme.bodySmall
                          ?.copyWith(
                            color: Theme.of(dialogContext)
                                .colorScheme
                                .onSurfaceVariant,
                          ),
                    ),
                    if (existing != null &&
                        curatedModelByApiId(existing.provider, existing.model) ==
                            null) ...[
                      const SizedBox(height: 8),
                      Text(
                        'Stored model "${existing.model}" is not in the current catalog. '
                        'Choose a replacement below.',
                        style: Theme.of(dialogContext).textTheme.bodySmall
                            ?.copyWith(color: Theme.of(dialogContext).colorScheme.error),
                      ),
                    ],
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      value: provider,
                      items: const [
                        DropdownMenuItem(value: 'openai', child: Text('OpenAI')),
                        DropdownMenuItem(
                          value: 'anthropic',
                          child: Text('Anthropic'),
                        ),
                        DropdownMenuItem(value: 'gemini', child: Text('Gemini')),
                      ],
                      onChanged: (v) {
                        setLocal(() {
                          provider = v ?? 'openai';
                          catalog = curatedModelsForProvider(provider);
                          selected =
                              catalog.isEmpty ? null : catalog.first;
                        });
                      },
                      decoration: const InputDecoration(labelText: 'Provider'),
                    ),
                    const SizedBox(height: 12),
                    if (catalog.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 8),
                        child: Text('No models defined for this provider.'),
                      )
                    else
                      DropdownButtonFormField<CuratedChatModel>(
                        value: selected,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: 'Model',
                        ),
                        items: catalog
                            .map(
                              (m) => DropdownMenuItem(
                                value: m,
                                child: Text(
                                  '${chatProviderBrand(provider)} · ${m.catalogLabel}',
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            )
                            .toList(),
                        onChanged: (m) {
                          setLocal(() => selected = m);
                        },
                      ),
                    if (catalog.isNotEmpty && selected != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        'API model id · ${selected!.apiModelId}',
                        style:
                            Theme.of(dialogContext).textTheme.bodySmall?.copyWith(
                                  color: Theme.of(dialogContext)
                                      .colorScheme
                                      .onSurfaceVariant,
                                  fontFeatures: const [FontFeature.tabularFigures()],
                                ),
                      ),
                    ],
                    const SizedBox(height: 12),
                    TextField(
                      controller: keyCtrl,
                      obscureText: true,
                      decoration: InputDecoration(
                        labelText: 'Provider API key',
                        border: const OutlineInputBorder(),
                        helperText:
                            isEdit ? 'Leave blank to keep your current API key.' : null,
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () async {
                    final sel = selected;
                    if (sel == null) return;
                    final messenger = ScaffoldMessenger.of(context);
                    final keyText = keyCtrl.text.trim();
                    if (!isEdit && keyText.isEmpty) {
                      messenger.showSnackBar(
                        const SnackBar(
                          content: Text('Paste your provider API key to add this model.'),
                        ),
                      );
                      return;
                    }
                    final pageApp = AppScope.of(context);
                    final profileId = existing?.id ?? const Uuid().v4();
                    final p = ChatModelProfile(
                      id: profileId,
                      displayName: composeChatDisplayName(provider, sel),
                      provider: provider,
                      model: sel.apiModelId,
                    );
                    final next = isEdit
                        ? pageApp.chatModels
                            .map((m) => m.id == profileId ? p : m)
                            .toList()
                        : [...pageApp.chatModels, p];
                    final activeAfter = isEdit
                        ? (pageApp.activeModelId ?? profileId)
                        : profileId;
                    if (!dialogContext.mounted) return;
                    Navigator.of(dialogContext).pop();
                    if (keyText.isNotEmpty) {
                      await pageApp.vault.setLlmApiKey(profileId, keyText);
                    }
                    await pageApp.saveChatModels(next, activeId: activeAfter);
                  },
                  child: const Text('Save'),
                ),
              ],
            );
          },
        );
      },
    );
    // Don't dispose immediately after showDialog returns; the route can still
    // be finishing teardown animations and briefly rebuild the TextField.
  }

  Future<void> _confirmRemoveModel(ChatModelProfile m) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove chat model?'),
        content: Text('“${m.displayName}” will be removed from this device.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Remove')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final app = AppScope.of(context);
    final next = app.chatModels.where((x) => x.id != m.id).toList(growable: false);
    await app.vault.setLlmApiKey(m.id, null);
    final newActive = next.isEmpty
        ? null
        : (app.activeModelId == m.id ? next.first.id : app.activeModelId);
    await app.saveChatModels(next, activeId: newActive);
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
            padding: const EdgeInsets.all(20),
            children: [
          Text(
            'Credentials',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Text(
            'Mem REST API key comes from Mem Settings → API. It powers Notes, '
            'capture, and is the preferred path for chat tools (same quotas as MCP).',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _apiKeyCtrl,
            obscureText: _maskKey,
            decoration: InputDecoration(
              labelText: 'Mem API key',
              border: const OutlineInputBorder(),
              suffixIcon: IconButton(
                icon: Icon(_maskKey ? Icons.visibility : Icons.visibility_off),
                onPressed: () => setState(() => _maskKey = !_maskKey),
              ),
            ),
          ),
          const SizedBox(height: 8),
          FilledButton(onPressed: _saveApiKey, child: const Text('Save API key')),
          const SizedBox(height: 24),
          Text('MCP OAuth', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Text(
            'Uses Mem’s hosted OAuth (see ${MemMcpOAuth.redirectUrl}). Required '
            'for MCP JSON-RPC tools if you choose not to use a REST API key.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: 8),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(
              app.mcpConnected ? 'MCP: connected' : 'MCP: not connected',
            ),
          ),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton(
                onPressed: app.mcpConnected ? null : _connectMcp,
                child: const Text('Connect MCP (browser)'),
              ),
              OutlinedButton(
                onPressed: app.mcpConnected
                    ? () => app.disconnectMcp()
                    : null,
                child: const Text('Disconnect'),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            runSpacing: 8,
            children: [
              Text(
                'Chat models',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              FilledButton.tonal(
                onPressed: () => _showChatModelEditor(),
                child: const Text('Add model'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ...app.chatModels.map((m) {
            return Card(
              child: RadioListTile<String>(
                title: Text(m.displayName),
                subtitle: Text(m.model),
                value: m.id,
                groupValue: app.activeModelId,
                onChanged: (v) => app.setActiveModel(v),
                secondary: PopupMenuButton<String>(
                  tooltip: 'Model actions',
                  onSelected: (v) {
                    if (v == 'edit') {
                      _showChatModelEditor(existing: m);
                    } else if (v == 'remove') {
                      _confirmRemoveModel(m);
                    }
                  },
                  itemBuilder: (ctx) => const [
                    PopupMenuItem(value: 'edit', child: Text('Edit')),
                    PopupMenuItem(value: 'remove', child: Text('Remove')),
                  ],
                ),
              ),
            );
          }),
          const SizedBox(height: 24),
          Text(
            'Voice transcription (OpenAI)',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Text(
            'Voice capture uses OpenAI transcription models. You can use a dedicated '
            'OpenAI key here, or leave it blank to reuse an OpenAI chat model key.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            value: app.voiceWhisperModel,
            items: _voiceModels
                .map(
                  (m) => DropdownMenuItem<String>(
                    value: m.$1,
                    child: Text(m.$2),
                  ),
                )
                .toList(),
            decoration: const InputDecoration(
              labelText: 'Voice model',
              border: OutlineInputBorder(),
            ),
            onChanged: (v) {
              if (v != null) {
                app.setVoiceWhisperModel(v);
              }
            },
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _voiceOpenAiKeyCtrl,
            obscureText: _maskVoiceKey,
            decoration: InputDecoration(
              labelText: 'OpenAI API key for voice (optional)',
              border: const OutlineInputBorder(),
              helperText: 'Leave blank to fallback to any configured OpenAI chat key.',
              suffixIcon: IconButton(
                icon: Icon(_maskVoiceKey ? Icons.visibility : Icons.visibility_off),
                onPressed: () => setState(() => _maskVoiceKey = !_maskVoiceKey),
              ),
            ),
          ),
          const SizedBox(height: 8),
          FilledButton.tonal(
            onPressed: _saveVoiceSettings,
            child: const Text('Save voice settings'),
          ),
          const SizedBox(height: 24),
          Text(
            'Prompt jobs',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Text(
            'Save multi-step MCP chat templates (e.g. triage uncategorized notes), '
            'run them from Chat, pin up to four on the Android home widget, '
            'and get a notification when a widget-triggered run finishes.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: 12),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(
              Icons.bolt_outlined,
              color: Theme.of(context).colorScheme.primary,
            ),
            title: const Text('Manage prompt jobs'),
            subtitle: const Text('Edit, reorder pins for the widget'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push<void>(
                  MaterialPageRoute(builder: (_) => const PromptJobsPage()),
                ),
          ),
          const SizedBox(height: 24),
          Text('Security', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Text(
            'Secrets live in flutter_secure_storage (Android Keystore-backed). '
            'Nothing is sent to third parties except the providers you configure '
            '(Mem, OpenAI, Anthropic, Gemini, …).',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
            ],
          ),
        );
  }
}
