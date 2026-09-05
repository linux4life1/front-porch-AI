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

class DeskLlmTurn {
  const DeskLlmTurn({
    required this.systemPrompt,
    required this.prompt,
    required this.tools,
  });

  final String systemPrompt;
  final String prompt;
  final List<Map<String, dynamic>> tools;
}

/// Thin generateWithTools door. Production wraps [LLMService]; tests inject
/// [ScriptedDeskLlm]. Desk does not construct ChatService.
abstract class DeskLlm {
  Future<LlmToolResponse?> generate({
    required String systemPrompt,
    required String prompt,
    required List<Map<String, dynamic>> tools,
  });

  void abort() {}
}

class LlmServiceDeskLlm implements DeskLlm {
  LlmServiceDeskLlm(this._llm);

  final LLMService _llm;

  @override
  Future<LlmToolResponse?> generate({
    required String systemPrompt,
    required String prompt,
    required List<Map<String, dynamic>> tools,
  }) {
    return _llm.generateWithTools(
      GenerationParams(
        prompt: prompt,
        systemPrompt: systemPrompt,
        maxLength: 4096,
        temperature: 0.4,
      ),
      tools,
    );
  }

  @override
  void abort() => _llm.abortGeneration();
}

/// Deterministic LLM for harness tests and widget pumps.
class ScriptedDeskLlm implements DeskLlm {
  ScriptedDeskLlm(List<LlmToolResponse?> script, {this.beforeGenerate})
    : _script = script,
      _repeat = false,
      _unsupported = false;

  ScriptedDeskLlm.repeat(LlmToolResponse response, {this.beforeGenerate})
    : _script = [response],
      _repeat = true,
      _unsupported = false;

  ScriptedDeskLlm.unsupported({this.beforeGenerate})
    : _script = const [],
      _repeat = false,
      _unsupported = true;

  final List<LlmToolResponse?> _script;
  final bool _repeat;
  final bool _unsupported;
  final Future<void> Function(int i)? beforeGenerate;

  final calls = <DeskLlmTurn>[];
  int? waitingAt;
  bool aborted = false;
  int _i = 0;

  @override
  Future<LlmToolResponse?> generate({
    required String systemPrompt,
    required String prompt,
    required List<Map<String, dynamic>> tools,
  }) async {
    waitingAt = _i;
    await beforeGenerate?.call(_i);
    waitingAt = null;
    if (aborted) {
      return const LlmToolResponse(calls: [], text: '');
    }
    calls.add(
      DeskLlmTurn(systemPrompt: systemPrompt, prompt: prompt, tools: tools),
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
