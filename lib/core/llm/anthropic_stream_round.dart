import 'dart:convert';

/// Builds Anthropic Messages `assistant` `content` from one streamed round.
///
/// Implements `content_block_*` deltas from
/// https://docs.claude.com/en/api/messages-streaming
final class AnthropicStreamRoundAccumulator {
  AnthropicStreamRoundAccumulator();

  final Map<int, _BlockScratch> blocks = {};

  bool streamComplete = false;

  void ingestEvent(Map<String, dynamic> j) {
    switch (j['type']) {
      case 'ping':
      case 'message_start':
      case 'message_delta':
        return;
      case 'error':
        final err = j['error'];
        throw StateError('Anthropic SSE error: $err');
      case 'content_block_start':
        blocks[j['index'] as int] = _BlockScratch.fromStart(
          Map<String, dynamic>.from(j['content_block'] as Map),
        );
        return;
      case 'content_block_delta':
        blocks[j['index'] as int]
            ?.delta(Map<String, dynamic>.from(j['delta'] as Map));
        return;
      case 'content_block_stop':
        blocks[j['index'] as int]?.finalize();
        return;
      case 'message_stop':
        streamComplete = true;
        return;
      default:
        return;
    }
  }

  /// Text segments only (omit thinking for the composer bubble).
  String userVisibleText() {
    final keys = blocks.keys.toList()..sort();
    final sb = StringBuffer();
    for (final k in keys) {
      final b = blocks[k]!;
      if (b.kind == BlockKind.text) sb.write(b.textBuf.toString());
    }
    return sb.toString();
  }

  List<Map<String, dynamic>> assistantContentBlocks() {
    final keys = blocks.keys.toList()..sort();
    final out = <Map<String, dynamic>>[];
    for (final k in keys) {
      final m = blocks[k]!.toApiContentBlock();
      if (m != null) out.add(m);
    }
    return out;
  }

  bool get hasToolUse =>
      blocks.values.any((b) => b.kind == BlockKind.toolUse);
}

enum BlockKind { text, toolUse, thinking, unknown }

final class _BlockScratch {
  _BlockScratch._({required this.kind});

  BlockKind kind;
  final textBuf = StringBuffer();
  final partialJsonBuf = StringBuffer();
  final thinkingBuf = StringBuffer();
  String? signature;
  String? toolId;
  String? toolName;

  factory _BlockScratch.fromStart(Map<String, dynamic> cb) {
    final t = cb['type'] as String?;
    switch (t) {
      case 'text':
        return _BlockScratch._(kind: BlockKind.text);
      case 'tool_use':
        final b = _BlockScratch._(kind: BlockKind.toolUse);
        b.toolId = cb['id'] as String?;
        b.toolName = cb['name'] as String?;
        return b;
      case 'thinking':
        return _BlockScratch._(kind: BlockKind.thinking);
      default:
        return _BlockScratch._(kind: BlockKind.unknown);
    }
  }

  void delta(Map<String, dynamic> d) {
    switch (d['type']) {
      case 'text_delta':
        textBuf.write(d['text'] as String? ?? '');
        return;
      case 'input_json_delta':
        partialJsonBuf.write(d['partial_json'] as String? ?? '');
        return;
      case 'thinking_delta':
        thinkingBuf.write(d['thinking'] as String? ?? '');
        return;
      case 'signature_delta':
        signature = d['signature'] as String?;
        return;
      default:
        return;
    }
  }

  void finalize() {}

  Map<String, dynamic>? toApiContentBlock() {
    switch (kind) {
      case BlockKind.text:
        return {'type': 'text', 'text': textBuf.toString()};
      case BlockKind.toolUse:
        final raw = partialJsonBuf.toString().trim();
        Map<String, dynamic> input;
        try {
          final decoded =
              raw.isEmpty ? <String, dynamic>{} : jsonDecode(raw);
          input = decoded is Map<String, dynamic>
              ? decoded
              : <String, dynamic>{};
        } catch (_) {
          input = <String, dynamic>{};
        }
        return {
          'type': 'tool_use',
          'id': toolId ?? 'tool_unknown',
          'name': toolName ?? '',
          'input': input,
        };
      case BlockKind.thinking:
        final tb = thinkingBuf.toString();
        final sig = signature;
        if (tb.isEmpty && (sig == null || sig.isEmpty)) return null;
        final m = <String, dynamic>{'type': 'thinking', 'thinking': tb};
        if (sig != null && sig.isNotEmpty) {
          m['signature'] = sig;
        }
        return m;
      default:
        return null;
    }
  }
}
