// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// All-zero needs impact is a failed read. Tools fill required ints with 0;
// retry text, then a repair pass. Individual 0s are fine; all seven are not.

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

void main() {
  group('needsImpactHasNonZeroDelta', () {
    test('false for all zeros and for no delta keys', () {
      expect(
        needsImpactHasNonZeroDelta(
          '{"hunger_delta":0,"energy_delta":0,"hygiene_delta":0,'
          '"fun_delta":0,"social_delta":0,"bladder_delta":0,'
          '"comfort_delta":0,"reason":"none"}',
        ),
        isFalse,
      );
      expect(needsImpactHasNonZeroDelta('{"reason":"none"}'), isFalse);
    });

    test('true when any need moved', () {
      expect(
        needsImpactHasNonZeroDelta(
          '{"hunger_delta":0,"bladder_delta":60,"reason":"peed"}',
        ),
        isTrue,
      );
    });
  });

  group('tools all-zero retries text', () {
    test('uses the text JSON when tools filled every delta with 0', () async {
      var textCalls = 0;
      final e = _engine(
        toolArgs: _zeroArgs,
        onText: (p) {
          textCalls++;
          return '{"hunger_delta":0,"energy_delta":-6,"hygiene_delta":-8,'
              '"fun_delta":7,"social_delta":13,"bladder_delta":60,'
              '"comfort_delta":10,"reason":"relieved herself in the scene"}';
        },
      );
      final raw = await e.evaluateNeedsImpactCall(
        'she pees on him, riding hard',
      );
      expect(textCalls, 1);
      expect(raw, contains('"bladder_delta":60'));
      expect(needsImpactHasNonZeroDelta(raw!), isTrue);
    });

    test(
      'repair pass is used when tools and text both return all zeros',
      () async {
        var textCalls = 0;
        final e = _engine(
          toolArgs: _zeroArgs,
          onText: (p) {
            textCalls++;
            if (p.prompt.contains('failed read')) {
              return '{"hunger_delta":0,"energy_delta":-5,"hygiene_delta":0,'
                  '"fun_delta":8,"social_delta":12,"bladder_delta":60,'
                  '"comfort_delta":4,"reason":"the beat moved her"}';
            }
            return '{"hunger_delta":0,"energy_delta":0,"hygiene_delta":0,'
                '"fun_delta":0,"social_delta":0,"bladder_delta":0,'
                '"comfort_delta":0,"reason":"no notable need impact"}';
          },
        );
        final raw = await e.evaluateNeedsImpactCall(
          'she pees on him, riding hard',
        );
        expect(textCalls, 2);
        expect(raw, contains('"bladder_delta":60'));
        expect(needsImpactHasNonZeroDelta(raw!), isTrue);
      },
    );

    test('does not retry when tools already reported a scene delta', () async {
      var textCalls = 0;
      final e = _engine(
        toolArgs: {..._zeroArgs, 'bladder_delta': 70, 'reason': 'bathroom'},
        onText: (p) {
          textCalls++;
          return '{"hunger_delta":99}';
        },
      );
      final raw = await e.evaluateNeedsImpactCall('she uses the bathroom');
      expect(textCalls, 0);
      expect(raw, contains('"bladder_delta":70'));
    });
  });
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
