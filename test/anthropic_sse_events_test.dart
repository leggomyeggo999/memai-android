import 'package:flutter_test/flutter_test.dart';
import 'package:memai_android/core/llm/anthropic_sse_events.dart';

void main() {
  test('AnthropicSseSink merges multi-line data: payloads', () {
    final emitted = <Map<String, dynamic>>[];
    final sink = AnthropicSseSink(emitted.add);

    sink.addLine('event: message_start');
    sink.addLine('data: {"type":"message_start",');
    sink.addLine('data:  "message":{"id":"m1"}}');
    sink.addLine('');
    expect(emitted.length, 1);
    expect(emitted[0]['type'], 'message_start');

    sink.addLine('data: {"type":"ping"}');
    sink.addLine('');
    expect(emitted.length, 2);
    expect(emitted[1]['type'], 'ping');
  });

  test('AnthropicSseSink ignores comments and event lines', () {
    final emitted = <Map<String, dynamic>>[];
    final sink = AnthropicSseSink(emitted.add);

    sink.addLine(': keep-alive');
    sink.addLine('event: foo');
    sink.addLine('data: {"type":"message_stop"}');
    sink.addLine('');
    expect(emitted.length, 1);
    expect(emitted[0]['type'], 'message_stop');
  });

  test('AnthropicSseSink close flushes pending data', () {
    final emitted = <Map<String, dynamic>>[];
    final sink = AnthropicSseSink(emitted.add);
    sink.addLine('data: {"type":"error","error":"x"}');
    sink.close();
    expect(emitted.length, 1);
    expect(emitted[0]['type'], 'error');
  });
}
