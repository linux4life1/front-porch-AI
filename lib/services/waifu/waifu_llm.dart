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

import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/waifu/waifu_compact.dart';
import 'package:front_porch_ai/services/llm_service.dart';
import 'package:front_porch_ai/services/storage_service.dart';
import 'package:front_porch_ai/services/tool_choice_style_probe.dart';

/// Think budget for a coding turn. `0` is unlimited on several hosts.
/// `enabled: false` adds `exclude: true`, which hides thoughts and does
/// not stop GLM 5.3. 8192 tokens at ~20 tok/s is ~400s — a novel, not a
/// patch. 512 is enough to look at a screenshot and pick a tool.
/// Do not send `effort`: GLM 5.3 remaps `low`→`high` and then fills the
/// whole budget.
const kWaifuThinkCapTokens = 512;

/// Wrap-up (no tools). A 512-token think on Nano-GPT is ~2 minutes.
const kWaifuWrapThinkCapTokens = 64;

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

/// Thin generateWithTools door. Production wraps [LLMService]; tests inject
/// [ScriptedWaifuLlm]. Waifu Coder does not construct ChatService.
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

  /// Fail-closed door. Scripted tests default true; `.unsupported()` stays
  /// a generate-null path so that receipt is still covered.
  bool get toolsSupported => true;
}

class LlmServiceWaifuLlm implements WaifuLlm {
  LlmServiceWaifuLlm(
    this._serviceOf, {
    this.settingsOf,
    this.storage,
    this.remainingTokensOf,
  });

  /// Fresh each call so Model Settings swapping backends takes effect.
  final LLMService Function() _serviceOf;
  final ChatGenerationSettings Function()? settingsOf;
  final StorageService? storage;

  /// Remaining context for this turn. Chat Max Output Tokens is ignored.
  final int Function()? remainingTokensOf;

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
  }) {
    final g = settingsOf?.call();
    final s = storage;
    final toolsOn = tools.isNotEmpty;
    return _serviceOf().generateWithTools(
      GenerationParams(
        prompt: prompt,
        systemPrompt: systemPrompt,
        chatMessages: messages,
        maxLength:
            maxTokens ??
            remainingTokensOf?.call() ??
            waifuOutputTokenBudget(budget: kWaifuDefaultContextTokens, used: 0),
        minLength: 0,
        temperature: g != null && s != null ? g.resolveTemperature(s) : 0.7,
        minP: g != null && s != null ? g.resolveMinP(s) : 0.0,
        topP: g != null && s != null ? g.resolveTopP(s) : 0.9,
        topK: g != null && s != null ? g.resolveTopK(s) : 0,
        // Visible short think, then a tool. Off+exclude hides the chevron
        // and does not stop GLM 5.3. Empty effort: do not remap Low→High.
        // Required only when the harness asks — after the first tool, auto.
        reasoningEnabled: true,
        reasoningEffort: '',
        reasoningMaxTokens: toolsOn
            ? kWaifuThinkCapTokens
            : kWaifuWrapThinkCapTokens,
        toolChoice: toolsOn && forceTool ? kToolChoiceRequired : null,
        images: images,
        onChunk: onChunk,
      ),
      tools,
    );
  }

  @override
  void abort() => _serviceOf().abortGeneration();

  /// Production wrap has no probe of its own. Session / ChatService stamp
  /// the fail-closed verdict; this door stays open unless a test injects
  /// [ScriptedWaifuLlm] with `toolsSupported: false`.
  @override
  bool get toolsSupported => true;
}

/// Deterministic LLM for harness tests and widget pumps.
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
