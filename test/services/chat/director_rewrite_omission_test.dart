// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Director rewrite that omits keys used to REPLACE the original eval JSON.
// Missing relationship_delta is treated as 0, so the rule check PASSES and
// the chips vanish — Jennifer's last two regens (bond already at 300, so
// "extreme bond swing" always reprocesses a 15) landed as emotion-only
// rewrites with no bond/trust/arousal. Omitted ≠ 0; overlay onto original.

import 'package:flutter_test/flutter_test.dart';

import 'package:front_porch_ai/services/chat/eval_json_merge.dart';

import 'realism_verification_test.dart' show createTestRealismVerification;

int? _int(String raw, String key) {
  final m = RegExp('"$key"\\s*:\\s*(-?\\d+)').firstMatch(raw);
  return m != null ? int.tryParse(m.group(1)!) : null;
}

String? _str(String raw, String key) {
  final m = RegExp('"$key"\\s*:\\s*"([^"]*)"').firstMatch(raw);
  return m?.group(1);
}

void main() {
  group('mergeEvalJson', () {
    test('omitted keys keep the original values', () {
      const original =
          '{"relationship_delta":6,"trust_delta":8,"emotion":"excitement"}';
      const rewrite = '{"emotion":"devotion","emotion_intensity":"strong"}';
      final merged = mergeEvalJson(original, rewrite);
      expect(_int(merged, 'relationship_delta'), 6);
      expect(_int(merged, 'trust_delta'), 8);
      expect(_str(merged, 'emotion'), 'devotion');
      expect(_str(merged, 'emotion_intensity'), 'strong');
    });

    test('explicit zero in the rewrite wins', () {
      const original = '{"relationship_delta":6,"trust_delta":8}';
      const rewrite = '{"relationship_delta":0}';
      final merged = mergeEvalJson(original, rewrite);
      expect(_int(merged, 'relationship_delta'), 0);
      expect(_int(merged, 'trust_delta'), 8);
    });

    test('non-JSON rewrite keeps the original', () {
      const original = '{"relationship_delta":6}';
      expect(mergeEvalJson(original, 'not json'), original);
      expect(mergeEvalJson(original, ''), original);
      expect(mergeEvalJson(original, '{}'), original);
    });

    test('tool-call envelope arguments overlay the original', () {
      const original =
          '{"relationship_delta":6,"trust_delta":8,"emotion":"excitement"}';
      const rewrite =
          '{"name":"report_realism","arguments":{"emotion":"devotion"}}';
      final merged = mergeEvalJson(original, rewrite);
      expect(_int(merged, 'relationship_delta'), 6);
      expect(_str(merged, 'emotion'), 'devotion');
    });
  });

  group('Director one-shot rewrite must not wipe deltas', () {
    test(
      'emotion-only reprocess keeps the damped bond/trust from the original',
      () async {
        final v = createTestRealismVerification(
          fireFn: (p, {onChunk}) async =>
              '{"emotion":"devotion","emotion_intensity":"strong"}',
        );
        final r = await v.verify(
          evalKind: 'oneShot',
          rawOutput:
              '{"relationship_delta":15,"trust_delta":8,"arousal_delta":10,'
              '"emotion":"excitement","emotion_intensity":"strong"}',
          sceneResponse: 'she kisses you, trembling',
          preState: const {'affectionScore': 300},
          strictnessOverride: 3,
          maxPassesOverride: 1,
        );
        expect(r.status, 'corrected');
        final raw = r.correctedRaw ?? '';
        expect(
          _int(raw, 'relationship_delta'),
          isNotNull,
          reason:
              'omitting relationship_delta used to pass the rule check '
              'as 0 and replace the original, wiping the chips',
        );
        expect(_int(raw, 'relationship_delta'), isNot(0));
        expect(_int(raw, 'trust_delta'), 8);
        expect(_int(raw, 'arousal_delta'), 10);
        expect(_str(raw, 'emotion'), 'devotion');
      },
    );

    test('explicit zero from the Director still lands', () async {
      final v = createTestRealismVerification(
        fireFn: (p, {onChunk}) async =>
            '{"relationship_delta":0,"trust_delta":0,"emotion":"predatory"}',
      );
      final r = await v.verify(
        evalKind: 'oneShot',
        rawOutput:
            '{"relationship_delta":15,"trust_delta":8,"emotion":"excitement"}',
        sceneResponse: 'she kisses you, trembling',
        preState: const {'affectionScore': 300},
        strictnessOverride: 3,
        maxPassesOverride: 1,
      );
      expect(_int(r.correctedRaw ?? '', 'relationship_delta'), 0);
      expect(_str(r.correctedRaw ?? '', 'emotion'), 'predatory');
    });
  });

  group('Director rejects all-zero needs impact', () {
    test(
      'all zeros is not accepted — reprocess can land a scene delta',
      () async {
        final v = createTestRealismVerification(
          fireFn: (p, {onChunk}) async =>
              '{"hunger_delta":0,"energy_delta":-4,"hygiene_delta":0,'
              '"fun_delta":6,"social_delta":8,"bladder_delta":50,'
              '"comfort_delta":3,"reason":"the beat moved her"}',
        );
        final r = await v.verify(
          evalKind: 'needs_impact',
          rawOutput:
              '{"hunger_delta":0,"energy_delta":0,"hygiene_delta":0,'
              '"fun_delta":0,"social_delta":0,"bladder_delta":0,'
              '"comfort_delta":0,"reason":"none"}',
          sceneResponse: 'she pees on him, riding hard',
          maxPassesOverride: 1,
        );
        expect(r.status, 'corrected');
        expect(_int(r.correctedRaw ?? '', 'bladder_delta'), 50);
      },
    );
  });
}
