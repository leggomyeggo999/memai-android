import 'package:flutter_test/flutter_test.dart';
import 'package:memai_android/core/llm/gemini_stream_round.dart';

void main() {
  test('GeminiStreamRoundAccumulator merges text', () {
    final a = GeminiStreamRoundAccumulator();
    a.ingestResponseJson({
      'candidates': [
        {'content': {'parts': [{'text': 'Hello'}, {'text': ' world'}]}},
      ],
    });
    expect(a.textSoFar, 'Hello world');
    expect(a.sawFunction, false);
    expect(a.hasToolCalls, false);
    final msg = a.buildModelContentMessage();
    expect(msg['role'], 'model');
    expect(msg['parts'], [
      {'text': 'Hello world'},
    ]);
  });

  test('GeminiStreamRoundAccumulator merges functionCall at repeated index', () {
    final a = GeminiStreamRoundAccumulator();
    a.ingestResponseJson({
      'candidates': [
        {
          'content': {
            'parts': [
              {'functionCall': {'name': 'search_notes'}},
            ],
          },
        },
      ],
    });
    a.ingestResponseJson({
      'candidates': [
        {
          'content': {
            'parts': [
              {
                'functionCall': {'args': {'query': 'q'}},
              },
            ],
          },
        },
      ],
    });
    expect(a.hasToolCalls, true);
    final inv = a.toolInvocationsSync().toList();
    expect(inv.length, 1);
    expect(inv[0].name, 'search_notes');
    expect(inv[0].args['query'], 'q');
  });

  test(
    'GeminiStreamRoundAccumulator uses new slot when single part switches name',
    () {
      final a = GeminiStreamRoundAccumulator();
      a.ingestResponseJson({
        'candidates': [
          {
            'content': {
              'parts': [
                {'functionCall': {'name': 'search_notes'}},
              ],
            },
          },
        ],
      });
      a.ingestResponseJson({
        'candidates': [
          {
            'content': {
              'parts': [
                {'functionCall': {'name': 'get_note'}},
              ],
            },
          },
        ],
      });
      expect(a.toolInvocationsSync().length, 2);
    },
  );

  test('GeminiSseSink decodes lines', () {
    final payloads = <Map<String, dynamic>>[];
    final s = GeminiSseSink(payloads.add);
    s.acceptLine(
      r'data: {"candidates":[{"content":{"parts":[{"text":"A"}]}}]}',
    );
    expect(payloads.length, 1);
    expect(
      (payloads[0]['candidates'] as List).length,
      1,
    );
  });

  test('promptFeedback sets blockReason', () {
    final a = GeminiStreamRoundAccumulator();
    a.ingestResponseJson({'promptFeedback': {'blockReason': 'SAFETY'}});
    expect(a.blockReason, 'SAFETY');
  });
}
