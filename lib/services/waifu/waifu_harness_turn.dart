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

part of 'waifu_harness.dart';

extension _WaifuHarnessTurn on WaifuHarness {
  Future<void> _loop() async {
    final system = _system();
    for (var step = 0; step < kWaifuMaxSteps; step++) {
      if (_aborted) return;
      _beginStream();
      final prompt = _prompt();
      _setBudget(system, prompt);
      final resp = await llm.generate(
        systemPrompt: system,
        prompt: prompt,
        tools: _turn.speechOnly
            ? const <Map<String, dynamic>>[]
            : waifuAdvertisedTools(
                exploreOnly: exploreOnly,
                includeWebSearch: webSearch != null,
                mcpOptIn: mcpOptIn,
                mcpTools: mcpTools,
                includeTask: depth < kWaifuMaxTaskDepth,
                includeWorkflow: depth == 0,
                pathMode: session.pathMode,
                mode: session.mode,
              ),
        images: step == 0 ? _turnImages : null,
        onChunk: _onChunk,
      );
      _endStream();
      if (_aborted) return;
      if (resp == null) {
        if (_turn.successfulTool) {
          _reject('turn', 'tool work ended without a spoken wrap-up');
          _say(_turn.failureLine(''));
        } else {
          _say(kWaifuToolsUnsupported);
        }
        return;
      }

      _noteReasoning(resp);
      final body = waifuVisibleText(resp.text);
      if (_turn.speechOnly && resp.calls.isNotEmpty) {
        _turn.rememberToolSpeech(body);
        if (_turn.canUseRememberedSpeech) {
          _say(_turn.rememberedSpeech);
          return;
        }
        if (_turn.canRetrySpeech) {
          _turn.requestSpeech();
          continue;
        }
        _reject('turn', 'tool work ended without an in-character spoken line');
        _say(_turn.failureLine(body));
        return;
      }

      if (resp.calls.isEmpty) {
        switch (_turn.decideFinal(body, chips: _liveAssistant().chips)) {
          case WaifuFinalAction.accept:
            _say(body);
            return;
          case WaifuFinalAction.useRememberedSpeech:
            _say(_turn.rememberedSpeech);
            return;
          case WaifuFinalAction.retryMutation:
            _turn.requestMutation();
            continue;
          case WaifuFinalAction.retrySpeech:
            _turn.requestSpeech();
            continue;
          case WaifuFinalAction.retryVerify:
            _turn.requestVerify();
            continue;
          case WaifuFinalAction.retryTodoWrite:
            _turn.requestTodoWrite();
            continue;
          case WaifuFinalAction.failMutation:
            _reject('turn', 'no file change landed for a code-change request');
            _say(_turn.failureLine(body));
            return;
          case WaifuFinalAction.failSpeech:
            _reject(
              'turn',
              'tool work ended without an in-character spoken line',
            );
            _say(_turn.failureLine(body));
            return;
          case WaifuFinalAction.failVerify:
            _reject('turn', 'no verify after a project file change');
            _say(_turn.failureLine(body));
            return;
          case WaifuFinalAction.failTodoWrite:
            _reject('turn', 'no todowrite receipt for a claimed todo update');
            _say(_turn.failureLine(body));
            return;
        }
      }

      _turn.rememberToolSpeech(body);
      if (body.isNotEmpty && !waifuLooksGenericCompletion(body)) {
        _say(body);
      }
      for (final call in resp.calls) {
        if (_aborted) return;
        await _runTool(call.name, call.arguments);
      }
    }

    if (_aborted) return;
    _reject('turn', 'runaway fuse stopped this turn');
    _say(_turn.failureLine(''));
  }

  void _settlePendingChip(String name) {
    if (!_liveAssistant().chips.any((c) => c.pending && c.name == name)) {
      return;
    }
    _pushChip(
      WaifuToolChip(
        name: name,
        detail: _aborted ? 'stopped' : 'error',
        ok: false,
      ),
    );
  }
}
