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

// THE VERIFIER'S HUNGER RULE WAS DEAD FOR EVERY REAL NEEDS OUTPUT.
//
// The rule probed the plain key 'hunger', but the needs eval emits
// 'hunger_delta' — and the strict-quote extractor ("hunger"\s*:) can never
// match `"hunger_delta"`, so h was always 0 and the "hunger delta without
// eating" correction never fired on genuine output (2026-08-10 eval review).
// The dedicated suite never caught it because its assertions were
// anyOf('corrected','accepted') — green either way. Fixed: probe
// 'hunger_delta' first, keep plain 'hunger' as the fallback the parser also
// accepts. These tests assert STRICT outcomes so the rule can never go
// silently dead again.
//
// Guard proven to fail: reverting the probe to plain 'hunger' sends the two
// hunger_delta tests red (status comes back 'accepted', the spike survives);
// restored, they are green again.
//
// The extractors are the PRODUCT's own (evalJsonInt / evalJsonBool, which
// LlmEvalEngine.extractJsonInt forwards to). The strict-quote matching is
// half the bug under guard, so a local copy could drift away from the real
// regex and leave this suite green while the rule went dead again. It used to
// be a local copy; it is not any more.

import 'package:flutter_test/flutter_test.dart';

import 'package:front_porch_ai/services/chat/chat.dart'
    show RealismVerification, evalJsonBool, evalJsonInt;

RealismVerification _verifier() {
  return RealismVerification(
    // Null re-fire: the reprocess loop breaks immediately and verify()
    // returns the RULE's own correction — which is exactly the layer under
    // guard here.
    fireLLMEval: (p, {onChunk}) async => null,
    stripThinkBlocks: (s) => s,
    extractJsonInt: evalJsonInt,
    extractJsonBool: evalJsonBool,
    getActiveCharacter: () => null,
    getActiveGroup: () => null,
    getIsObserverMode: () => false,
    getUserName: () => 'You',
    getMessages: () => const [],
    getRealismVerificationEnabled: () => true,
    getVerificationMaxReprocesses: () => 1,
    getVerificationStrictness: () => 3,
  );
}

void main() {
  group('needs verifier hunger rule (hunger_delta key)', () {
    test('an out-of-scene hunger_delta spike is corrected to ±2', () async {
      final r = await _verifier().verify(
        evalKind: 'needs_impact',
        rawOutput: '{"hunger_delta": 20, "reason": "just chatting"}',
        sceneResponse: 'we sat on the porch and swapped stories',
      );
      expect(
        r.status,
        'corrected',
        reason:
            'THE BUG. Probing the plain key "hunger" against real output '
            '(which says "hunger_delta") extracts nothing, h stays 0, and a '
            '+20 hunger swing in a scene with no food sails through as '
            '"accepted".',
      );
      expect(r.correctedRaw, contains('"hunger_delta": 2'));
      expect(r.correctedRaw, isNot(contains('20')));
    });

    test('the sign survives the correction (−20 → −2)', () async {
      final r = await _verifier().verify(
        evalKind: 'needs_impact',
        rawOutput: '{"hunger_delta": -20, "reason": "starving suddenly"}',
        sceneResponse: 'we sat on the porch and swapped stories',
      );
      expect(r.status, 'corrected');
      expect(r.correctedRaw, contains('"hunger_delta": -2'));
    });

    test('the plain "hunger" key remains a live fallback', () async {
      final r = await _verifier().verify(
        evalKind: 'needs_impact',
        rawOutput: '{"hunger": 20, "reason": "just chatting"}',
        sceneResponse: 'we sat on the porch and swapped stories',
      );
      expect(r.status, 'corrected');
      expect(r.correctedRaw, contains('"hunger": 2'));
    });

    test('a scene that actually involves eating is left alone', () async {
      final r = await _verifier().verify(
        evalKind: 'needs_impact',
        rawOutput: '{"hunger_delta": -20, "reason": "a full dinner"}',
        sceneResponse: 'she eats the whole plate of biscuits',
      );
      expect(r.status, 'accepted');
      expect(r.correctedRaw, contains('-20'));
    });

    test('a within-threshold delta is left alone', () async {
      final r = await _verifier().verify(
        evalKind: 'needs_impact',
        rawOutput: '{"hunger_delta": -5, "reason": "a long evening"}',
        sceneResponse: 'we sat on the porch and swapped stories',
      );
      expect(r.status, 'accepted');
    });
  });
}
