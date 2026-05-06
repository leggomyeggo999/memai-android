import 'package:flutter_test/flutter_test.dart';
import 'package:memai_android/core/llm/openai_stream_accumulator.dart';

void main() {
  test('accumulates streamed text only', () {
    final a = OpenAiStreamAccumulator();
    a.acceptLine(
      r'data: {"choices":[{"delta":{"content":"Hello"}}]}',
    );
    a.acceptLine(r'data: {"choices":[{"delta":{"content":" world"}}]}');
    a.acceptLine(r'data: [DONE]');
    expect(a.textSoFar, 'Hello world');
    expect(a.sawToolDelta, false);
    final m = a.buildAssistantMessage();
    expect(m['role'], 'assistant');
    expect(m['content'], 'Hello world');
  });

  test('accumulates tool call fragments', () {
    final a = OpenAiStreamAccumulator();
    a.acceptLine(
      r'data: {"choices":[{"delta":{"tool_calls":[{"index":0,"id":"call_x","type":"function","function":{"name":"search_notes","arguments":"{}"}}]}}]}',
    );
    expect(a.sawToolDelta, true);
    final m = a.buildAssistantMessage();
    expect(m['tool_calls'], isA<List<dynamic>>());
  });
}
