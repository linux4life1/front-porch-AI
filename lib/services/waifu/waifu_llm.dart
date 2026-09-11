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

import 'package:front_porch_ai/services/llm_service.dart';

/// Test-seam LLM. Production send talks to OpenCode, not this door.
class WaifuLlmTurn {
  const WaifuLlmTurn({
    required this.systemPrompt,
    required this.prompt,
    required this.tools,
    this.images,
    this.forceTool = false,
    this.maxTokens,
    this.messages,
  });

  final String systemPrompt;
  final String prompt;
  final List<Map<String, dynamic>> tools;
  final List<String>? images;
  final bool forceTool;
  final int? maxTokens;
  final List<Map<String, Object>>? messages;
}

abstract class WaifuLlm {
  Future<LlmToolResponse?> generate({
    required String systemPrompt,
    required String prompt,
    required List<Map<String, dynamic>> tools,
    List<String>? images,
    void Function(String chunk)? onChunk,
    int? maxTokens,
    bool forceTool = true,
    List<Map<String, Object>>? messages,
  });

  void abort() {}

  bool get toolsSupported => true;
}

/// Deterministic LLM so chrome tests can bind a harness without OpenCode.
class ScriptedWaifuLlm implements WaifuLlm {
  ScriptedWaifuLlm(
    List<LlmToolResponse?> script, {
    this.beforeGenerate,
    this.streamDuring,
    this.toolsSupported = true,
  }) : _script = script,
       _repeat = false,
       _unsupported = false;

  ScriptedWaifuLlm.repeat(
    LlmToolResponse response, {
    this.beforeGenerate,
    this.streamDuring,
    this.toolsSupported = true,
  }) : _script = [response],
       _repeat = true,
       _unsupported = false;

  ScriptedWaifuLlm.unsupported({
    this.beforeGenerate,
    this.streamDuring,
    this.toolsSupported = true,
  }) : _script = const [],
       _repeat = false,
       _unsupported = true;

  final List<LlmToolResponse?> _script;
  final bool _repeat;
  final bool _unsupported;
  @override
  final bool toolsSupported;
  final Future<void> Function(int i)? beforeGenerate;
  final Future<void> Function(int i, void Function(String chunk) onChunk)?
  streamDuring;

  final calls = <WaifuLlmTurn>[];
  int? waitingAt;
  bool aborted = false;
  int _i = 0;

  @override
  Future<LlmToolResponse?> generate({
    required String systemPrompt,
    required String prompt,
    required List<Map<String, dynamic>> tools,
    List<String>? images,
    void Function(String chunk)? onChunk,
    int? maxTokens,
    bool forceTool = true,
    List<Map<String, Object>>? messages,
  }) async {
    waitingAt = _i;
    await beforeGenerate?.call(_i);
    if (onChunk != null) await streamDuring?.call(_i, onChunk);
    waitingAt = null;
    if (aborted) {
      return const LlmToolResponse(calls: [], text: '');
    }
    calls.add(
      WaifuLlmTurn(
        systemPrompt: systemPrompt,
        prompt: prompt,
        tools: tools,
        images: images,
        forceTool: forceTool,
        maxTokens: maxTokens,
        messages: messages,
      ),
    );
    if (_unsupported) return null;
    if (_repeat) {
      _i++;
      return _script.first;
    }
    if (_i >= _script.length) {
      return const LlmToolResponse(calls: [], text: 'done');
    }
    return _script[_i++];
  }

  @override
  void abort() {
    aborted = true;
  }
}
