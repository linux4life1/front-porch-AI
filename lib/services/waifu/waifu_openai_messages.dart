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

import 'package:front_porch_ai/services/waifu/waifu_coworker_prompt.dart';
import 'package:front_porch_ai/services/waifu/waifu_jail.dart';
import 'package:front_porch_ai/services/waifu/waifu_session.dart';
import 'package:front_porch_ai/services/waifu/waifu_sit_down.dart';

/// OpenAI chat messages for Waifu: system is separate; here is user +
/// assistant tool_calls + tool results. Chat's single user blob is unchanged.
List<Map<String, Object>> waifuOpenAiMessages({
  required String folderName,
  required String coworkerName,
  required List<WaifuMessage> transcript,
  required String todos,
  required String mentionBlock,
  String skillBlock = '',
  String mcpBlock = '',
  bool preserveThinking = false,
  WaifuPathMode pathMode = WaifuPathMode.folderJail,
  int taskDepthRemaining = 3,
  String turnContractCue = '',
  WaifuMode mode = WaifuMode.build,
  String planBlock = '',
}) {
  final prefix = waifuLoopUserPrompt(
    folderName: folderName,
    coworkerName: coworkerName,
    transcript: const [],
    todos: todos,
    mentionBlock: mentionBlock,
    skillBlock: skillBlock,
    mcpBlock: mcpBlock,
    preserveThinking: preserveThinking,
    pathMode: pathMode,
    taskDepthRemaining: taskDepthRemaining,
    turnContractCue: turnContractCue,
    mode: mode,
    planBlock: planBlock,
  );
  final out = <Map<String, Object>>[
    {'role': 'user', 'content': prefix},
  ];
  final pending = <WaifuMessage>[];
  void flushTools() {
    if (pending.isEmpty) return;
    final calls = <Map<String, Object>>[];
    for (var i = 0; i < pending.length; i++) {
      final t = pending[i];
      final name = (t.toolName ?? 'tool').trim();
      final id = (t.toolCallId != null && t.toolCallId!.isNotEmpty)
          ? t.toolCallId!
          : 'waifu_${name}_$i';
      calls.add({
        'id': id,
        'type': 'function',
        'function': {
          'name': name.isEmpty ? 'tool' : name,
          'arguments': jsonEncode(t.toolArgs ?? const <String, dynamic>{}),
        },
      });
    }
    out.add({'role': 'assistant', 'content': '', 'tool_calls': calls});
    for (var i = 0; i < pending.length; i++) {
      final t = pending[i];
      final name = (t.toolName ?? 'tool').trim();
      final id = (t.toolCallId != null && t.toolCallId!.isNotEmpty)
          ? t.toolCallId!
          : 'waifu_${name}_$i';
      out.add({
        'role': 'tool',
        'tool_call_id': id,
        'content': waifuToolPromptLine(t),
      });
    }
    pending.clear();
  }

  for (final m in transcript) {
    switch (m.kind) {
      case WaifuMsgKind.tool:
        pending.add(m);
      case WaifuMsgKind.user:
        flushTools();
        out.add({'role': 'user', 'content': m.text});
      case WaifuMsgKind.recap:
        flushTools();
        final recap = waifuPromptSpeech(
          m,
          coworkerName,
          preserveThinking: false,
        );
        if (recap.isNotEmpty) out.add({'role': 'user', 'content': recap});
      case WaifuMsgKind.assistant:
        flushTools();
        final line = waifuPromptSpeech(
          m,
          coworkerName,
          preserveThinking: preserveThinking,
        );
        if (line.isEmpty) break;
        final spoken = line.startsWith('$coworkerName: ')
            ? line.substring(coworkerName.length + 2)
            : line;
        out.add({'role': 'assistant', 'content': spoken});
    }
  }
  flushTools();
  return out;
}

/// Flat projection of the live [messages] request. Meter and scripted
/// tests read this; generate sends the structured list. One request.
String waifuMessagesMeterText(List<Map<String, Object>> messages) {
  final buf = StringBuffer();
  for (final m in messages) {
    final content = m['content'];
    if (content is String && content.isNotEmpty) buf.writeln(content);
    final calls = m['tool_calls'];
    if (calls != null) buf.writeln(calls);
  }
  return buf.toString();
}
