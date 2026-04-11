// SSE parser for OpenAI-compatible streaming chat-completion
// responses. Used by the LLM proxy and the direct OpenAI provider
// to transform a chunked HTTP body into a `Stream<String>` of
// content deltas.
//
// **Wire format** (from the OpenAI Chat Completions streaming
// spec):
//
//   data: {"id":"...","choices":[{"delta":{"content":"Hello"}}]}
//
//   data: {"id":"...","choices":[{"delta":{"content":" world"}}]}
//
//   data: [DONE]
//
// Each event line starts with `data: `. The terminator is the
// literal string `[DONE]`. Lines that don't start with `data: `
// are tolerated (some providers send keep-alive comments
// `:keepalive` between events). Malformed JSON in a `data:`
// payload is also tolerated — we just skip the line and continue,
// matching the iOS native's behavior of "best-effort streaming".
//
// **Why a separate file:** the parsing logic is non-trivial and
// gets reused by every streaming-capable provider. Splitting it
// out keeps each provider focused on transport, and lets the
// unit tests exercise the parser against synthetic SSE strings
// without standing up a real HTTP server.

import 'dart:convert';

/// Parses an OpenAI-style SSE chunk stream into a `Stream<String>`
/// of content deltas. The output stream emits ONLY the new text
/// from each chunk's `delta.content` field — callers that want
/// the full accumulated text should fold the deltas with
/// `await for (final chunk in stream) { acc += chunk; }`.
///
/// Each `rawChunk` from `input` may contain ZERO, ONE, or MANY
/// SSE event lines (HTTP chunks don't align with line boundaries).
/// The parser buffers across chunks until it sees a newline.
Stream<String> parseOpenAiSseStream(Stream<String> input) async* {
  var buffer = '';
  await for (final raw in input) {
    buffer += raw;
    // Process complete lines (ending in \n). Anything after the
    // last \n stays in the buffer for the next chunk.
    while (true) {
      final newlineIndex = buffer.indexOf('\n');
      if (newlineIndex < 0) break;
      final line = buffer.substring(0, newlineIndex).trimRight();
      buffer = buffer.substring(newlineIndex + 1);
      final delta = _processLine(line);
      if (delta == _doneSentinel) return;
      if (delta != null) yield delta;
    }
  }
  // Drain any final buffered line that didn't end in \n.
  final finalLine = buffer.trimRight();
  if (finalLine.isNotEmpty) {
    final delta = _processLine(finalLine);
    if (delta != null && delta != _doneSentinel) yield delta;
  }
}

/// Convenience: collapses the parsed delta stream into a single
/// final accumulated string. Used by the proxy's
/// `chatCompletionStream` end of the call when the caller wants
/// just the final text and doesn't need per-token rendering.
Future<String> accumulateSseStream(Stream<String> input) async {
  final buf = StringBuffer();
  await for (final delta in parseOpenAiSseStream(input)) {
    buf.write(delta);
  }
  return buf.toString();
}

/// Sentinel returned by `_processLine` when it sees `data: [DONE]`.
/// Distinct from `null` (which means "this line wasn't a content
/// delta — keep going").
const String _doneSentinel = '__SSE_DONE__';

String? _processLine(String line) {
  if (line.isEmpty) return null;
  // Comment lines (`: keepalive`) — ignore.
  if (line.startsWith(':')) return null;
  if (!line.startsWith('data:')) return null;
  final payload = line.substring(5).trimLeft();
  if (payload == '[DONE]') return _doneSentinel;
  try {
    final json = jsonDecode(payload) as Map<String, dynamic>;
    final choices = json['choices'] as List?;
    if (choices == null || choices.isEmpty) return null;
    final first = choices[0] as Map<String, dynamic>;
    final delta = first['delta'] as Map<String, dynamic>?;
    if (delta == null) return null;
    final content = delta['content'] as String?;
    if (content == null || content.isEmpty) return null;
    return content;
  } catch (_) {
    // Malformed JSON — skip the line and continue. Matches the
    // iOS native's "best-effort streaming" behavior.
    return null;
  }
}
