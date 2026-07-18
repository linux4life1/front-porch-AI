// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Tests for ChatGenerationSettings — per-session generation parameter overrides.
// Covers JSON serialization, resolution with defaults, and deep copy.

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/models/chat_generation_settings.dart';

void main() {
  // ─── ChatGenerationSettings — defaults ─────────────────────────────

  group('defaults', () {
    test('all fields are null by default', () {
      final settings = ChatGenerationSettings();

      expect(settings.temperature, isNull);
      expect(settings.minP, isNull);
      expect(settings.repeatPenalty, isNull);
      expect(settings.repeatPenaltyTokens, isNull);
      expect(settings.xtcThreshold, isNull);
      expect(settings.xtcProbability, isNull);
      expect(settings.dynamicTempEnabled, isNull);
      expect(settings.dynamicTempRange, isNull);
      expect(settings.maxLength, isNull);
      expect(settings.minLength, isNull);
      expect(settings.contextSize, isNull);
      expect(settings.stopSequences, isNull);
      expect(settings.bannedPhrases, isNull);
      expect(settings.reasoningEnabled, isNull);
      expect(settings.reasoningEffort, isNull);
    });

    test('hasOverrides is false when all fields are null', () {
      final settings = ChatGenerationSettings();
      expect(settings.hasOverrides, isFalse);
    });

    test('hasOverrides is true when any field is set', () {
      final settings = ChatGenerationSettings(temperature: 0.8);
      expect(settings.hasOverrides, isTrue);
    });

    test('top-p / top-k / DRY overrides survive a JSON round trip', () {
      final settings = ChatGenerationSettings(
        topP: 0.92,
        topK: 60,
        dryMultiplier: 0.8,
      );
      expect(settings.hasOverrides, isTrue);
      final back = ChatGenerationSettings.fromJsonString(
        settings.toJsonString(),
      );
      expect(back.topP, 0.92);
      expect(back.topK, 60);
      expect(back.dryMultiplier, 0.8);
      // Unset fields stay null (inherit global).
      expect(back.temperature, isNull);
    });
  });

  // ─── ChatGenerationSettings — JSON serialization ───────────────────

  group('toJson', () {
    test('only includes non-null fields', () {
      final settings = ChatGenerationSettings(temperature: 0.8, maxLength: 500);

      final json = settings.toJson();

      expect(json['temperature'], 0.8);
      expect(json['max_length'], 500);
      expect(json.containsKey('min_p'), isFalse);
      expect(json.containsKey('repeat_penalty'), isFalse);
      expect(json.length, 2);
    });

    test('toJson includes boolean field', () {
      final settings = ChatGenerationSettings(reasoningEnabled: true);

      final json = settings.toJson();
      expect(json['reasoning_enabled'], isTrue);
    });

    test('toJson includes list fields', () {
      final settings = ChatGenerationSettings(
        stopSequences: ['\n\n', 'User:'],
        bannedPhrases: ['bad word'],
      );

      final json = settings.toJson();
      expect(json['stop_sequences'], ['\n\n', 'User:']);
      expect(json['banned_phrases'], ['bad word']);
    });

    test('toJson includes all non-null fields when all are set', () {
      final settings = ChatGenerationSettings(
        temperature: 0.9,
        minP: 0.1,
        repeatPenalty: 1.2,
        repeatPenaltyTokens: 128,
        xtcThreshold: 0.5,
        xtcProbability: 0.3,
        dynamicTempEnabled: true,
        dynamicTempRange: 0.5,
        maxLength: 1024,
        minLength: 50,
        contextSize: 2048,
        stopSequences: ['\n'],
        bannedPhrases: ['test'],
        reasoningEnabled: true,
        reasoningEffort: 'high',
      );

      final json = settings.toJson();
      // All 15 nullable fields are set, so all should be in the map
      expect(json['temperature'], 0.9);
      expect(json['min_p'], 0.1);
      expect(json['repeat_penalty'], 1.2);
      expect(json['rep_pen_tokens'], 128);
      expect(json['xtc_threshold'], 0.5);
      expect(json['xtc_probability'], 0.3);
      expect(json['dynatemp_enabled'], isTrue);
      expect(json['dynatemp_range'], 0.5);
      expect(json['max_length'], 1024);
      expect(json['min_length'], 50);
      expect(json['context_size'], 2048);
      expect(json['stop_sequences'], ['\n']);
      expect(json['banned_phrases'], ['test']);
      expect(json['reasoning_enabled'], isTrue);
      expect(json['reasoning_effort'], 'high');
    });

    test('toJson with empty lists includes them', () {
      final settings = ChatGenerationSettings(
        stopSequences: [],
        bannedPhrases: [],
      );

      final json = settings.toJson();
      expect(json['stop_sequences'], []);
      expect(json['banned_phrases'], []);
    });
  });

  group('toJsonString', () {
    test('returns null when no overrides', () {
      final settings = ChatGenerationSettings();
      expect(settings.toJsonString(), isNull);
    });

    test('returns JSON string when overrides exist', () {
      final settings = ChatGenerationSettings(temperature: 0.8);
      final jsonStr = settings.toJsonString();

      expect(jsonStr, isNotNull);
      expect(jsonStr, contains('temperature'));
    });
  });

  // ─── ChatGenerationSettings — JSON parsing ─────────────────────────

  group('fromJson', () {
    test('parses all fields from JSON map', () {
      final json = {
        'temperature': 0.85,
        'min_p': 0.05,
        'repeat_penalty': 1.15,
        'rep_pen_tokens': 64,
        'xtc_threshold': 0.5,
        'xtc_probability': 0.3,
        'dynatemp_enabled': true,
        'dynatemp_range': 0.4,
        'max_length': 512,
        'min_length': 30,
        'context_size': 4096,
        'stop_sequences': ['\n\n', 'User:'],
        'banned_phrases': ['cliché'],
        'reasoning_enabled': true,
        'reasoning_effort': 'low',
      };

      final settings = ChatGenerationSettings.fromJson(json);

      expect(settings.temperature, 0.85);
      expect(settings.minP, 0.05);
      expect(settings.repeatPenalty, 1.15);
      expect(settings.repeatPenaltyTokens, 64);
      expect(settings.xtcThreshold, 0.5);
      expect(settings.xtcProbability, 0.3);
      expect(settings.dynamicTempEnabled, isTrue);
      expect(settings.dynamicTempRange, 0.4);
      expect(settings.maxLength, 512);
      expect(settings.minLength, 30);
      expect(settings.contextSize, 4096);
      expect(settings.stopSequences, ['\n\n', 'User:']);
      expect(settings.bannedPhrases, ['cliché']);
      expect(settings.reasoningEnabled, isTrue);
      expect(settings.reasoningEffort, 'low');
    });

    test('fromJson ignores missing keys (leaves them null)', () {
      final json = {'temperature': 0.7};
      final settings = ChatGenerationSettings.fromJson(json);

      expect(settings.temperature, 0.7);
      expect(settings.maxLength, isNull);
      expect(settings.reasoningEnabled, isNull);
    });

    test('fromJson handles numeric values as int', () {
      final json = {
        'max_length': 200,
        'rep_pen_tokens': 64,
        'min_length': 10,
        'context_size': 1024,
      };

      final settings = ChatGenerationSettings.fromJson(json);

      expect(settings.maxLength, 200);
      expect(settings.repeatPenaltyTokens, 64);
      expect(settings.minLength, 10);
      expect(settings.contextSize, 1024);
    });

    test('fromJson handles numeric values as double', () {
      final json = {
        'temperature': 0.7,
        'min_p': 0.0,
        'repeat_penalty': 1.0,
        'xtc_threshold': 0.1,
        'xtc_probability': 0.5,
        'dynatemp_range': 0.0,
      };

      final settings = ChatGenerationSettings.fromJson(json);

      expect(settings.temperature, 0.7);
      expect(settings.minP, 0.0);
      expect(settings.repeatPenalty, 1.0);
      expect(settings.xtcThreshold, 0.1);
      expect(settings.xtcProbability, 0.5);
      expect(settings.dynamicTempRange, 0.0);
    });

    test('fromJson handles null values gracefully', () {
      final json = {'temperature': null, 'maxLength': null};

      final settings = ChatGenerationSettings.fromJson(json);

      expect(settings.temperature, isNull);
      expect(settings.maxLength, isNull);
    });

    test('fromJson handles empty map', () {
      final settings = ChatGenerationSettings.fromJson({});

      expect(settings.temperature, isNull);
      expect(settings.hasOverrides, isFalse);
    });
  });

  group('fromJsonString', () {
    test('returns empty settings for null input', () {
      final settings = ChatGenerationSettings.fromJsonString(null);
      expect(settings.hasOverrides, isFalse);
    });

    test('returns empty settings for empty string', () {
      final settings = ChatGenerationSettings.fromJsonString('');
      expect(settings.hasOverrides, isFalse);
    });

    test('parses valid JSON string', () {
      final jsonStr = '{"temperature": 0.8, "max_length": 500}';
      final settings = ChatGenerationSettings.fromJsonString(jsonStr);

      expect(settings.temperature, 0.8);
      expect(settings.maxLength, 500);
    });

    test('returns empty settings for invalid JSON string', () {
      final settings = ChatGenerationSettings.fromJsonString('not json');
      expect(settings.hasOverrides, isFalse);
    });

    test('returns empty settings for malformed JSON', () {
      final settings = ChatGenerationSettings.fromJsonString('{broken');
      expect(settings.hasOverrides, isFalse);
    });
  });

  // ─── ChatGenerationSettings — copy ─────────────────────────────────

  group('copy', () {
    test('creates independent deep copy', () {
      final original = ChatGenerationSettings(
        temperature: 0.8,
        maxLength: 500,
        stopSequences: ['\n\n', 'User:'],
      );

      final copy = original.copy();

      expect(copy.temperature, 0.8);
      expect(copy.maxLength, 500);
      expect(copy.stopSequences, ['\n\n', 'User:']);
    });

    test('copy is independent — modifying copy does not affect original', () {
      final original = ChatGenerationSettings(
        temperature: 0.8,
        stopSequences: ['\n\n'],
      );

      final copy = original.copy();
      copy.temperature = 0.9;
      // stopSequences list is replaced, not mutated
      copy.stopSequences = ['new'];

      expect(original.temperature, 0.8);
      expect(original.stopSequences, ['\n\n']);
    });

    test('copy of empty settings is empty', () {
      final original = ChatGenerationSettings();
      final copy = original.copy();

      expect(copy.hasOverrides, isFalse);
    });

    test('copy preserves all fields', () {
      final original = ChatGenerationSettings(
        temperature: 0.9,
        minP: 0.1,
        repeatPenalty: 1.2,
        repeatPenaltyTokens: 128,
        xtcThreshold: 0.5,
        xtcProbability: 0.3,
        dynamicTempEnabled: true,
        dynamicTempRange: 0.5,
        maxLength: 1024,
        minLength: 50,
        contextSize: 2048,
        stopSequences: ['\n'],
        bannedPhrases: ['test'],
        reasoningEnabled: true,
        reasoningEffort: 'high',
      );

      final copy = original.copy();

      expect(copy.temperature, original.temperature);
      expect(copy.minP, original.minP);
      expect(copy.repeatPenalty, original.repeatPenalty);
      expect(copy.repeatPenaltyTokens, original.repeatPenaltyTokens);
      expect(copy.xtcThreshold, original.xtcThreshold);
      expect(copy.xtcProbability, original.xtcProbability);
      expect(copy.dynamicTempEnabled, original.dynamicTempEnabled);
      expect(copy.dynamicTempRange, original.dynamicTempRange);
      expect(copy.maxLength, original.maxLength);
      expect(copy.minLength, original.minLength);
      expect(copy.contextSize, original.contextSize);
      expect(copy.stopSequences, original.stopSequences);
      expect(copy.bannedPhrases, original.bannedPhrases);
      expect(copy.reasoningEnabled, original.reasoningEnabled);
      expect(copy.reasoningEffort, original.reasoningEffort);
    });
  });

  // ─── ChatGenerationSettings — JSON round-trip ──────────────────────

  group('JSON round-trip', () {
    test('round-trip preserves all values', () {
      final original = ChatGenerationSettings(
        temperature: 0.85,
        minP: 0.05,
        repeatPenalty: 1.1,
        repeatPenaltyTokens: 64,
        xtcThreshold: 0.5,
        xtcProbability: 0.3,
        dynamicTempEnabled: true,
        dynamicTempRange: 0.4,
        maxLength: 512,
        minLength: 30,
        contextSize: 2048,
        stopSequences: ['\n\n', 'User:'],
        bannedPhrases: ['bad word'],
        reasoningEnabled: true,
        reasoningEffort: 'medium',
      );

      final jsonStr = original.toJsonString();
      final restored = ChatGenerationSettings.fromJsonString(jsonStr!);

      expect(restored.temperature, original.temperature);
      expect(restored.minP, original.minP);
      expect(restored.repeatPenalty, original.repeatPenalty);
      expect(restored.repeatPenaltyTokens, original.repeatPenaltyTokens);
      expect(restored.xtcThreshold, original.xtcThreshold);
      expect(restored.xtcProbability, original.xtcProbability);
      expect(restored.dynamicTempEnabled, original.dynamicTempEnabled);
      expect(restored.dynamicTempRange, original.dynamicTempRange);
      expect(restored.maxLength, original.maxLength);
      expect(restored.minLength, original.minLength);
      expect(restored.contextSize, original.contextSize);
      expect(restored.stopSequences, original.stopSequences);
      expect(restored.bannedPhrases, original.bannedPhrases);
      expect(restored.reasoningEnabled, original.reasoningEnabled);
      expect(restored.reasoningEffort, original.reasoningEffort);
    });

    test('round-trip with partial settings', () {
      final original = ChatGenerationSettings(temperature: 0.7);

      final jsonStr = original.toJsonString();
      final restored = ChatGenerationSettings.fromJsonString(jsonStr!);

      expect(restored.temperature, 0.7);
      expect(restored.maxLength, isNull);
    });

    test('round-trip with empty settings', () {
      final original = ChatGenerationSettings();

      expect(original.toJsonString(), isNull);
    });
  });
}
