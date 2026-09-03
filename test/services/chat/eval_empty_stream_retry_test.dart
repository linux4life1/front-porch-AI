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

// EMPTY EVAL STREAMS MUST FAIL FAST ON NON-LOCAL BACKENDS.
//
// fireLLMEval retries a completed-but-empty stream once after a settle, for
// local thinking models that return nothing during <think> prefill. That
// retry used to run for EVERY backend — including ScriptedLlm fakes and
// remote APIs — and the `continue` then paid the connection-drop 3s delay
// on top of the 2s settle. Each unmatched eval (With-you after it landed,
// posture on a fake that does not answer it, …) stalled the turn 5 seconds.
// ScriptedLlm chat tests hit the 2-minute timeout or asserted against a
// seed prompt because post-gen had not finished.
//
// Proven red before the product fix: this file's first test saw calls == 2
// and elapsed ≈ 5s against HEAD. After: calls == 1, elapsed well under 1s.

import 'package:flutter_test/flutter_test.dart';

import 'package:front_porch_ai/services/chat/chat.dart';
import 'package:front_porch_ai/services/services.dart';

import 'llm_eval_engine_test.dart' show createTestLlmEvalEngine;

void main() {
  test(
    'a completed-empty stream on a non-local backend does not retry',
    () async {
      var calls = 0;
      final e = createTestLlmEvalEngine(
        streamFactory: (_) {
          calls++;
          return Stream<String>.value('');
        },
      );
      final sw = Stopwatch()..start();
      final res = await e.fireLLMEval('p').timeout(const Duration(seconds: 15));
      sw.stop();

      expect(res, isNull);
      expect(
        calls,
        1,
        reason:
            'THE BUG. Empty retry is for local thinking prefill. A remote '
            'API or ScriptedLlm yielding "" is a real empty — a second call '
            'plus 5s of settle/drop delay is how With-you stalled every '
            'scripted chat test',
      );
      expect(
        sw.elapsed,
        lessThan(const Duration(milliseconds: 800)),
        reason: 'fail-fast: no 2s settle and no 3s connection-drop pause',
      );
    },
  );

  test('a local empty stream still retries once after settle', () async {
    var calls = 0;
    final e = _localEngine(
      streamFactory: (_) {
        calls++;
        return Stream<String>.value('');
      },
      emptyStreamSettle: const Duration(milliseconds: 15),
      connectionDropSettle: const Duration(seconds: 3),
    );
    final sw = Stopwatch()..start();
    final res = await e.fireLLMEval('p').timeout(const Duration(seconds: 5));
    sw.stop();

    expect(res, isNull);
    expect(calls, 2, reason: 'local thinking prefill still gets one retry');
    expect(
      sw.elapsed,
      lessThan(const Duration(milliseconds: 800)),
      reason:
          'empty retry must NOT also pay the 3s connection-drop delay — '
          'that pause is for thrown stream errors only',
    );
  });

  test('a thrown stream error still retries after the drop pause', () async {
    var calls = 0;
    final e = _localEngine(
      streamFactory: (_) {
        calls++;
        if (calls == 1) {
          return Stream<String>.error(StateError('drop'));
        }
        return Stream<String>.value('{"ok":true}');
      },
      emptyStreamSettle: Duration.zero,
      connectionDropSettle: const Duration(milliseconds: 15),
    );
    final res = await e.fireLLMEval('p').timeout(const Duration(seconds: 5));
    expect(res, contains('"ok":true'));
    expect(calls, 2);
  });
}

LlmEvalEngine _localEngine({
  required Stream<String> Function(GenerationParams) streamFactory,
  required Duration emptyStreamSettle,
  required Duration connectionDropSettle,
}) {
  final base = createTestLlmEvalEngine(streamFactory: streamFactory);
  return LlmEvalEngine(
    getActiveCharacter: base.getActiveCharacter,
    getActiveGroup: base.getActiveGroup,
    getIsObserverMode: base.getIsObserverMode,
    getUserName: base.getUserName,
    getRealismEnabled: base.getRealismEnabled,
    getMessages: base.getMessages,
    getLlmService: base.getLlmService,
    getIsLocal: () => true,
    getKoboldService: base.getKoboldService,
    reconnectIfAlive: base.reconnectIfAlive,
    ensureServerIdle: base.ensureServerIdle,
    getIsCancellingRealismEval: base.getIsCancellingRealismEval,
    getRealismEvalCancelled: base.getRealismEvalCancelled,
    getPendingRealismMetadata: base.getPendingRealismMetadata,
    setPendingRealismMetadata: base.setPendingRealismMetadata,
    captureRealismState: base.captureRealismState,
    getCharacterEmotion: base.getCharacterEmotion,
    setCharacterEmotion: base.setCharacterEmotion,
    getEmotionIntensity: base.getEmotionIntensity,
    setEmotionIntensity: base.setEmotionIntensity,
    relationshipService: base.relationshipService,
    emptyStreamSettle: emptyStreamSettle,
    connectionDropSettle: connectionDropSettle,
  );
}
