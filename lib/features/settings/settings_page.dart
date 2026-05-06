import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:uuid/uuid.dart';

import '../../app_scope.dart';
import '../../core/llm/chat_model_profile.dart';
import '../../core/mcp/mem_oauth.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final _apiKeyCtrl = TextEditingController();
  bool _maskKey = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final app = AppScope.of(context);
      await app.load();
      final k = app.memApiKey;
      if (k != null && mounted) {
        _apiKeyCtrl.text = k;
      }
    });
  }

  @override
  void dispose() {
    _apiKeyCtrl.dispose();
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

  Future<void> _addModelDialog() async {
    final nameCtrl = TextEditingController();
    final modelCtrl = TextEditingController();
    final keyCtrl = TextEditingController();
    String provider = 'openai';

    await showDialog<void>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setLocal) {
            return AlertDialog(
              title: const Text('Add chat model'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: nameCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Display name',
                      ),
                    ),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<String>(
                      value: provider,
                      items: const [
                        DropdownMenuItem(value: 'openai', child: Text('OpenAI')),
                        DropdownMenuItem(
                          value: 'anthropic',
                          child: Text('Anthropic'),
                        ),
                      ],
                      onChanged: (v) => setLocal(() => provider = v ?? 'openai'),
                      decoration: const InputDecoration(labelText: 'Provider'),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: modelCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Model id (e.g. gpt-4o)',
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: keyCtrl,
                      obscureText: true,
                      decoration: const InputDecoration(
                        labelText: 'Provider API key',
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () async {
                    final app = AppScope.of(context);
                    final id = const Uuid().v4();
                    final p = ChatModelProfile(
                      id: id,
                      displayName: nameCtrl.text.trim().isEmpty
                          ? 'Model'
                          : nameCtrl.text.trim(),
                      provider: provider,
                      model: modelCtrl.text.trim(),
                    );
                    if (p.model.isEmpty) return;
                    await app.vault.setLlmApiKey(p.id, keyCtrl.text.trim());
                    final next = [...app.chatModels, p];
                    await app.saveChatModels(next, activeId: p.id);
                    if (context.mounted) Navigator.pop(context);
                  },
                  child: const Text('Save'),
                ),
              ],
            );
          },
        );
      },
    );
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
            'Mem REST API key comes from Mem Settings → API. It powers Pulse, '
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
          Row(
            children: [
              FilledButton(
                onPressed: _connectMcp,
                child: const Text('Connect MCP (browser)'),
              ),
              const SizedBox(width: 8),
              OutlinedButton(
                onPressed: app.mcpConnected
                    ? () async {
                        await app.disconnectMcp();
                        setState(() {});
                      }
                    : null,
                child: const Text('Disconnect'),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Chat models',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              FilledButton.tonal(
                onPressed: _addModelDialog,
                child: const Text('Add model'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ...app.chatModels.map((m) {
            final sel = app.activeModelId == m.id;
            return Card(
              child: RadioListTile<String>(
                title: Text(m.displayName),
                subtitle: Text('${m.provider} · ${m.model}'),
                value: m.id,
                groupValue: app.activeModelId,
                onChanged: (v) => app.setActiveModel(v),
                secondary: sel ? const Icon(Icons.check_circle_outline) : null,
              ),
            );
          }),
          const SizedBox(height: 24),
          Text('Security', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Text(
            'Secrets live in flutter_secure_storage (Android Keystore-backed). '
            'Nothing is sent to third parties except the providers you configure '
            '(Mem, OpenAI, Anthropic, …).',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
        ],
      ),
    );
  }
}
