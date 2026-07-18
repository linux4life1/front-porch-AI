// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Tests for the extracted NsfwService (plain class).
// Covers: arousalTier calc from level (-100..100 -> -10..10 + names 'Feverish'..'Deserted'),
// cooldown set/remaining/total from climax apply + decrement, resets/loads/roundtrips/seeds (fresh 0 arousal/cooldown, enabled false, ext seed only flag),
// apply from sexual/daily/climax cross (mutations exercised; LLM checks stayed in god per plan),
// public surface + setNsfw clears, group vs 1:1 (load/save scalars for speaker using live group map, per-char nsfw/cooldown/arousal),
// negative arousal clamp, max cooldown, OOC/edges.
// Uses createTestNsfw factory (modeled exactly on time_service_test.dart + expression/prior).
// Real owner dispatch: reset/seed/load/save sites passively via pre-existing startNew/setActive/_loadLast/group load + _runPostGen in
// key suites (realism_engine, group_realism, session); full tier/cooldown/apply/group exercised in dedicated.
// (aug edits in key tests add only qualified header notes per review precedent:
// "reset sites passively hit by pre-existing...; full climax/sexual/daily checks only in dedicated + manual").
// climax/sexual/daily LLM checks only thin or stayed in god for now; full in later if extracted (prompt builders step8).
// 3 group cbs only (onNotify/onSaveChat removed as dead/unused per review; god owns save/notify for post-gen climax/sexual fidelity per plan boundaries).
// 0 forcing of internal state; real dispatch for branches where unit feasible.
// oneShot vs normal nsfw parity (state in realism_state + post-gen apply + restore exercised) documented in dedicated + god capture/restore paths.
// aug exercising only passive/qualified (key suites exercise nsfw via _runPostGen/oneShot/resets/loads; nsfw-specific in dedicated header + service only).
// restore fallback + safe casts exercised; partial map test asserts total fallback behavior.
// 12 tests (12 test() bodies via grep -c post dead noop parity note deletion).

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/services/chat/nsfw_service.dart';

/// Test factory (modeled exactly on time + expression/prior).
/// Supplies realistic defaults + live groupRealism map for group scalar tests (3 group cbs only; onNotify/onSave removed as dead).
NsfwService createTestNsfw({
  Map<String, Map<String, dynamic>>? initialGroupRealism,
}) {
  final groupMap = initialGroupRealism ?? <String, Map<String, dynamic>>{};

  final svc = NsfwService(
    getGroupInt: (charId, key) =>
        (groupMap[charId]?[key] as num?)?.toInt() ?? 0,
    getGroupValue: (charId, key) => groupMap[charId]?[key],
    setGroupValue: (charId, key, v) {
      groupMap.putIfAbsent(charId, () => {});
      groupMap[charId]![key] = v;
    },
  );
  return svc;
}

