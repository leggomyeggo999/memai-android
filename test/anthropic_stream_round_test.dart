import 'package:flutter_test/flutter_test.dart';
import 'package:memai_android/core/llm/anthropic_stream_round.dart';

void main() {
  test('AnthropicStreamRoundAccumulator builds text + tool_use', () {
    final a = AnthropicStreamRoundAccumulator();

    a.ingestEvent({
      'type': 'content_block_start',
      'index': 0,
      'content_block': {'type': 'text', 'text': ''},
    });
    a.ingestEvent({
      'type': 'content_block_delta',
      'index': 0,
      'delta': {'type': 'text_delta', 'text': 'Hi'},
    });
    expect(a.userVisibleText(), 'Hi');

    a.ingestEvent({
      'type': 'content_block_start',
      'index': 1,
      'content_block': {
        'type': 'tool_use',
        'id': 'toolu_test',
        'name': 'search_notes',
        'input': {},
      },
    });
    a.ingestEvent({
      'type': 'content_block_delta',
      'index': 1,
      'delta': {'type': 'input_json_delta', 'partial_json': '{"query":"x"}'},
    });
    a.ingestEvent({'type': 'content_block_stop', 'index': 1});
    a.ingestEvent({'type': 'content_block_stop', 'index': 0});
    a.ingestEvent({'type': 'message_stop'});

    expect(a.hasToolUse, true);
    expect(a.userVisibleText(), 'Hi');
    final blocks = a.assistantContentBlocks();
    expect(blocks.any((b) => b['type'] == 'tool_use'), true);
  });
}
