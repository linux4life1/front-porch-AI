// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Tests for GenerationParams — the shared generation parameters sent to all LLM backends.
// Covers default values and field preservation.

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/services/llm_service.dart';

void main() {
  // ─── GenerationParams — defaults ───────────────────────────────────

  group('defaults', () {
    test('maxLength defaults to 200', () {
      final params = GenerationParams(prompt: 'test');
      expect(params.maxLength, 200);
    });

    test('minLength defaults to 0', () {
      final params = GenerationParams(prompt: 'test');
      expect(params.minLength, 0);
    });

    test('temperature defaults to 0.7', () {
      final params = GenerationParams(prompt: 'test');
      expect(params.temperature, 0.7);
    });

    test('repeatPenalty defaults to 1.1', () {
      final params = GenerationParams(prompt: 'test');
      expect(params.repeatPenalty, 1.1);
    });

    test('topP defaults to 0.9', () {
      final params = GenerationParams(prompt: 'test');
      expect(params.topP, 0.9);
    });

    test('minP defaults to 0.0', () {
      final params = GenerationParams(prompt: 'test');
      expect(params.minP, 0.0);
    });

    test('repPenTokens defaults to 64', () {
      final params = GenerationParams(prompt: 'test');
      expect(params.repPenTokens, 64);
    });

    test('xtcThreshold defaults to 0.1', () {
      final params = GenerationParams(prompt: 'test');
      expect(params.xtcThreshold, 0.1);
    });

    test('xtcProbability defaults to 0.0 (off)', () {
      // Was 0.5 back when XTC never actually reached the model; now that
      // samplers are delivered, defaulting a creativity-cutter ON would
      // change every caller's output. 0 = off is the safe neutral.
      final params = GenerationParams(prompt: 'test');
      expect(params.xtcProbability, 0.0);
    });

    test('topK and dryMultiplier default to off', () {
      final params = GenerationParams(prompt: 'test');
      expect(params.topK, 0);
      expect(params.dryMultiplier, 0.0);
    });

    test('reasoningEnabled defaults to false', () {
      final params = GenerationParams(prompt: 'test');
      expect(params.reasoningEnabled, isFalse);
    });

    test('reasoningEffort defaults to medium', () {
      final params = GenerationParams(prompt: 'test');
      expect(params.reasoningEffort, 'medium');
    });

    test('banEosToken defaults to false', () {
      final params = GenerationParams(prompt: 'test');
      expect(params.banEosToken, isFalse);
    });

    test('trimStop defaults to true', () {
      final params = GenerationParams(prompt: 'test');
      expect(params.trimStop, isTrue);
    });

    test('systemPrompt defaults to null', () {
      final params = GenerationParams(prompt: 'test');
      expect(params.systemPrompt, isNull);
    });

    test('grammar defaults to null', () {
      final params = GenerationParams(prompt: 'test');
      expect(params.grammar, isNull);
    });

    test('stopSequences defaults to null', () {
      final params = GenerationParams(prompt: 'test');
      expect(params.stopSequences, isNull);
    });

    test('bannedPhrases defaults to null', () {
      final params = GenerationParams(prompt: 'test');
      expect(params.bannedPhrases, isNull);
    });

    test('dynatempRange defaults to null', () {
      final params = GenerationParams(prompt: 'test');
      expect(params.dynatempRange, isNull);
    });

    test('images defaults to null (text-only user content)', () {
      final params = GenerationParams(prompt: 'test');
      expect(params.images, isNull);
      expect(params.openAiUserContent, 'test');
    });
  });

  // ─── GenerationParams — custom values ──────────────────────────────

  group('custom values', () {
    test('accepts custom maxLength', () {
      final params = GenerationParams(prompt: 'test', maxLength: 500);
      expect(params.maxLength, 500);
    });

    test('accepts custom temperature', () {
      final params = GenerationParams(prompt: 'test', temperature: 1.2);
      expect(params.temperature, 1.2);
    });

    test('accepts custom repeatPenalty', () {
      final params = GenerationParams(prompt: 'test', repeatPenalty: 1.5);
      expect(params.repeatPenalty, 1.5);
    });

    test('accepts custom stopSequences', () {
      final params = GenerationParams(
        prompt: 'test',
        stopSequences: ['\n\n', 'User:'],
      );
      expect(params.stopSequences, ['\n\n', 'User:']);
    });

    test('accepts custom bannedPhrases', () {
      final params = GenerationParams(
        prompt: 'test',
        bannedPhrases: ['bad word'],
      );
      expect(params.bannedPhrases, ['bad word']);
    });

    test('accepts custom systemPrompt', () {
      final params = GenerationParams(
        prompt: 'test',
        systemPrompt: 'You are a helpful assistant.',
      );
      expect(params.systemPrompt, 'You are a helpful assistant.');
    });

    test('accepts custom grammar', () {
      final params = GenerationParams(
        prompt: 'test',
        grammar: 'root ::= "hello"',
      );
      expect(params.grammar, 'root ::= "hello"');
    });

    test('accepts custom reasoning settings', () {
      final params = GenerationParams(
        prompt: 'test',
        reasoningEnabled: true,
        reasoningEffort: 'high',
      );
      expect(params.reasoningEnabled, isTrue);
      expect(params.reasoningEffort, 'high');
    });

    test('accepts custom banEosToken', () {
      final params = GenerationParams(prompt: 'test', banEosToken: true);
      expect(params.banEosToken, isTrue);
    });

    test('accepts custom trimStop', () {
      final params = GenerationParams(prompt: 'test', trimStop: false);
      expect(params.trimStop, isFalse);
    });

    test('accepts custom dynatempRange', () {
      final params = GenerationParams(prompt: 'test', dynatempRange: 0.5);
      expect(params.dynatempRange, 0.5);
    });

    test('accepts custom images', () {
      final params = GenerationParams(prompt: 'test', images: ['QUFB']);
      expect(params.images, ['QUFB']);
    });

    test('accepts all fields at once', () {
      final params = GenerationParams(
        prompt: 'test prompt',
        maxLength: 512,
        minLength: 50,
        temperature: 0.8,
        repeatPenalty: 1.2,
        topP: 0.95,
        minP: 0.05,
        repPenTokens: 128,
        dynatempRange: 0.3,
        xtcThreshold: 0.5,
        xtcProbability: 0.3,
        stopSequences: ['\n\n', 'User:'],
        reasoningEnabled: true,
        reasoningEffort: 'low',
        bannedPhrases: ['cliché'],
        systemPrompt: 'System prompt',
        grammar: 'root ::= "test"',
        banEosToken: true,
        trimStop: false,
      );

      expect(params.prompt, 'test prompt');
      expect(params.maxLength, 512);
      expect(params.minLength, 50);
      expect(params.temperature, 0.8);
      expect(params.repeatPenalty, 1.2);
      expect(params.topP, 0.95);
      expect(params.minP, 0.05);
      expect(params.repPenTokens, 128);
      expect(params.dynatempRange, 0.3);
      expect(params.xtcThreshold, 0.5);
      expect(params.xtcProbability, 0.3);
      expect(params.stopSequences, ['\n\n', 'User:']);
      expect(params.reasoningEnabled, isTrue);
      expect(params.reasoningEffort, 'low');
      expect(params.bannedPhrases, ['cliché']);
      expect(params.systemPrompt, 'System prompt');
      expect(params.grammar, 'root ::= "test"');
      expect(params.banEosToken, isTrue);
      expect(params.trimStop, isFalse);
    });
  });

  // ─── GenerationParams — prompt preservation ────────────────────────

  group('prompt preservation', () {
    test('empty prompt is accepted', () {
      final params = GenerationParams(prompt: '');
      expect(params.prompt, '');
    });

    test('null prompt is not accepted (required field)', () {
      // This test documents that prompt is a required positional parameter.
      // The following would not compile:
      // GenerationParams(prompt: null);
      // GenerationParams();
    });

    test('long prompt is preserved', () {
      final longPrompt = 'a' * 10000;
      final params = GenerationParams(prompt: longPrompt);
      expect(params.prompt.length, 10000);
    });

    test('prompt with special characters is preserved', () {
      final prompt = 'Hello\n\nWorld!\t"quoted"\n*asterisks*';
      final params = GenerationParams(prompt: prompt);
      expect(params.prompt, prompt);
    });
  });
}
