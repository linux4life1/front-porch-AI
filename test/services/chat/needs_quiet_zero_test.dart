// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// A quiet beat that scores all zeros is a valid read. Tools models fill the
// seven required ints with 0, so a text retry is allowed; inventing a swing
// from the character's own prose is the 2026-08 crater.

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:front_porch_ai/models/character_card.dart';
import 'package:front_porch_ai/services/chat/llm_eval_engine.dart';
import 'package:front_porch_ai/services/chat/needs_impact_zero.dart';
import 'package:front_porch_ai/services/chat/pass_support.dart';
import 'package:front_porch_ai/services/chat/realism_tools.dart';
import 'package:front_porch_ai/services/llm_service.dart';

import 'llm_eval_engine_test.dart' show createTestLlmEvalEngine;

const _zeroArgs = {
  'hunger_delta': 0,
  'energy_delta': 0,
  'hygiene_delta': 0,
  'fun_delta': 0,
  'social_delta': 0,
  'bladder_delta': 0,
  'comfort_delta': 0,
  'reason': 'none',
};

const _zeroJson =
    '{"hunger_delta":0,"energy_delta":0,"hygiene_delta":0,'
    '"fun_delta":0,"social_delta":0,"bladder_delta":0,'
    '"comfort_delta":0,"reason":"a quiet beat"}';

void main() {
  test(
    'tools+text all-zero stays zeros — repair must not invent a swing',
    () async {
      var textCalls = 0;
      var sawRepair = false;
      final e = _engine(
        toolArgs: _zeroArgs,
        onText: (p) {
          textCalls++;
          if (p.prompt.contains('failed read') ||
              p.prompt.contains('always moves at least one need')) {
            sawRepair = true;
            return '{"hunger_delta":0,"energy_delta":-5,"hygiene_delta":0,'
                '"fun_delta":8,"social_delta":12,"bladder_delta":60,'
                '"comfort_delta":4,"reason":"invented"}';
          }
          return _zeroJson;
        },
      );
      final raw = await e.evaluateNeedsImpactCall('they sit together a while');
      expect(sawRepair, isFalse, reason: 'quiet zeros are not a failed read');
      expect(textCalls, 1, reason: 'tools zeros may retry text once');
      expect(needsImpactHasNonZeroDelta(raw!), isFalse);
    },
  );
}

LlmEvalEngine _engine({
  required Map<String, dynamic> toolArgs,
  required String Function(GenerationParams) onText,
}) {
  final base = createTestLlmEvalEngine(
    activeChar: CharacterCard(name: 'Jennifer'),
  );
  return LlmEvalEngine(
    getActiveCharacter: () => CharacterCard(name: 'Jennifer'),
    getActiveGroup: () => null,
    getIsObserverMode: () => false,
    getUserName: () => 'User',
    getRealismEnabled: () => true,
    getMessages: () => const [],
    fireToolEval: (spec) async => LlmToolResponse(
      calls: [LlmToolCall(name: kNeedsImpactTool, arguments: toolArgs)],
      text: '',
    ),
    probe: ToolTransportProbe(),
    getBackendIdentity: () => 'test',
    getLlmService: () => _TextLlm(onText),
    getIsLocal: () => false,
    getKoboldService: () => null,
    reconnectIfAlive: () async {},
    ensureServerIdle: () async {},
    getIsCancellingRealismEval: () => false,
    getRealismEvalCancelled: () => false,
    getPendingRealismMetadata: () => null,
    setPendingRealismMetadata: (_) {},
    captureRealismState: ({preTurn}) => {},
    getCharacterEmotion: () => '',
    setCharacterEmotion: (_) {},
    getEmotionIntensity: () => '',
    setEmotionIntensity: (_) {},
    relationshipService: base.relationshipService,
  );
}

class _TextLlm extends LLMService {
  _TextLlm(this._onText);
  final String Function(GenerationParams) _onText;

  @override
  bool get isReady => true;

  @override
  String get backendName => 'fake';

  @override
  Stream<String> generateStream(GenerationParams params) =>
      Stream.value(_onText(params));

  @override
  void addListener(VoidCallback listener) {}

  @override
  void removeListener(VoidCallback listener) {}

  @override
  bool get hasListeners => false;

  @override
  void notifyListeners() {}
}
