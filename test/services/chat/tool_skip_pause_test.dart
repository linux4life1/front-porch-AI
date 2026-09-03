// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Two-gate no-double-gen: skip the rest of THIS send after an inconclusive
// tools miss; pause after two consecutive skipped sends. Regen of a finished
// turn retries tools (endUserSend cleared skip; skip is only honored while
// a send is open). Honest-empty Journal/Growth calls are not skip.

import 'package:flutter_test/flutter_test.dart';

import 'package:front_porch_ai/services/chat/pass_support.dart';
import 'package:front_porch_ai/services/chat/tool_eval_spec.dart';
import 'package:front_porch_ai/services/llm_service.dart';

void main() {
  const id = 'Kobold|m';

  Future<int> fire({
    required ToolTransportProbe probe,
    required int Function() onTool,
    LlmToolResponse? resp,
  }) async {
    await fireStructuredEval(
      probe: probe,
      backendIdentity: id,
      debugLabel: 'report_relationship',
      tools: const [
        {
          'type': 'function',
          'function': {'name': 'report_relationship'},
        },
      ],
      toolChoice: 'report_relationship',
      buildPrompt: ({required bool toolsMode}) => 'P',
      callToText: (r) => r.calls.isEmpty ? null : 'OK',
      fireToolEval: (ToolEvalSpec spec) async {
        onTool();
        return resp;
      },
      fireTextEval: (p, {onChunk}) async => 'TEXT',
    );
    return 0;
  }

  test('inside a send, an empty miss skips tools for later evals', () async {
    final p = ToolTransportProbe();
    var tools = 0;
    p.beginUserSend();
    await fire(probe: p, onTool: () => tools++, resp: null);
    await fire(probe: p, onTool: () => tools++, resp: null);
    await fire(probe: p, onTool: () => tools++, resp: null);
    expect(
      tools,
      1,
      reason: 'three empty judges in one send: one tools attempt',
    );
    expect(p.isPausedUntilPing(id), isFalse);
    p.endUserSend(id);
    expect(
      p.isPausedUntilPing(id),
      isFalse,
      reason: 'one skipped send is not 2',
    );
  });

  test('after endUserSend, regen retries tools (skip cleared)', () async {
    final p = ToolTransportProbe();
    var tools = 0;
    p.beginUserSend();
    await fire(probe: p, onTool: () => tools++, resp: null);
    expect(tools, 1);
    p.endUserSend(id);
    // Regen is not a new send — no beginUserSend. Skip must not apply.
    await fire(probe: p, onTool: () => tools++, resp: null);
    expect(tools, 2);
  });

  test(
    'two consecutive skipped sends pause; reset unpauses and untests',
    () async {
      final p = ToolTransportProbe()..markSupported(id);
      p.beginUserSend();
      p.noteInconclusive(id);
      p.endUserSend(id);
      p.beginUserSend();
      p.noteInconclusive(id);
      p.endUserSend(id);
      expect(p.isPausedUntilPing(id), isTrue);
      expect(p.shouldPostAfterIdle(id), isFalse);
      p.reset(id);
      expect(p.isPausedUntilPing(id), isFalse);
      expect(p.supportFor(id), ToolCallSupport.untested);
      expect(p.shouldPostAfterIdle(id), isTrue);
    },
  );

  test('shouldPostAfterIdle never reads preferText (ping door)', () {
    final p = ToolTransportProbe()..markSupported(id);
    expect(p.shouldFireTools(id, preferTextEvals: true), isFalse);
    expect(
      p.shouldPostAfterIdle(id),
      isTrue,
      reason:
          'ping shares _fireToolEval; live prefer-text here would starve it',
    );
  });

  test('honest empty (calls but no usable ops) is not skip', () {
    final p = ToolTransportProbe();
    p.beginUserSend();
    p.markSupported(id);
    // Journal/Growth return [] here and must NOT noteInconclusive.
    expect(p.isSkippedThisSend(id), isFalse);
    expect(p.shouldPostAfterIdle(id), isTrue);
    p.endUserSend(id);
    expect(p.isPausedUntilPing(id), isFalse);
  });

  test('supported → inconclusive → markSupported clears consecutive', () {
    final p = ToolTransportProbe()..markSupported(id);
    p.beginUserSend();
    p.noteInconclusive(id);
    p.endUserSend(id);
    p.beginUserSend();
    p.markSupported(id);
    p.endUserSend(id);
    p.beginUserSend();
    p.noteInconclusive(id);
    p.endUserSend(id);
    expect(p.isPausedUntilPing(id), isFalse);
  });
}
