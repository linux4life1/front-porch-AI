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
      _pruneTraces();
      _beginStream();
      final prompt = _prompt();
      final tools = _advertisedTools(speechOnly: _turn.speechOnly);
      _armBudget(tools: tools);
      final resp = await llm.generate(
        systemPrompt: system,
        prompt: prompt,
        tools: tools,
        images: step == 0 ? _turnImages : null,
        onChunk: _onChunk,
        forceTool: waifuForceFirstTool(
          step: step,
          speechOnly: _turn.speechOnly,
          mutationRequired: _turn.mutationRequired,
          mutationSucceeded: _turn.mutationSucceeded,
        ),
      );
      if (resp != null) _applyUsage(resp);
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
      final calls = waifuEffectiveToolCalls(resp);
      if (calls.isNotEmpty) {
        if (_turn.speechOnly) {
          _turn.rememberToolSpeech(body);
          if (_turn.canUseRememberedSpeech) {
            _say(_turn.rememberedSpeech);
            _turn.phase = WaifuPhase.done;
            return;
          }
          if (_turn.canRetrySpeech) {
            _turn.requestSpeech();
            continue;
          }
          _reject(
            'turn',
            'tool work ended without an in-character spoken line',
          );
          _say(_turn.failureLine(body));
          return;
        }
        _turn.rememberToolSpeech(body);
        var checkIn = false;
        for (final call in calls) {
          if (_aborted) return;
          if (waifuShouldCheckInBefore(
            rootTurn: depth == 0,
            mutationsSinceCheckIn: _turn.mutationsSinceCheckIn,
            toolName: call.name,
          )) {
            _turn.requestCheckInSpeech();
            checkIn = true;
            break;
          }
          await _runTool(call.name, call.arguments);
        }
        if (checkIn) continue;
        continue;
      }

      switch (_turn.onEmptyCalls(body)) {
        case WaifuTurnStep.accept:
          _say(_turn.pendingSpeech);
          return;
        case WaifuTurnStep.retry:
          continue;
        case WaifuTurnStep.fail:
          _reject('turn', _turn.failReason);
          _say(_turn.pendingSpeech);
          return;
      }
    }

    if (_aborted) return;
    _reject('turn', 'runaway fuse stopped this turn');
    _say(_turn.failureLine(''));
  }

  void _clearTurnReceipts() {
    session.turnWrites.clear();
    session.turnVerifyPaths.clear();
  }

  bool _refuseIfToolsUnsupported() {
    if (waifuCanUseTools(
      sessionToolsSupported: session.toolsSupported,
      llmToolsSupported: llm.toolsSupported,
    )) {
      return false;
    }
    _say(kWaifuToolsUnsupported);
    return true;
  }

  void _noteDiskWrite(WaifuWriteRecord rec) {
    session.lastWrite = rec;
    session.turnWrites.add(rec);
    undoLog.push(rec);
  }

  void _noteVerifyReceipt() {
    if (!_turn.verified || _turn.mutatedPaths.isEmpty) return;
    session.turnVerifyPaths
      ..clear()
      ..addAll(_turn.mutatedPaths);
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

  WaifuMessage _liveAssistant() {
    final live = _turn.live;
    if (live != null) {
      final i = session.transcript.indexOf(live);
      if (i >= 0 && session.transcript[i].kind == WaifuMsgKind.assistant) {
        return session.transcript[i];
      }
    }
    session.transcript.add(const WaifuMessage.assistant(''));
    _turn.live = session.transcript.last;
    return session.transcript.last;
  }

  void _writeLive(WaifuMessage msg) {
    final live = _turn.live;
    if (live != null) {
      final i = session.transcript.indexOf(live);
      if (i >= 0 && session.transcript[i].kind == WaifuMsgKind.assistant) {
        session.transcript[i] = msg;
        _turn.live = msg;
        return;
      }
    }
    session.transcript.add(msg);
    _turn.live = msg;
  }

  void _beginStream() {
    _streamBuf = '';
    _priorReasoning = '';
    _writeLive(
      waifuBeginStream(_liveAssistant(), DateTime.now().millisecondsSinceEpoch),
    );
    _emit();
  }

  void _onChunk(String chunk) {
    if (_aborted || chunk.isEmpty) return;
    _streamBuf += chunk;
    _writeLive(
      waifuApplyChunk(
        last: _liveAssistant(),
        priorReasoning: _priorReasoning,
        streamBuf: _streamBuf,
        paintBody: _turn.speechOnly,
      ),
    );
    if (!session.tokensFromApi) {
      session.tokensUsed += waifuEstimateTokens(chunk);
    }
    _emit();
  }

  void _endStream() {
    if (_aborted) return;
    _writeLive(
      waifuEndStream(_liveAssistant(), DateTime.now().millisecondsSinceEpoch),
    );
    _emit();
  }

  void _noteReasoning(LlmToolResponse resp) {
    final next = waifuMergeReasoning(_liveAssistant(), resp);
    if (next == null) return;
    _writeLive(next);
    _emit();
  }

  void _say(String text) {
    final live = _turn.live;
    if (live != null) {
      final i = session.transcript.indexOf(live);
      if (i >= 0 && session.transcript[i].kind == WaifuMsgKind.assistant) {
        _writeLive(live.copyWith(text: text));
        _emit();
        return;
      }
    }
    final msg = WaifuMessage.assistant(text);
    session.transcript.add(msg);
    _turn.live = msg;
    _emit();
  }
}
