import 'dart:convert';

/// Parses Claude Messages API SSE: `event:` lines are ignored; `data:` payloads
/// are concatenated until a blank line, then decoded as JSON.
///
/// References: https://docs.claude.com/en/api/messages-streaming
final class AnthropicSseSink {
  AnthropicSseSink(this._emit);

  final void Function(Map<String, dynamic> payload) _emit;

  final List<String> _dataChunks = [];

  void addLine(String line) {
    final t =
        line.isEmpty ? line : line.replaceFirst(RegExp(r'\r$'), '');
    if (t.isEmpty) {
      _flush();
      return;
    }
    if (t.startsWith(':')) return;
    if (t.startsWith('event:')) return;
    if (t.startsWith('data:')) {
      _dataChunks.add(t.substring(5).trim());
    }
  }

  void close() => _flush();

  void _flush() {
    if (_dataChunks.isEmpty) return;
    final merged = _dataChunks.join('\n');
    _dataChunks.clear();
    try {
      final decoded = jsonDecode(merged);
      if (decoded is Map<String, dynamic>) {
        _emit(decoded);
      }
    } catch (_) {}
  }
}
