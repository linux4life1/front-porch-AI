// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// This file is part of Front Porch AI.
//
// Front Porch AI is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// Front Porch AI is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
// GNU Affero General Public License for more details.
//
// You should have received a copy of the GNU Affero General Public License
// along with Front Porch AI. If not, see <https://www.gnu.org/licenses/>.

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'package:front_porch_ai/services/llm_service.dart';
import 'package:front_porch_ai/services/reasoning_stream_wrapper.dart';

/// Incremental OpenAI `delta.tool_calls` + reasoning/content. Pure: tests
/// feed maps, production feeds SSE.
class OpenAiToolStreamParser {
  OpenAiToolStreamParser({required bool wrap, bool salvage = false})
    : _ingest = ReasoningIngest(wrap: wrap, salvage: salvage);

  final ReasoningIngest _ingest;
  final _calls = <int, _Acc>{};
  final text = StringBuffer();
  final reasoning = StringBuffer();
  var _closed = false;

  /// Returns text the UI should append (think-wrapped), or empty.
  String onDelta(Map<dynamic, dynamic> delta) {
    final out = StringBuffer();
    final rawReason = delta['reasoning_content'] ?? delta['reasoning'];
    if (rawReason is String && rawReason.isNotEmpty) {
      reasoning.write(rawReason);
      final chunk = _ingest.onReasoning(rawReason);
      if (chunk.isNotEmpty) out.write(chunk);
    }
    final content = delta['content'];
    if (content is String && content.isNotEmpty) {
      text.write(content);
      final chunk = _ingest.onContent(content);
      if (chunk.isNotEmpty) out.write(chunk);
    }
    final tcs = delta['tool_calls'];
    if (tcs is List) {
      for (final tc in tcs) {
        if (tc is! Map) continue;
        final idx = tc['index'] is int
            ? tc['index'] as int
            : int.tryParse('${tc['index']}') ?? 0;
        final slot = _calls.putIfAbsent(idx, _Acc.new);
        if (tc['id'] is String && (tc['id'] as String).isNotEmpty) {
          slot.id = tc['id'] as String;
        }
        final fn = tc['function'];
        if (fn is Map) {
          final name = fn['name'];
          if (name is String && name.isNotEmpty) slot.name = name;
          final args = fn['arguments'];
          if (args is String) slot.args.write(args);
        }
      }
    }
    return out.toString();
  }

  /// Close an open think block. Idempotent. Yield this through [onChunk].
  String closeThink() {
    if (_closed) return '';
    _closed = true;
    return _ingest.finish();
  }

  LlmToolResponse toResponse() {
    final calls = <LlmToolCall>[];
    final keys = _calls.keys.toList()..sort();
    for (final k in keys) {
      final slot = _calls[k]!;
      if (slot.name.isEmpty) continue;
      Map<String, dynamic> args = const {};
      final raw = slot.args.toString();
      if (raw.isNotEmpty) {
        try {
          final decoded = jsonDecode(raw);
          if (decoded is Map) args = Map<String, dynamic>.from(decoded);
        } catch (_) {}
      }
      calls.add(LlmToolCall(name: slot.name, arguments: args));
    }
    return LlmToolResponse(
      calls: calls,
      text: text.toString(),
      reasoning: reasoning.toString(),
    );
  }
}

class _Acc {
  String id = '';
  String name = '';
  final args = StringBuffer();
}

/// Consume an OpenAI SSE byte stream into [LlmToolResponse], forwarding
/// think-wrapped chunks to [onChunk] as they arrive.
Future<LlmToolResponse?> consumeOpenAiToolSse(
  Stream<List<int>> bytes, {
  required bool wrap,
  bool salvage = false,
  void Function(String chunk)? onChunk,
}) async {
  final parser = OpenAiToolStreamParser(wrap: wrap, salvage: salvage);
  var buffer = '';
  await for (final chunk in bytes.transform(utf8.decoder)) {
    buffer += chunk;
    while (buffer.contains('\n')) {
      final idx = buffer.indexOf('\n');
      final line = buffer.substring(0, idx).trim();
      buffer = buffer.substring(idx + 1);
      if (line.isEmpty) continue;
      if (line == 'data: [DONE]' || line == 'data:[DONE]') {
        final tail = parser.closeThink();
        if (tail.isNotEmpty) onChunk?.call(tail);
        return parser.toResponse();
      }
      if (!line.startsWith('data:')) continue;
      final data = line.startsWith('data: ')
          ? line.substring(6)
          : line.substring(5);
      _ingestDataLine(parser, data, onChunk);
    }
  }
  final remaining = buffer.trim();
  if (remaining.isNotEmpty && remaining.startsWith('data:')) {
    final data = remaining.startsWith('data: ')
        ? remaining.substring(6)
        : remaining.substring(5);
    if (data != '[DONE]') _ingestDataLine(parser, data, onChunk);
  }
  final tail = parser.closeThink();
  if (tail.isNotEmpty) onChunk?.call(tail);
  return parser.toResponse();
}

void _ingestDataLine(
  OpenAiToolStreamParser parser,
  String data,
  void Function(String chunk)? onChunk,
) {
  try {
    final json = jsonDecode(data);
    if (json is! Map) return;
    final choices = json['choices'];
    final choice = choices is List && choices.isNotEmpty ? choices.first : null;
    if (choice is! Map) return;
    if (choice['finish_reason'] == 'length') {
      debugPrint(
        '[OpenAiChat] streamed tool call hit max_tokens '
        '(finish_reason=length)',
      );
    }
    final delta = choice['delta'];
    if (delta is! Map) return;
    final out = parser.onDelta(delta);
    if (out.isNotEmpty) onChunk?.call(out);
  } catch (_) {}
}

/// POST `/chat/completions` with `stream: true` and tools. Same contract as
/// the non-stream door: null = unusable answer, throw = transport.
Future<LlmToolResponse?> streamOpenAiChatTools({
  required Uri uri,
  required Map<String, String> headers,
  required Map<String, dynamic> payload,
  required http.Client client,
  required bool wrapReasoning,
  bool salvage = false,
  void Function(String chunk)? onChunk,
}) async {
  payload['stream'] = true;
  final request = http.Request('POST', uri);
  request.headers.addAll(headers);
  request.body = jsonEncode(payload);
  final response = await client.send(request);
  if (response.statusCode == 429 || response.statusCode >= 500) {
    throw LlmToolTransportException(
      'tool call HTTP ${response.statusCode} (server busy/unavailable)',
    );
  }
  if (response.statusCode != 200) {
    debugPrint(
      '[OpenAiChat] Streamed tool call rejected '
      '(HTTP ${response.statusCode}) — falling back to text transport',
    );
    return null;
  }
  return consumeOpenAiToolSse(
    response.stream,
    wrap: wrapReasoning,
    salvage: salvage,
    onChunk: onChunk,
  );
}
