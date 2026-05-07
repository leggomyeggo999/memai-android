import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'core/llm/chat_model_profile.dart';
import 'core/mcp/mem_oauth.dart';
import 'core/prompts/home_prompt_widget_sync.dart';
import 'core/prompts/prompt_template.dart';
import 'core/prompts/prompt_template_store.dart';
import 'core/security/secure_vault.dart';

/// Loads secrets once at startup and exposes derived booleans to the UI.
class AppState extends ChangeNotifier {
  AppState() : _vault = SecureVault(), _promptStore = PromptTemplateStore();

  final SecureVault _vault;
  final PromptTemplateStore _promptStore;
  late final MemMcpOAuth _mcpOAuth = MemMcpOAuth(vault: _vault);

  /// Increment to tell the Notes tab (and similar) to reload from the API.
  final ValueNotifier<int> notesListRevision = ValueNotifier(0);

  void bumpNotesListRevision() {
    notesListRevision.value++;
  }

  String? memApiKey;
  bool mcpConnected = false;
  List<ChatModelProfile> chatModels = [];
  String? activeModelId;

  List<PromptTemplate> promptTemplates = [];
  List<String> pinnedTemplateIds = [];
  String? voiceOpenAiApiKey;
  String voiceWhisperModel = 'whisper-1';

  /// When set (0–2), shell switches bottom-nav tab once and clears [shellTabRequest].
  final ValueNotifier<int?> shellTabRequest = ValueNotifier(null);

  void goToShellTab(int index) {
    shellTabRequest.value = index;
  }

  bool get hasMemRest => memApiKey != null && memApiKey!.isNotEmpty;

  Future<void> load() async {
    await _vault.ensureMcpRedirectMatchesOrReset(MemMcpOAuth.redirectUrl);
    memApiKey = await _vault.getMemApiKey();
    final access = await _vault.getMcpAccessToken();
    mcpConnected = access != null && access.isNotEmpty;
    final raw = await _vault.getChatProfilesMetaJson();
    chatModels = ChatModelProfile.decodeList(raw);
    voiceOpenAiApiKey = await _vault.getVoiceOpenAiApiKey();
    voiceWhisperModel = await _vault.getVoiceWhisperModel() ?? 'whisper-1';
    if (activeModelId == null && chatModels.isNotEmpty) {
      activeModelId = chatModels.first.id;
    }
    await reloadPromptJobs();
    notifyListeners();
  }

  Future<void> reloadPromptJobs() async {
    final tuple = await _promptStore.load();
    promptTemplates = tuple.$1;
    pinnedTemplateIds = tuple.$2;
    _sanitizePinned();
  }

  void _sanitizePinned() {
    final ids = promptTemplates.map((t) => t.id).toSet();
    pinnedTemplateIds = pinnedTemplateIds.where(ids.contains).take(4).toList();
  }

  PromptTemplate? promptById(String id) {
    for (final p in promptTemplates) {
      if (p.id == id) return p;
    }
    return null;
  }

  Future<void> _persistPrompts() async {
    await _promptStore.save(
      templates: promptTemplates,
      pinnedTemplateIds: pinnedTemplateIds,
    );
    await syncHomePromptWidget(all: promptTemplates, pinnedIds: pinnedTemplateIds);
    notifyListeners();
  }

  Future<void> upsertPromptJob(PromptTemplate template) async {
    final ix = promptTemplates.indexWhere((e) => e.id == template.id);
    final next = List<PromptTemplate>.from(promptTemplates);
    if (ix >= 0) {
      next[ix] = template;
    } else {
      next.add(template);
    }
    promptTemplates = next;
    _sanitizePinned();
    await _persistPrompts();
  }

  Future<void> removePromptJob(String id) async {
    promptTemplates =
        promptTemplates.where((t) => t.id != id).toList(growable: false);
    pinnedTemplateIds = pinnedTemplateIds.where((x) => x != id).toList();
    await _persistPrompts();
  }

  Future<void> setPinnedTemplateIds(List<String> ids) async {
    final unique = <String>{};
    for (final id in ids) {
      if (!unique.contains(id) && promptById(id) != null) {
        unique.add(id);
      }
      if (unique.length >= 4) break;
    }
    pinnedTemplateIds = unique.toList();
    await _persistPrompts();
  }

  Future<void> setMemApiKey(String? key) async {
    await _vault.setMemApiKey(key);
    memApiKey = key;
    notifyListeners();
  }

  Future<void> connectMcp() async {
    await _mcpOAuth.signInWithMcp();
    mcpConnected = true;
    notifyListeners();
  }

  Future<void> disconnectMcp() async {
    await _mcpOAuth.signOutMcp();
    mcpConnected = false;
    notifyListeners();
  }

  /// Background refresh for MCP access token (call before MCP calls).
  Future<void> refreshMcpIfNeeded() => _mcpOAuth.refreshIfNeeded();

  Future<void> saveChatModels(List<ChatModelProfile> models, {String? activeId}) async {
    await _vault.setChatProfilesMetaJson(ChatModelProfile.encodeList(models));
    chatModels = models;
    if (models.isEmpty) {
      activeModelId = null;
    } else if (activeId != null) {
      activeModelId = activeId;
    }
    notifyListeners();
  }

  void setActiveModel(String? id) {
    activeModelId = id;
    notifyListeners();
  }

  Future<void> setVoiceOpenAiApiKey(String? key) async {
    await _vault.setVoiceOpenAiApiKey(key);
    voiceOpenAiApiKey = key;
    notifyListeners();
  }

  Future<void> setVoiceWhisperModel(String modelId) async {
    await _vault.setVoiceWhisperModel(modelId);
    voiceWhisperModel = modelId;
    notifyListeners();
  }

  SecureVault get vault => _vault;
  MemMcpOAuth get mcpOAuth => _mcpOAuth;
}
