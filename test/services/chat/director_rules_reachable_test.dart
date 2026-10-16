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

// TWO DIRECTOR RULES THAT COULD NEVER FIRE (1.3 sweep, _idx 71 + 72).
//
// Both were dead on the KEYS, so every existing test stayed green: the
// 'extreme bond swing' damper read the pre-state bond from 'short_term_bond' /
// 'bond' while ChatService._captureRealismState writes 'affectionScore' (so
// preBond was always 0), and the emotion rule probed 'character_emotion' plus
// an INT intensity while every producer emits 'emotion' plus the string enum
// mild|moderate|strong. These tests feed the shapes production actually
// produces, so a rename on either side goes red instead of silently switching
// the Director off. maxPassesOverride: 0 keeps them pure — rule checks only,
// no LLM critique.

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/services/chat/realism_verification/realism_director_rules.dart';

import 'realism_verification_test.dart' show createTestRealismVerification;

void main() {
  group('extreme bond swing damper (production pre-state keys)', () {
    test('fires on a near-max bond from _captureRealismState', () async {
      final v = createTestRealismVerification();
      final r = await v.verify(
        evalKind: 'relationship',
        rawOutput: '{"relationship_delta": 15, "trust_delta": 0}',
        sceneResponse: 'she kisses you, trembling',
        preState: const {'affectionScore': 280},
        strictnessOverride: 3,
        maxPassesOverride: 0,
      );
      expect(r.reason, 'extreme bond swing');
      expect(r.correctedRaw, contains('"relationship_delta": 6'));
    });

    test('leaves an ordinary bond alone', () async {
      final v = createTestRealismVerification();
      final r = await v.verify(
        evalKind: 'relationship',
        rawOutput: '{"relationship_delta": 15, "trust_delta": 0}',
        sceneResponse: 'she kisses you, trembling',
        preState: const {'affectionScore': 40},
        strictnessOverride: 3,
        maxPassesOverride: 0,
      );
      expect(r.status, 'accepted');
      expect(r.correctedRaw, contains('15'));
    });
  });

  group('unsupported strong emotion damper (production eval shape)', () {
    test('fires on {"emotion": ..., "emotion_intensity": "strong"}', () async {
      final v = createTestRealismVerification();
      final r = await v.verify(
        evalKind: 'emotional_state',
        rawOutput: '{"emotion": "sad", "emotion_intensity": "strong"}',
        sceneResponse: 'she asks about the weather and pours the coffee',
        strictnessOverride: 3,
        maxPassesOverride: 0,
      );
      expect(r.reason, 'strong emotion w/o support');
      expect(
        r.correctedRaw,
        contains('"emotion_intensity": "mild"'),
        reason:
            'the evals parse the quoted enum, so a numeric damp would be '
            'a silent no-op',
      );
    });

    test('accepts an emotion the scene supports', () async {
      final v = createTestRealismVerification();
      final r = await v.verify(
        evalKind: 'emotional_state',
        rawOutput: '{"emotion": "sad", "emotion_intensity": "strong"}',
        sceneResponse: 'she wipes a tear and turns away, crying',
        strictnessOverride: 3,
        maxPassesOverride: 0,
      );
      expect(r.status, 'accepted');
      expect(r.correctedRaw, contains('strong'));
    });

    test('mild intensity is never damped', () async {
      final v = createTestRealismVerification();
      final r = await v.verify(
        evalKind: 'emotional_state',
        rawOutput: '{"emotion": "sad", "emotion_intensity": "mild"}',
        sceneResponse: 'she asks about the weather and pours the coffee',
        strictnessOverride: 3,
        maxPassesOverride: 0,
      );
      expect(r.status, 'accepted');
    });
  });

  group('the critique prompt preserves the mood keys (mood with bite)', () {
    // The Director REWRITES the eval text and the rewrite is what gets
    // parsed, so a key the hint forgets is a key the mood never gets (the
    // "serves_ambition" lesson in the rules file).
    String hint(String kind) =>
        RealismDirectorRules(
          extractJsonInt: (_, _) => null,
        ).buildReprocessCritiquePrompt(
          originalRaw: '{"emotion": "sad", "emotion_intensity": "strong"}',
          reason: 'strong emotion w/o support',
          suggested: '{"emotion_intensity": "mild"}',
          bundle: {
            'eval_kind': kind,
            'char_name': 'Vera',
            'pre_state': <String, dynamic>{},
            'scene': 'she pours the coffee',
          },
          strict: 3,
        );

    test('emotional_state names cause and change', () {
      final h = hint('emotional_state');
      expect(h, contains('"emotion_cause"'));
      expect(h, contains('"emotion_change"'));
      expect(h, contains('carry cause and change through unchanged'));
    });

    test('oneShot names cause and change', () {
      final h = hint('oneShot');
      expect(h, contains('"emotion_cause"'));
      expect(h, contains('"emotion_change"'));
    });

    test('relationship does not invent them', () {
      expect(hint('relationship'), isNot(contains('"emotion_cause"')));
    });
  });
}
