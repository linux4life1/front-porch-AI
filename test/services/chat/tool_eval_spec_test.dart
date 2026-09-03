// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Named toolChoice through fireStructuredEval, dual-accept (p, t) closures,
// overlay start chunk, and eval-sized defaults.

import 'package:flutter_test/flutter_test.dart';

import 'package:front_porch_ai/services/chat/pass_support.dart';
import 'package:front_porch_ai/services/chat/tool_eval_spec.dart';
import 'package:front_porch_ai/services/llm_service.dart';
import 'package:front_porch_ai/services/storage/settings/realism_settings.dart';

void main() {
  group('fireStructuredEval ToolEvalSpec', () {
    test('passes toolChoice on the spec, not inferred from tools', () async {
      String? seenChoice;
      List<Map<String, dynamic>>? seenTools;
      int? seenMax;
      final chunks = <String>[];
      final probe = ToolTransportProbe();
      final result = await fireStructuredEval(
        probe: probe,
        backendIdentity: 'id',
        debugLabel: 'report_emotional_state',
        tools: const [
          {
            'type': 'function',
            'function': {'name': 'report_relationship'},
          },
          {
            'type': 'function',
            'function': {'name': 'report_emotional_state'},
          },
        ],
        toolChoice: 'report_emotional_state',
        buildPrompt: ({required bool toolsMode}) => 'P',
        callToText: (resp) => resp.calls.isEmpty ? null : 'OK',
        fireToolEval: (ToolEvalSpec spec) async {
          seenChoice = spec.toolChoice;
          seenTools = spec.tools;
          seenMax = spec.maxLength;
          return const LlmToolResponse(
            calls: [LlmToolCall(name: 'report_emotional_state', arguments: {})],
            text: '',
          );
        },
        fireTextEval: (p, {onChunk}) async => 'TEXT',
        onChunk: chunks.add,
      );
      expect(result, 'OK');
      expect(seenChoice, 'report_emotional_state');
      expect(seenMax, kScalarToolMaxTokens);
      expect(seenTools, hasLength(2));
      expect(chunks.first, contains('⏳ report_emotional_state'));
    });

    test('legacy (prompt, tools) closures still run', () async {
      var called = false;
      final result = await fireStructuredEval(
        probe: ToolTransportProbe(),
        backendIdentity: 'id',
        debugLabel: 'test',
        tools: const [
          {
            'type': 'function',
            'function': {'name': 'report'},
          },
        ],
        buildPrompt: ({required bool toolsMode}) => 'P',
        callToText: (resp) => 'OK',
        fireToolEval: (String p, List<Map<String, dynamic>> t) async {
          called = true;
          return const LlmToolResponse(
            calls: [LlmToolCall(name: 'report', arguments: {})],
            text: '',
          );
        },
        fireTextEval: (p, {onChunk}) async => 'TEXT',
      );
      expect(called, isTrue);
      expect(result, 'OK');
    });

    test('preferTextEvals skips the tools attempt', () async {
      var toolFires = 0;
      final probe = ToolTransportProbe()..markSupported('id');
      final result = await fireStructuredEval(
        probe: probe,
        backendIdentity: 'id',
        debugLabel: 'report_relationship',
        tools: const [],
        toolChoice: 'report_relationship',
        getPreferTextEvals: () => true,
        buildPrompt: ({required bool toolsMode}) => toolsMode ? 'T' : 'X',
        callToText: (_) => 'NO',
        fireToolEval: (ToolEvalSpec spec) async {
          toolFires++;
          return null;
        },
        fireTextEval: (p, {onChunk}) async => 'TEXT',
      );
      expect(toolFires, 0);
      expect(result, 'TEXT');
      expect(probe.supportFor('id'), ToolCallSupport.supported);
    });
  });

  group('resolveOneShotMode preferTextEvals', () {
    test('Auto + remote + supported + preferText is not fused', () {
      expect(
        resolveOneShotMode(
          mode: OneShotMode.auto,
          isLocal: false,
          toolSupport: ToolCallSupport.supported,
          preferTextEvals: true,
        ),
        isFalse,
      );
    });

    test('Auto + remote + supported without preferText still fuses', () {
      expect(
        resolveOneShotMode(
          mode: OneShotMode.auto,
          isLocal: false,
          toolSupport: ToolCallSupport.supported,
        ),
        isTrue,
      );
    });
  });

  group('ToolTransportProbe skip/pause', () {
    test('three empty notes in one send do not pause', () {
      final p = ToolTransportProbe();
      p.beginUserSend();
      p.noteInconclusive('id');
      p.noteInconclusive('id');
      p.noteInconclusive('id');
      p.endUserSend('id');
      expect(p.isPausedUntilPing('id'), isFalse);
    });

    test('two skipped sends pause; reset drops pause', () {
      final p = ToolTransportProbe();
      p.markSupported('id');
      p.beginUserSend();
      p.noteInconclusive('id');
      p.endUserSend('id');
      expect(p.isPausedUntilPing('id'), isFalse);
      p.beginUserSend();
      p.noteInconclusive('id');
      p.endUserSend('id');
      expect(p.isPausedUntilPing('id'), isTrue);
      p.reset('id');
      expect(p.isPausedUntilPing('id'), isFalse);
      expect(p.supportFor('id'), ToolCallSupport.untested);
    });

    test('markSupported early-return still clears consecutive', () {
      final p = ToolTransportProbe();
      p.markSupported('id');
      p.beginUserSend();
      p.noteInconclusive('id');
      p.endUserSend('id');
      p.beginUserSend();
      p.markSupported('id');
      p.endUserSend('id');
      p.beginUserSend();
      p.noteInconclusive('id');
      p.endUserSend('id');
      expect(
        p.isPausedUntilPing('id'),
        isFalse,
        reason: 'recovered send reset consecutive; one later skip is not 2',
      );
    });
  });
}
