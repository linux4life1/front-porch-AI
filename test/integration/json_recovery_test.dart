// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Integration tests for the JSON recovery pipeline:
// LLM output → JsonSanitizer → parse → use.
//
// Tests the full pipeline from raw LLM output (with markdown fences,
// thinking tags, trailing commas, etc.) to usable Dart objects.

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/utils/json_sanitizer.dart';

void main() {
  // ─── 4.2: JSON Recovery Pipeline ───────────────────────────────────

  group('JSON Recovery Pipeline', () {
    test('realistic LLM output with thinking tags and trailing commas', () {
      // Simulate a realistic LLM response with common issues
      const rawOutput = '''
<thinking>
Let me analyze the character's emotional state and relationship dynamics.
The user just complimented the character, so I should show a positive
emotion response with a small bond increase.
</thinking>

Here is the JSON response:
{
  "bond_delta": 3,
  "emotion_label": "happy",
  "emotion_intensity": "mild",
  "arousal_delta": 0,
  "trust_delta": 1,
  "mood_delta": 2,
  "narrative_note": "The character smiles warmly at the compliment.",
}
''';

      final sanitized = JsonSanitizer.sanitize(rawOutput);
      final result = JsonSanitizer.tryParse(sanitized);

      expect(result, isNotNull, reason: 'sanitized JSON should parse');
      expect(result, isA<Map>());
      final json = result as Map;
      expect(json['bond_delta'], 3);
      expect(json['emotion_label'], 'happy');
      expect(json['emotion_intensity'], 'mild');
      expect(json['arousal_delta'], 0);
      expect(json['trust_delta'], 1);
      expect(json['mood_delta'], 2);
      expect(json['narrative_note'],
          'The character smiles warmly at the compliment.');
    });

    test('completely broken JSON with no structure', () {
      const rawOutput = '''
I don\'t know what to say. The character is just standing there.
Maybe something like: {"bond_delta": 0, "emotion_label": "uncertain"}
but I\'m not sure.
''';

      final sanitized = JsonSanitizer.sanitize(rawOutput);
      final result = JsonSanitizer.tryParse(sanitized);

      // Should extract the JSON object from the surrounding text
      expect(result, isNotNull);
      if (result != null) {
        final json = result as Map;
        expect(json['bond_delta'], 0);
        expect(json['emotion_label'], 'uncertain');
      }
    });

    test('JSON with markdown fences and thinking tags', () {
      const rawOutput = '''
<thinking>
Analyzing the scene...
</thinking>

```json
{
  "bond_delta": -2,
  "emotion_label": "annoyed",
  "arousal_delta": 0,
  "trust_delta": -1,
}
```
''';

      final sanitized = JsonSanitizer.sanitize(rawOutput);
      final result = JsonSanitizer.tryParse(sanitized);

      expect(result, isNotNull);
      final json = result as Map;
      expect(json['bond_delta'], -2);
      expect(json['emotion_label'], 'annoyed');
      expect(json['trust_delta'], -1);
    });

    test('JSON with misspelled thinking tags', () {
      const rawOutput = '''
<ink>thinking</ink>some analysis here
{"bond_delta": 5, "emotion_label": "excited"}
''';

      final sanitized = JsonSanitizer.sanitize(rawOutput);
      final result = JsonSanitizer.tryParse(sanitized);

      expect(result, isNotNull);
      final json = result as Map;
      expect(json['bond_delta'], 5);
    });

    test('empty input returns empty string', () {
      expect(JsonSanitizer.sanitize(''), '');
    });

    test('empty input to tryParse returns null', () {
      expect(JsonSanitizer.tryParse(''), isNull);
    });

    test('random text with no JSON returns null', () {
      const rawOutput = 'This is just random text with no JSON at all.';
      expect(JsonSanitizer.tryParse(rawOutput), isNull);
    });

    test('JSON with nested objects', () {
      const rawOutput = '''
{
  "bond_delta": 3,
  "metadata": {
    "source": "relationship_eval",
    "confidence": 0.85,
    "details": {
      "trigger": "compliment",
      "intensity": "moderate"
    }
  },
}
''';

      final sanitized = JsonSanitizer.sanitize(rawOutput);
      final result = JsonSanitizer.tryParse(sanitized);

      expect(result, isNotNull);
      final json = result as Map;
      expect(json['bond_delta'], 3);
      final meta = json['metadata'] as Map;
      expect(meta['source'], 'relationship_eval');
      expect(meta['confidence'], 0.85);
      final details = meta['details'] as Map;
      expect(details['trigger'], 'compliment');
    });

    test('JSON with arrays', () {
      const rawOutput = '''
{
  "bond_delta": 2,
  "trigger_keywords": ["compliment", "kindness", "support"],
  "emotion_label": "grateful",
}
''';

      final sanitized = JsonSanitizer.sanitize(rawOutput);
      final result = JsonSanitizer.tryParse(sanitized);

      expect(result, isNotNull);
      final json = result as Map;
      expect(json['bond_delta'], 2);
      final keywords = json['trigger_keywords'] as List;
      expect(keywords, hasLength(3));
      expect(keywords[0], 'compliment');
      expect(keywords[1], 'kindness');
      expect(keywords[2], 'support');
    });

    test('JSON with mixed types', () {
      const rawOutput = '''
{
  "bond_delta": 5,
  "trust_delta": -3,
  "emotion_label": "conflicted",
  "arousal_delta": 1,
  "is_climax": false,
  "narrative_note": null,
  "tags": ["tension", "romance"],
}
''';

      final sanitized = JsonSanitizer.sanitize(rawOutput);
      final result = JsonSanitizer.tryParse(sanitized);

      expect(result, isNotNull);
      final json = result as Map;
      expect(json['bond_delta'], 5);
      expect(json['trust_delta'], -3);
      expect(json['emotion_label'], 'conflicted');
      expect(json['arousal_delta'], 1);
      expect(json['is_climax'], false);
      expect(json['narrative_note'], isNull);
      expect(json['tags'], hasLength(2));
    });

    test('JSON with escaped quotes inside strings', () {
      const rawOutput = '''
{
  "bond_delta": 2,
  "narrative_note": "She said \\"thank you\\" with a smile.",
}
''';

      final sanitized = JsonSanitizer.sanitize(rawOutput);
      final result = JsonSanitizer.tryParse(sanitized);

      expect(result, isNotNull);
      final json = result as Map;
      expect(
        json['narrative_note'],
        'She said "thank you" with a smile.',
      );
    });

    test('JSON with literal newlines in strings gets escaped', () {
      // Simulate LLM output with literal newlines inside a string value
      const rawOutput = '''
{
  "bond_delta": 1,
  "narrative_note": "Line one
Line two",
}
''';

      final sanitized = JsonSanitizer.sanitize(rawOutput);
      final result = JsonSanitizer.tryParse(sanitized);

      // The sanitizer should escape the literal newlines
      expect(result, isNotNull);
    });

    test('tryParse handles empty string gracefully', () {
      expect(JsonSanitizer.tryParse(''), isNull);
    });

    test('full pipeline: raw LLM → sanitize → parse → apply', () {
      const rawLlmOutput = '''
<thinking>
The user just helped the character in a difficult situation.
This should increase trust significantly and create a positive emotion.
</thinking>

{
  "bond_delta": 8,
  "trust_delta": 5,
  "emotion_label": "grateful",
  "emotion_intensity": "strong",
  "arousal_delta": 0,
  "mood_delta": 3,
  "narrative_note": "The character looks at you with deep appreciation.",
}
''';

      // Step 1: Sanitize
      final sanitized = JsonSanitizer.sanitize(rawLlmOutput);
      expect(sanitized, isNotEmpty);
      expect(sanitized, isNot(contains('```')));
      expect(sanitized, isNot(contains('<thinking>')));

      // Step 2: Parse
      final parsed = JsonSanitizer.tryParse(sanitized);
      expect(parsed, isNotNull);
      expect(parsed, isA<Map>());

      // Step 3: Apply (simulated)
      final json = parsed as Map;
      final bondDelta = json['bond_delta'] as int;
      final trustDelta = json['trust_delta'] as int;
      final emotion = json['emotion_label'] as String;

      expect(bondDelta, 8);
      expect(trustDelta, 5);
      expect(emotion, 'grateful');
    });
  });
}
