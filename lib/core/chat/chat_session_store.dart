import 'dart:convert';

import 'package:flutter_chat_core/flutter_chat_core.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// How long UI + provider histories are kept on device.
const Duration kChatSessionRetention = Duration(days: 5);

const _keyPrefix = 'chat_session_v1_';

/// Persisted chat for one [ChatModelProfile.id].
class ChatSessionSnapshot {
  const ChatSessionSnapshot({
    required this.uiMessages,
    required this.openAiHist,
    required this.anthropicHist,
    required this.geminiHist,
    required this.savedAt,
  });

  final List<Message> uiMessages;
  final List<Map<String, dynamic>> openAiHist;
  final List<Map<String, dynamic>> anthropicHist;
  final List<Map<String, dynamic>> geminiHist;
  final DateTime savedAt;

  bool get isWithinRetention {
    return DateTime.now().difference(savedAt) <= kChatSessionRetention;
  }
}

class ChatSessionStore {
  Future<ChatSessionSnapshot?> load(String profileId) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('$_keyPrefix$profileId');
    if (raw == null || raw.isEmpty) return null;

    try {
      final j = jsonDecode(raw) as Map<String, dynamic>;
      final savedAt = DateTime.parse(j['savedAt'] as String);
      if (DateTime.now().difference(savedAt) > kChatSessionRetention) {
        await prefs.remove('$_keyPrefix$profileId');
        return null;
      }

      final ui = _decodeUiMessages(j['uiMessages'] as List<dynamic>? ?? []);
      final prunedUi = _pruneUiMessages(ui);
      if (prunedUi.isEmpty) {
        await prefs.remove('$_keyPrefix$profileId');
        return null;
      }

      return ChatSessionSnapshot(
        uiMessages: prunedUi,
        openAiHist: _decodeMapList(j['openAiHist']),
        anthropicHist: _decodeMapList(j['anthropicHist']),
        geminiHist: _decodeMapList(j['geminiHist']),
        savedAt: savedAt,
      );
    } catch (_) {
      await prefs.remove('$_keyPrefix$profileId');
      return null;
    }
  }

  Future<void> save({
    required String profileId,
    required List<Message> uiMessages,
    required List<Map<String, dynamic>> openAiHist,
    required List<Map<String, dynamic>> anthropicHist,
    required List<Map<String, dynamic>> geminiHist,
  }) async {
    final prunedUi = _pruneUiMessages(uiMessages);
    if (prunedUi.isEmpty) {
      await clear(profileId);
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      '$_keyPrefix$profileId',
      jsonEncode({
        'savedAt': DateTime.now().toUtc().toIso8601String(),
        'uiMessages': prunedUi.map(_encodeUiMessage).toList(),
        'openAiHist': openAiHist,
        'anthropicHist': anthropicHist,
        'geminiHist': geminiHist,
      }),
    );
  }

  Future<void> clear(String profileId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('$_keyPrefix$profileId');
  }

  List<Message> _pruneUiMessages(List<Message> messages) {
    final cutoff = DateTime.now().subtract(kChatSessionRetention);
    return messages
        .where((m) {
          final t = m.createdAt;
          if (t == null) return true;
          return !t.isBefore(cutoff);
        })
        .toList();
  }

  List<Message> _decodeUiMessages(List<dynamic> raw) {
    final out = <Message>[];
    for (final item in raw) {
      if (item is! Map<String, dynamic>) continue;
      final id = item['id'] as String?;
      final authorId = item['authorId'] as String?;
      final text = item['text'] as String?;
      if (id == null || authorId == null || text == null) continue;
      final createdRaw = item['createdAt'] as String?;
      out.add(
        Message.text(
          id: id,
          authorId: authorId,
          text: text,
          createdAt: createdRaw != null ? DateTime.parse(createdRaw) : null,
        ),
      );
    }
    return out;
  }

  Map<String, dynamic> _encodeUiMessage(Message m) {
    if (m is! TextMessage) {
      return {
        'id': m.id,
        'authorId': m.authorId,
        'text': '',
        if (m.createdAt != null) 'createdAt': m.createdAt!.toIso8601String(),
      };
    }
    return {
      'id': m.id,
      'authorId': m.authorId,
      'text': m.text,
      if (m.createdAt != null) 'createdAt': m.createdAt!.toIso8601String(),
    };
  }

  List<Map<String, dynamic>> _decodeMapList(dynamic raw) {
    if (raw is! List) return [];
    return raw
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }
}
