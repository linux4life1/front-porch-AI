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

import 'package:front_porch_ai/services/llm_service.dart';

/// MiniMax / GLM / Qwen often dump tool protocol into `content` when the
/// backend did not parse native `tool_calls`. Those tokens are never speech.
final _section = RegExp(
  r'◁\s*tool_calls_section_begin\s*▷[\s\S]*?(?:◁\s*tool_calls_section_end\s*▷|$)',
  caseSensitive: false,
);
final _sectionPipe = RegExp(
  r'<\|tool_calls_section_begin\|>[\s\S]*?(?:<\|tool_calls_section_end\|>|$)',
  caseSensitive: false,
);
final _callBlock = RegExp(
  r'◁\s*tool_call_begin\s*▷[\s\S]*?(?:◁\s*tool_call_end\s*▷|$)',
  caseSensitive: false,
);
final _callPipe = RegExp(
  r'<\|tool_call_begin\|>[\s\S]*?(?:<\|tool_call_end\|>|$)',
  caseSensitive: false,
);
final _xmlCall = RegExp(
  r'<tool_call>[\s\S]*?</tool_call>',
  caseSensitive: false,
);
final _fnTag = RegExp(
  r'<function=\w+>[\s\S]*?(?:</function>|$)',
  caseSensitive: false,
);

final _minimaxCall = RegExp(
  r'◁\s*tool_call_begin\s*▷\s*'
  r'(?:functions[/.\s]*)?([A-Za-z_][\w]*)(?::\d+)?\s*'
  r'◁\s*tool_call_argument_begin\s*▷\s*'
  r'(\{[\s\S]*?\})',
  caseSensitive: false,
);
final _minimaxPipe = RegExp(
  r'<\|tool_call_begin\|>\s*'
  r'(?:functions[/.\s]*)?([A-Za-z_][\w]*)(?::\d+)?\s*'
  r'<\|tool_call_argument_begin\|>\s*'
  r'(\{[\s\S]*?\})',
  caseSensitive: false,
);
final _xmlJson = RegExp(
  r'<tool_call>\s*(\{[\s\S]*?\})\s*</tool_call>',
  caseSensitive: false,
);

String waifuStripToolLeak(String raw) {
  var t = raw;
  t = t.replaceAll(_section, '');
  t = t.replaceAll(_sectionPipe, '');
  t = t.replaceAll(_callBlock, '');
  t = t.replaceAll(_callPipe, '');
  t = t.replaceAll(_xmlCall, '');
  t = t.replaceAll(_fnTag, '');
  return t.replaceAll(RegExp(r'\n{3,}'), '\n\n').trim();
}

List<LlmToolCall> waifuLeakedToolCalls(String raw) {
  final out = <LlmToolCall>[];
  void add(String name, String json) {
    final n = name.trim();
    if (n.isEmpty) return;
    try {
      final decoded = jsonDecode(json);
      if (decoded is Map<String, dynamic>) {
        out.add(LlmToolCall(name: n, arguments: decoded));
        return;
      }
      if (decoded is Map) {
        out.add(
          LlmToolCall(name: n, arguments: Map<String, dynamic>.from(decoded)),
        );
      }
    } catch (_) {}
  }

  for (final m in _minimaxCall.allMatches(raw)) {
    add(m.group(1) ?? '', m.group(2) ?? '');
  }
  for (final m in _minimaxPipe.allMatches(raw)) {
    add(m.group(1) ?? '', m.group(2) ?? '');
  }
  for (final m in _xmlJson.allMatches(raw)) {
    try {
      final decoded = jsonDecode(m.group(1) ?? '');
      if (decoded is! Map) continue;
      final name = (decoded['name'] ?? decoded['tool'] ?? '').toString();
      final args = decoded['arguments'] ?? decoded['params'] ?? decoded;
      if (args is Map) {
        add(name, jsonEncode(Map<String, dynamic>.from(args)));
      }
    } catch (_) {}
  }
  return out;
}

List<LlmToolCall> waifuEffectiveToolCalls(LlmToolResponse resp) {
  if (resp.calls.isNotEmpty) return resp.calls;
  return waifuLeakedToolCalls(resp.text);
}
