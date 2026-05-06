import 'dart:convert';

/// Metadata for an end-user-configured chat model (keys stored separately in
/// [SecureVault]).
class ChatModelProfile {
  ChatModelProfile({
    required this.id,
    required this.displayName,
    required this.provider,
    required this.model,
  });

  final String id;
  final String displayName;

  /// `openai` or `anthropic`
  final String provider;
  final String model;

  Map<String, dynamic> toJson() => {
    'id': id,
    'displayName': displayName,
    'provider': provider,
    'model': model,
  };

  static ChatModelProfile fromJson(Map<String, dynamic> j) {
    return ChatModelProfile(
      id: j['id'] as String,
      displayName: j['displayName'] as String,
      provider: j['provider'] as String,
      model: j['model'] as String,
    );
  }

  static List<ChatModelProfile> decodeList(String? json) {
    if (json == null || json.isEmpty) return [];
    final list = jsonDecode(json) as List<dynamic>;
    return list.map((e) => fromJson(Map<String, dynamic>.from(e as Map))).toList();
  }

  static String encodeList(List<ChatModelProfile> list) =>
      jsonEncode(list.map((e) => e.toJson()).toList());
}