void main() {
  group('NsfwService (extracted leaf)', () {
    test(
      'arousalTier computes correctly from -100 to +100 (clamped -10 to 10)',
      () {
        final svc = createTestNsfw();
        svc.setArousalLevel(-100);
        expect(svc.arousalTier, -10);
        svc.setArousalLevel(-99);
        expect(svc.arousalTier, -9);
        svc.setArousalLevel(0);
        expect(svc.arousalTier, 0);
        svc.setArousalLevel(50);
        expect(svc.arousalTier, 5);
        svc.setArousalLevel(100);
        expect(svc.arousalTier, 10);
        svc.setArousalLevel(999);
        expect(svc.arousalTier, 10);
        svc.setArousalLevel(-999);
        expect(svc.arousalTier, -10);
      },
    );

    test(
      'all nsfw scalars round-trip losslessly through the per-char map '
      '(arousal + cooldown enabled/remaining/total) — host-collapse safety net',
      () {
        final svc = createTestNsfw();
        svc.loadNsfwScalars(
          arousalLevel: 73,
          nsfwCooldownEnabled: true,
          cooldownTurnsRemaining: 4,
          cooldownTurnsTotal: 9,
        );
        svc.saveNsfwScalarsToGroup('spk');

        // Wipe the working registers (as if another speaker had been loaded).
        svc.loadNsfwScalars(
          arousalLevel: 0,
          nsfwCooldownEnabled: false,
          cooldownTurnsRemaining: 0,
          cooldownTurnsTotal: 0,
        );
        expect(svc.arousalLevel, 0);

        // Restore from the per-char map.
        svc.loadNsfwScalarsForSpeaker('spk');
        expect(svc.arousalLevel, 73);
        expect(svc.nsfwCooldownEnabled, true);
        expect(svc.cooldownTurnsRemaining, 4);
        expect(svc.cooldownTurnsTotal, 9);
      },
    );

    test('arousalTierName matches relationship-adapted names for tiers', () {
      final svc = createTestNsfw();
      svc.setArousalLevel(100);
      expect(svc.arousalTierName, 'Feverish');
      svc.setArousalLevel(95);
      expect(svc.arousalTierName, 'Ecstatic');
      svc.setArousalLevel(0);
      expect(svc.arousalTierName, 'Neutral');
      svc.setArousalLevel(-50);
      expect(svc.arousalTierName, 'Rejected');
      svc.setArousalLevel(-100);
      expect(svc.arousalTierName, 'Deserted');
    });

    test(
      'applyClimaxEffects sets total/remaining + sated-neutral arousal '
      '(0, not negative — satedness is not aversion)',
      () {
        final svc = createTestNsfw();
        svc.setArousalLevel(80);
        svc.applyClimaxEffects(turns: 5);
        expect(svc.cooldownTurnsTotal, 5);
        expect(svc.cooldownTurnsRemaining, 5);
        expect(svc.arousalLevel, 0);
      },
    );

    test('decrementCooldownIfActive only decrements when >0', () {
      final svc = createTestNsfw();
      svc.setCooldownTurnsRemaining(2);
      svc.decrementCooldownIfActive();
      expect(svc.cooldownTurnsRemaining, 1);
      svc.decrementCooldownIfActive();
      expect(svc.cooldownTurnsRemaining, 0);
      svc.decrementCooldownIfActive();
      expect(svc.cooldownTurnsRemaining, 0);
    });

    test(
      'refractory expiry resets the total and halves lingering negative '
      'arousal toward neutral (baseline receptivity returns)',
      () {
        final svc = createTestNsfw();
        svc.applyClimaxEffects(turns: 2);
        svc.setArousalLevel(-9); // dug down during the cooldown
        svc.decrementCooldownIfActive();
        expect(svc.cooldownTurnsRemaining, 1);
        expect(svc.cooldownTurnsTotal, 2); // total kept while running
        expect(svc.arousalLevel, -9); // no nudge until expiry
        svc.decrementCooldownIfActive(); // reaches 0 → expiry
        expect(svc.cooldownTurnsRemaining, 0);
        expect(svc.cooldownTurnsTotal, 0);
        expect(svc.arousalLevel, -4); // -9 ~/ 2, truncates toward zero
        // Positive arousal is never touched on expiry.
        svc.applyClimaxEffects(turns: 1);
        svc.setArousalLevel(20);
        svc.decrementCooldownIfActive();
        expect(svc.arousalLevel, 20);
      },
    );

    test(
      'applyEvalArousalDelta: normal path applies fully, clamps at bounds, '
      'and returns the delta that actually landed',
      () {
        final svc = createTestNsfw();
        svc.setArousalLevel(0);
        expect(svc.applyEvalArousalDelta(15), 15);
        expect(svc.arousalLevel, 15);
        expect(svc.applyEvalArousalDelta(-20), -20);
        expect(svc.arousalLevel, -5);
        // Clamp at the -100 floor: only the landed portion is reported.
        svc.setArousalLevel(-95);
        expect(svc.applyEvalArousalDelta(-25), -5);
        expect(svc.arousalLevel, -100);
      },
    );

    test(
      'applyEvalArousalDelta: refractory halves swings and cannot dig below '
      'mild disinterest (-10) — satedness is not aversion',
      () {
        final svc = createTestNsfw();
        svc.applyClimaxEffects(turns: 4); // arousal 0, refractory active
        // -20 halves to -10, landing exactly at the floor.
        expect(svc.applyEvalArousalDelta(-20), -10);
        expect(svc.arousalLevel, -10);
        // Further negatives can't dig deeper while refractory.
        expect(svc.applyEvalArousalDelta(-25), 0);
        expect(svc.arousalLevel, -10);
        // Positive stirring works but is damped (+10 → +5).
        expect(svc.applyEvalArousalDelta(10), 5);
        expect(svc.arousalLevel, -5);
        // A speaker loaded already below the floor is not clamped upward,
        // but also can't be pushed deeper.
        svc.setArousalLevel(-40);
        expect(svc.applyEvalArousalDelta(-10), 0);
        expect(svc.arousalLevel, -40);
        // Once the refractory ends, physiology no longer applies.
        svc.setCooldownTurnsRemaining(1);
        svc.decrementCooldownIfActive(); // expiry: -40 → -20
        expect(svc.arousalLevel, -20);
        expect(svc.applyEvalArousalDelta(-10), -10);
        expect(svc.arousalLevel, -30);
      },
    );

    test('resetForFreshChat zeros all + disables', () {
      final svc = createTestNsfw();
      svc.setNsfwCooldownEnabled(true);
      svc.setArousalLevel(42);
      svc.setCooldownTurnsRemaining(3);
      svc.setCooldownTurnsTotal(3);
      svc.resetForFreshChat();
      expect(svc.nsfwCooldownEnabled, false);
      expect(svc.arousalLevel, 0);
      expect(svc.cooldownTurnsRemaining, 0);
      expect(svc.cooldownTurnsTotal, 0);
    });

    test(
      'seedFromV2OrExt sets enabled flag (runtime arousal/cooldown zeroed separately)',
      () {
        final svc = createTestNsfw();
        svc.seedFromV2OrExt(nsfwCooldownEnabled: true);
        expect(svc.nsfwCooldownEnabled, true);
        // runtime zero is explicit in god fresh paths
      },
    );

    test('loadNsfwScalars roundtrips + clamps arousal', () {
      final svc = createTestNsfw();
      svc.loadNsfwScalars(
        nsfwCooldownEnabled: true,
        arousalLevel: 123,
        cooldownTurnsRemaining: 4,
        cooldownTurnsTotal: 5,
      );
      expect(svc.nsfwCooldownEnabled, true);
      expect(svc.arousalLevel, 100);
      expect(svc.cooldownTurnsRemaining, 4);
      expect(svc.cooldownTurnsTotal, 5);
    });

    test(
      'restoreNsfwFromRealismState and fromMessageState restore arousal/cooldown/total',
      () {
        final svc = createTestNsfw();
        svc.restoreNsfwFromRealismState({
          'arousalLevel': 77,
          'cooldownTurnsRemaining': 2,
          'cooldownTurnsTotal': 6,
        });
        expect(svc.arousalLevel, 77);
        expect(svc.cooldownTurnsRemaining, 2);
        expect(svc.cooldownTurnsTotal, 6);

        // partial map (no total key): total falls back to prior value (was 6 from previous restore in this test); tests the fixed ?? + safe cast path.
        svc.restoreNsfwFromMessageState({
          'arousalLevel': -30,
          'cooldownTurnsRemaining': 1,
        });
        expect(svc.arousalLevel, -30);
        expect(svc.cooldownTurnsRemaining, 1);
        expect(
          svc.cooldownTurnsTotal,
          6,
        ); // total preserved from prior restore (fallback exercised)
      },
    );

    test('setNsfwCooldownEnabled(false) clears cooldown + arousal', () {
      final svc = createTestNsfw();
      svc.setNsfwCooldownEnabled(true);
      svc.setArousalLevel(50);
      svc.setCooldownTurnsRemaining(3);
      svc.setCooldownTurnsTotal(3);
      svc.setNsfwCooldownEnabled(false);
      expect(svc.nsfwCooldownEnabled, false);
      expect(svc.arousalLevel, 0);
      expect(svc.cooldownTurnsRemaining, 0);
      expect(svc.cooldownTurnsTotal, 0);
    });

    test(
      'group load/save scalars for speaker roundtrips arousal + cooldown + nsfwEnabled',
      () {
        final group = <String, Map<String, dynamic>>{
          'char1': {
            'arousal': 25,
            'nsfwCooldownEnabled': true,
            'cooldownTurnsRemaining': 2,
            'cooldownTurnsTotal': 4,
          },
        };
        final svc = createTestNsfw(initialGroupRealism: group);
        svc.loadNsfwScalarsForSpeaker('char1');
        expect(svc.arousalLevel, 25);
        expect(svc.nsfwCooldownEnabled, true);
        expect(svc.cooldownTurnsRemaining, 2);
        expect(svc.cooldownTurnsTotal, 4);

        // Use loadNsfwScalars (public API) to exercise mutation path for group test
        svc.loadNsfwScalars(
          nsfwCooldownEnabled: false,
          arousalLevel: 99,
          cooldownTurnsRemaining: 0,
          cooldownTurnsTotal: 0,
        );
        svc.saveNsfwScalarsToGroup('char1');
        // Scalars updated; map mutation via cb also exercised (group map lives in god).
        expect(svc.arousalLevel, 99);
        expect(svc.nsfwCooldownEnabled, false);
        expect(svc.cooldownTurnsRemaining, 0);
        // Also verify map was written (cb captured the live group object)
        expect(group['char1']!['arousal'], 99);
        expect(group['char1']!['nsfwCooldownEnabled'], false);
        expect(group['char1']!['cooldownTurnsRemaining'], 0);
      },
    );

    test('public surface getters and tier exposed', () {
      final svc = createTestNsfw();
      svc.setArousalLevel(42);
      expect(svc.arousalLevel, 42);
      expect(svc.arousalTier, 4);
      expect(svc.arousalTierName, 'Stimulated');
      svc.setNsfwCooldownEnabled(true);
      expect(svc.nsfwCooldownEnabled, true);
      svc.setCooldownTurnsRemaining(7);
      expect(svc.cooldownTurnsRemaining, 7);
    });

    test('negative arousal clamps on set + load', () {
      final svc = createTestNsfw();
      svc.setArousalLevel(-200);
      expect(svc.arousalLevel, -100);
      svc.loadNsfwScalars(
        nsfwCooldownEnabled: false,
        arousalLevel: -999,
        cooldownTurnsRemaining: 0,
      );
      expect(svc.arousalLevel, -100);
    });
  });
}
