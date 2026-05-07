import 'dart:convert';

/// One streamed `streamGenerateContent` round (`?alt=sse`) → model `parts`
/// plus plain text for the typing indicator.
///
/// See: https://ai.google.dev/api/generate-content#method:-models.streamgeneratecontent
final class GeminiStreamRoundAccumulator {
  GeminiStreamRoundAccumulator();

  final StringBuffer _text = StringBuffer();
  final List<_FcSlot> _fcSlots = [];
  bool sawFunction = false;
  /// Set when JSON includes blocking `promptFeedback` (stream or unary).
  String? blockReason;

  String get textSoFar => _text.toString();

  void ingestResponseJson(Map<String, dynamic> json) {
    final pf = json['promptFeedback'];
    if (pf is Map<String, dynamic>) {
      final br = pf['blockReason'];
      if (br != null) {
        blockReason = br.toString();
      }
    }

    final cands = json['candidates'] as List<dynamic>?;
    if (cands == null || cands.isEmpty) return;
    final c0 = cands[0] as Map<String, dynamic>;
    final content = c0['content'] as Map<String, dynamic>?;
    if (content == null) return;
    final parts = content['parts'] as List<dynamic>?;
    if (parts == null) return;

    for (var i = 0; i < parts.length; i++) {
      final p = parts[i];
      if (p is! Map<String, dynamic>) continue;
      if (p['text'] is String && (p['text'] as String).isNotEmpty) {
        _text.write(p['text'] as String);
      }
      if (p.containsKey('functionCall')) {
        sawFunction = true;
        final fc = Map<String, dynamic>.from(p['functionCall'] as Map);
        final slotIx = _functionCallSlotIndex(fc, i, parts.length);
        _ensureSlot(slotIx).merge(fc);
      }
    }
  }

  /// Streams often send incremental `functionCall` chunks as `[parts][0]`; merge
  /// those into the last slot unless a new distinct `name` starts.
  int _functionCallSlotIndex(
    Map<String, dynamic> fc,
    int partIndexInMessage,
    int partCountInMessage,
  ) {
    if (partCountInMessage > 1) return partIndexInMessage;
    if (_fcSlots.isEmpty) return 0;
    final incomingName = fc['name'] as String?;
    final lastName = _fcSlots.last.name;
    if (incomingName != null &&
        incomingName.isNotEmpty &&
        lastName != null &&
        lastName.isNotEmpty &&
        incomingName != lastName) {
      return _fcSlots.length;
    }
    return _fcSlots.length - 1;
  }

  _FcSlot _ensureSlot(int i) {
    while (_fcSlots.length <= i) {
      _fcSlots.add(_FcSlot());
    }
    return _fcSlots[i];
  }

  /// `role: model` message to append to Gemini `contents` history.
  Map<String, dynamic> buildModelContentMessage() {
    final parts = <Map<String, dynamic>>[];
    final t = _text.toString();
    if (t.isNotEmpty) {
      parts.add({'text': t});
    }
    for (final s in _fcSlots) {
      if (s.name == null || s.name!.isEmpty) continue;
      parts.add({
        'functionCall': {'name': s.name, 'args': s.args},
      });
    }
    return {'role': 'model', 'parts': parts};
  }

  bool get hasToolCalls =>
      _fcSlots.any((s) => s.name != null && s.name!.isNotEmpty);

  Iterable<({String name, Map<String, dynamic> args})> toolInvocationsSync() sync* {
    for (final s in _fcSlots) {
      if (s.name == null || s.name!.isEmpty) continue;
      yield (name: s.name!, args: Map<String, dynamic>.from(s.args));
    }
  }
}

final class _FcSlot {
  String? name;
  Map<String, dynamic> args = {};

  void merge(Map<String, dynamic> fc) {
    final n = fc['name'];
    if (n is String && n.isNotEmpty) name = n;
    final a = fc['args'];
    if (a is Map<String, dynamic>) {
      args.addAll(a);
    }
  }
}

/// Parses Gemini SSE (`alt=sse`): lines `data:` with one JSON object per event.
final class GeminiSseSink {
  GeminiSseSink(this._onJson);

  final void Function(Map<String, dynamic> json) _onJson;

  void acceptLine(String line) {
    final trimmed = line.trim();
    if (trimmed.isEmpty || trimmed.startsWith(':')) return;
    if (!trimmed.startsWith('data:')) return;
    final payload = trimmed.substring(5).trim();
    if (payload.isEmpty) return;

    final dynamic decoded;
    try {
      decoded = jsonDecode(payload);
    } catch (_) {
      return;
    }
    if (decoded is Map<String, dynamic>) {
      _onJson(decoded);
    }
  }
}
