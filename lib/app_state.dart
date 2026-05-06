import 'package:flutter/foundation.dart';

import 'core/llm/chat_model_profile.dart';
import 'core/mcp/mem_oauth.dart';
import 'core/security/secure_vault.dart';

/// Loads secrets once at startup and exposes derived booleans to the UI.
class AppState extends ChangeNotifier {
  AppState() : _vault = SecureVault();

  final SecureVault _vault;
  late final MemMcpOAuth _mcpOAuth = MemMcpOAuth(vault: _vault);

  String? memApiKey;
  bool mcpConnected = false;
  List<ChatModelProfile> chatModels = [];
  String? activeModelId;

  bool get hasMemRest => memApiKey != null && memApiKey!.isNotEmpty;

  Future<void> load() async {
    memApiKey = await _vault.getMemApiKey();
    final access = await _vault.getMcpAccessToken();
    mcpConnected = access != null && access.isNotEmpty;
    final raw = await _vault.getChatProfilesMetaJson();
    chatModels = ChatModelProfile.decodeList(raw);
    if (activeModelId == null && chatModels.isNotEmpty) {
      activeModelId = chatModels.first.id;
    }
    notifyListeners();
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
    if (activeId != null) activeModelId = activeId;
    notifyListeners();
  }

  void setActiveModel(String? id) {
    activeModelId = id;
    notifyListeners();
  }

  SecureVault get vault => _vault;
  MemMcpOAuth get mcpOAuth => _mcpOAuth;
}
