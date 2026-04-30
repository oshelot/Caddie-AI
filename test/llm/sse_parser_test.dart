// Tests for the OpenAI-compatible SSE parser used by the LLM
// router (KAN-294 / S7.3).
//
// **AC #1 (streaming):** chunks accumulate in order, [DONE]
// terminates the stream, malformed lines are tolerated. Every
// test below exercises a different facet of that requirement
// against synthetic SSE strings — no real HTTP traffic.

import 'package:caddieai/core/llm/sse_parser.dart';
import 'package:flutter_test/flutter_test.dart';

Stream<String> _stream(List<String> chunks) =>
    Stream.fromIterable(chunks);

void main() {
  group('parseOpenAiSseStream', () {
    test('extracts content deltas in order', () async {
      final input = _stream([
        'data: {"choices":[{"delta":{"content":"Hello"}}]}\n',
        'data: {"choices":[{"delta":{"content":" "}}]}\n',
        'data: {"choices":[{"delta":{"content":"world"}}]}\n',
        'data: [DONE]\n',
      ]);
      final deltas = await parseOpenAiSseStream(input).toList();
      expect(deltas, ['Hello', ' ', 'world']);
    });

    test('[DONE] sentinel terminates the stream early', () async {
      final input = _stream([
        'data: {"choices":[{"delta":{"content":"first"}}]}\n',
        'data: [DONE]\n',
        'data: {"choices":[{"delta":{"content":"never seen"}}]}\n',
      ]);
      final deltas = await parseOpenAiSseStream(input).toList();
      expect(deltas, ['first']);
    });

    test('tolerates malformed JSON in a data: line', () async {
      final input = _stream([
        'data: {"choices":[{"delta":{"content":"good"}}]}\n',
        'data: {malformed garbage\n',
        'data: {"choices":[{"delta":{"content":"after"}}]}\n',
        'data: [DONE]\n',
      ]);
      final deltas = await parseOpenAiSseStream(input).toList();
      expect(deltas, ['good', 'after']);
    });

    test('tolerates SSE comment lines (`: keepalive`)', () async {
      final input = _stream([
        ': keepalive\n',
        'data: {"choices":[{"delta":{"content":"hi"}}]}\n',
        ': another comment\n',
        'data: [DONE]\n',
      ]);
      final deltas = await parseOpenAiSseStream(input).toList();
      expect(deltas, ['hi']);
    });

    test('tolerates an SSE event split across multiple HTTP chunks',
        () async {
      // Real HTTP delivery splits SSE events arbitrarily — the
      // parser must buffer until it sees a newline.
      final input = _stream([
        'data: {"choices":[{"delta":',
        '{"content":"split"}}]}\n',
        'data: [DONE]\n',
      ]);
      final deltas = await parseOpenAiSseStream(input).toList();
      expect(deltas, ['split']);
    });

    test('skips empty lines and choices without delta.content', () async {
      final input = _stream([
        '\n',
        'data: {"choices":[{"delta":{}}]}\n',
        'data: {"choices":[{"delta":{"content":"good"}}]}\n',
        'data: [DONE]\n',
      ]);
      final deltas = await parseOpenAiSseStream(input).toList();
      expect(deltas, ['good']);
    });

    test('handles a final delta with no trailing newline', () async {
      final input = _stream([
        'data: {"choices":[{"delta":{"content":"first"}}]}\n',
        'data: {"choices":[{"delta":{"content":"last"}}]}',
      ]);
      final deltas = await parseOpenAiSseStream(input).toList();
      expect(deltas, ['first', 'last']);
    });

    test('returns empty for an empty stream', () async {
      final deltas = await parseOpenAiSseStream(_stream([])).toList();
      expect(deltas, isEmpty);
    });
  });

  group('accumulateSseStream', () {
    test('joins all deltas into a single string', () async {
      final input = _stream([
        'data: {"choices":[{"delta":{"content":"Hello"}}]}\n',
        'data: {"choices":[{"delta":{"content":", "}}]}\n',
        'data: {"choices":[{"delta":{"content":"world!"}}]}\n',
        'data: [DONE]\n',
      ]);
      final accumulated = await accumulateSseStream(input);
      expect(accumulated, 'Hello, world!');
    });
  });
}
