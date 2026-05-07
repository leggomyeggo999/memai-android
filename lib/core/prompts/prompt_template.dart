import 'dart:convert';

/// User-defined prompt the assistant runs with Mem tools (REST and/or MCP).
class PromptTemplate {
  const PromptTemplate({
    required this.id,
    required this.title,
    required this.body,
  });

  final String id;
  final String title;
  final String body;

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'body': body,
      };

  factory PromptTemplate.fromJson(Map<String, dynamic> j) {
    return PromptTemplate(
      id: j['id'] as String,
      title: j['title'] as String? ?? '',
      body: j['body'] as String? ?? '',
    );
  }

  static List<PromptTemplate> decodeList(String? raw) {
    if (raw == null || raw.isEmpty) return [];
    final list = jsonDecode(raw) as List<dynamic>;
    return list
        .map((e) => PromptTemplate.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  static String encodeList(List<PromptTemplate> items) {
    return jsonEncode(items.map((e) => e.toJson()).toList());
  }
}
