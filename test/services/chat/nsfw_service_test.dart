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
// 2026-10-06, needs-on-the-clock v2: the refractory counts story minutes
// (judge turns × 15) with an opening-turn flag, so the turn assertions below
// became minute assertions and the per-reply decrement became
// Refractory.elapse; snapshots saved in turns are now read as turns × 15.

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/services/chat/nsfw_service.dart';
import 'package:front_porch_ai/services/chat/refractory.dart';

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

    test('all nsfw scalars round-trip losslessly through the per-char map '
        '(arousal + cooldown enabled + refractory minutes/total/opened) — '
        'host-collapse safety net', () {
      final svc = createTestNsfw();
      svc.loadNsfwScalars(
        arousalLevel: 73,
        nsfwCooldownEnabled: true,
        refractory: const Refractory(minutes: 60, total: 135, opened: true),
      );
      svc.saveNsfwScalarsToGroup('spk');

      // Wipe the working registers (as if another speaker had been loaded).
      svc.loadNsfwScalars(arousalLevel: 0, nsfwCooldownEnabled: false);
      expect(svc.arousalLevel, 0);
      expect(svc.refractory, Refractory.none);

      // Restore from the per-char map.
      svc.loadNsfwScalarsForSpeaker('spk');
      expect(svc.arousalLevel, 73);
      expect(svc.nsfwCooldownEnabled, true);
      expect(
        svc.refractory,
        const Refractory(minutes: 60, total: 135, opened: true),
      );
    });

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
      'applyClimaxEffects sets total/remaining (turns × 15 min, opening turn '
      'unspoken) + sated-neutral arousal (0, not negative — satedness is '
      'not aversion)',
      () {
        final svc = createTestNsfw();
        svc.setArousalLevel(80);
        svc.applyClimaxEffects(turns: 5);
        expect(svc.refractoryMinutesTotal, 75);
        expect(svc.refractoryMinutesRemaining, 75);
        expect(svc.refractoryOpened, isFalse);
        expect(svc.isOpeningAfterglowTurn, isTrue);
        expect(svc.arousalLevel, 0);
      },
    );

    test('elapse only runs a running refractory down, and stops at zero', () {
      var r = const Refractory(minutes: 30, total: 30);
      r = r.elapse(15, arousal: 0).refractory;
      expect(r.minutes, 15);
      r = r.elapse(15, arousal: 0).refractory;
      expect(r, Refractory.none);
      r = r.elapse(15, arousal: 0).refractory;
      expect(r, Refractory.none);
      expect(const Refractory(minutes: 30, total: 30).elapse(0, arousal: 0), (
        refractory: const Refractory(minutes: 30, total: 30),
        arousal: 0,
      ), reason: 'the same moment takes no time');
    });

    test('refractory expiry resets the total and halves lingering negative '
        'arousal toward neutral (baseline receptivity returns)', () {
      final running = Refractory.fromJudgeTurns(2); // 30 min
      // Dug down during the cooldown; no nudge until expiry.
      final half = running.elapse(15, arousal: -9);
      expect(half.refractory.minutes, 15);
      expect(half.refractory.total, 30); // total kept while running
      expect(half.arousal, -9);
      final ended = half.refractory.elapse(15, arousal: -9); // expiry
      expect(ended.refractory, Refractory.none);
      expect(ended.arousal, -4); // -9 ~/ 2, truncates toward zero
      // Positive arousal is never touched on expiry.
      expect(Refractory.fromJudgeTurns(1).elapse(60, arousal: 20).arousal, 20);
    });

    test('applyEvalArousalDelta: normal path applies fully, clamps at bounds, '
        'and returns the delta that actually landed', () {
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
    });

    test('applyEvalArousalDelta: refractory halves swings and cannot dig below '
        'mild disinterest (-10) — satedness is not aversion', () {
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
      final ended = svc.refractory.elapse(
        svc.refractoryMinutesRemaining,
        arousal: svc.arousalLevel,
      ); // expiry: -40 → -20
      svc
        ..setRefractory(ended.refractory)
        ..setArousalLevel(ended.arousal);
      expect(svc.arousalLevel, -20);
      expect(svc.applyEvalArousalDelta(-10), -10);
      expect(svc.arousalLevel, -30);
    });

    test('resetForFreshChat zeros all + disables', () {
      final svc = createTestNsfw();
      svc.setNsfwCooldownEnabled(true);
      svc.setArousalLevel(42);
      svc.setRefractory(Refractory.fromJudgeTurns(3));
      svc.resetForFreshChat();
      expect(svc.nsfwCooldownEnabled, false);
      expect(svc.arousalLevel, 0);
      expect(svc.refractory, Refractory.none);
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
        refractory: const Refractory(minutes: 60, total: 75),
      );
      expect(svc.nsfwCooldownEnabled, true);
      expect(svc.arousalLevel, 100);
      expect(svc.refractoryMinutesRemaining, 60);
      expect(svc.refractoryMinutesTotal, 75);
    });

    test('restoreNsfwFromRealismState and fromMessageState restore arousal and '
        'the refractory (minutes, total, opened)', () {
      final svc = createTestNsfw();
      svc.restoreNsfwFromRealismState({
        'arousalLevel': 77,
        'refractoryMinutesRemaining': 30,
        'refractoryMinutesTotal': 90,
        'refractoryOpened': true,
      });
      expect(svc.arousalLevel, 77);
      expect(
        svc.refractory,
        const Refractory(minutes: 30, total: 90, opened: true),
      );

      // A snapshot without the refractory keeps what is there (fallback).
      svc.restoreNsfwFromMessageState({'arousalLevel': -30});
      expect(svc.arousalLevel, -30);
      expect(
        svc.refractory,
        const Refractory(minutes: 30, total: 90, opened: true),
      );

      // The refractory is read as a unit: minutes without a total use the
      // minutes as the total (no stale total from an earlier restore).
      svc.restoreNsfwFromMessageState({'refractoryMinutesRemaining': 15});
      expect(svc.refractory, const Refractory(minutes: 15, total: 15));

      // A snapshot saved in turns reads once as turns × 15; 1 of 6 had
      // already ticked, so its opening turn was spent.
      svc.restoreNsfwFromMessageState({
        'cooldownTurnsRemaining': 1,
        'cooldownTurnsTotal': 6,
      });
      expect(
        svc.refractory,
        const Refractory(minutes: 15, total: 90, opened: true),
      );
    });

    test('setNsfwCooldownEnabled(false) keeps cooldown + arousal', () {
      final svc = createTestNsfw();
      svc.setNsfwCooldownEnabled(true);
      svc.setArousalLevel(50);
      svc.setRefractory(Refractory.fromJudgeTurns(3));
      svc.setNsfwCooldownEnabled(false);
      expect(svc.nsfwCooldownEnabled, false);
      expect(svc.arousalLevel, 50);
      expect(svc.refractory, Refractory.fromJudgeTurns(3));
    });

    test('group load/save scalars for speaker roundtrips arousal + refractory + '
        'nsfwEnabled; a member saved in turns reads them as turns × 15', () {
      final group = <String, Map<String, dynamic>>{
        'char1': {
          'arousal': 25,
          'nsfwCooldownEnabled': true,
          'refractoryMinutesRemaining': 30,
          'refractoryMinutesTotal': 60,
          'refractoryOpened': true,
        },
        'legacy': {
          'nsfwCooldownEnabled': true,
          'cooldownTurnsRemaining': 2,
          'cooldownTurnsTotal': 2,
        },
      };
      final svc = createTestNsfw(initialGroupRealism: group);
      svc.loadNsfwScalarsForSpeaker('char1');
      expect(svc.arousalLevel, 25);
      expect(svc.nsfwCooldownEnabled, true);
      expect(
        svc.refractory,
        const Refractory(minutes: 30, total: 60, opened: true),
      );

      // Use loadNsfwScalars (public API) to exercise mutation path for group test
      svc.loadNsfwScalars(nsfwCooldownEnabled: false, arousalLevel: 99);
      svc.saveNsfwScalarsToGroup('char1');
      // Scalars updated; map mutation via cb also exercised (group map lives in god).
      expect(svc.arousalLevel, 99);
      expect(svc.nsfwCooldownEnabled, false);
      expect(svc.refractoryMinutesRemaining, 0);
      // Also verify map was written (cb captured the live group object)
      expect(group['char1']!['arousal'], 99);
      expect(group['char1']!['nsfwCooldownEnabled'], false);
      expect(group['char1']!['refractoryMinutesRemaining'], 0);

      svc.loadNsfwScalarsForSpeaker('legacy');
      expect(
        svc.refractory,
        const Refractory(minutes: 30, total: 30),
        reason: 'two turns, none ticked: 30 min, opening turn unspoken',
      );
    });

    test('public surface getters and tier exposed', () {
      final svc = createTestNsfw();
      svc.setArousalLevel(42);
      expect(svc.arousalLevel, 42);
      expect(svc.arousalTier, 4);
      expect(svc.arousalTierName, 'Stimulated');
      svc.setNsfwCooldownEnabled(true);
      expect(svc.nsfwCooldownEnabled, true);
      svc.setRefractory(Refractory.fromJudgeTurns(7));
      expect(svc.refractoryMinutesRemaining, 105);
      expect(svc.refractoryWords.chip, 'Refractory: about 105 min');
    });

    test('negative arousal clamps on set + load', () {
      final svc = createTestNsfw();
      svc.setArousalLevel(-200);
      expect(svc.arousalLevel, -100);
      svc.loadNsfwScalars(nsfwCooldownEnabled: false, arousalLevel: -999);
      expect(svc.arousalLevel, -100);
    });

    test('a climax with a 0-turn verdict starts NO refractory', () {
      // PR 1 made "no cooldown needed" expressible end to end: the parser
      // lets 0 through, and applying it must not leave the old
      // parser-floor lock (1 turn = 15 min) behind. Arousal still resets,
      // exactly as with any climax.
      final svc = createTestNsfw();
      svc.setArousalLevel(90);
      svc.applyClimaxEffects(turns: 0);
      expect(svc.refractoryMinutesRemaining, 0);
      expect(svc.refractory.running, isFalse);
      expect(svc.arousalLevel, 0);
    });

    // Recovery overhaul PR 2: minutes are the canonical unit, and a card's
    // fixed recovery minutes outrank the judge's turn count.
    test('Refractory.fromMinutes is canonical — judge turns are a wrapper', () {
      expect(
        Refractory.fromMinutes(45),
        const Refractory(minutes: 45, total: 45),
      );
      expect(Refractory.fromMinutes(0), Refractory.none);
      expect(Refractory.fromMinutes(-10), Refractory.none);
      // The judge path is exactly the same math through the same door.
      expect(
        Refractory.fromJudgeTurns(4),
        Refractory.fromMinutes(4 * kRefractoryMinutesPerTurn),
      );
    });

    test('card-fixed minutes replace the judge number at climax', () {
      // An insatiable card fixed at 20 min must lock 20, not the judge's
      // 5 × 15 = 75. Arousal resets either way.
      final svc = createTestNsfw();
      svc.setArousalLevel(90);
      svc.applyClimaxEffects(turns: 5, fixedMinutes: 20);
      expect(svc.refractoryMinutesRemaining, 20);
      expect(svc.refractory.total, 20);
      expect(svc.arousalLevel, 0);
    });

    test('card-fixed 0 starts nothing even when the judge called turns', () {
      // The multiorgasmic card: a judge verdict of 6 turns is overruled by
      // the author's "None" — no lock is opened at all.
      final svc = createTestNsfw();
      svc.setArousalLevel(90);
      svc.applyClimaxEffects(turns: 6, fixedMinutes: 0);
      expect(svc.refractory, Refractory.none);
      expect(svc.arousalLevel, 0);
    });

    test('no fixed minutes leaves the judge number standing', () {
      // The card-says-nothing path is byte-identical to PR 1 behaviour.
      final svc = createTestNsfw();
      svc.applyClimaxEffects(turns: 4, fixedMinutes: null);
      expect(svc.refractoryMinutesRemaining, 60);
    });
  });

  // Recovery overhaul PR 3: the soft gate's mechanics — peak costs, the
  // Continue re-verdict rule, and the window's gains-only halving
  // (decisions 4 + 6). The numbers mirror the mockup's June simulator:
  // 100→90, 95→77, 90→66.
  group('soft gate (PR 3)', () {
    test('each peak bites harder and arousal never crashes', () {
      final svc = createTestNsfw();
      svc.setArousalLevel(100);
      svc.applyClimaxEffects(turns: 6, soft: true);
      expect(svc.arousalLevel, 90, reason: '100 − round(0.2×50×1) = 90');
      expect(svc.refractoryMinutesRemaining, kTendernessWindowMinutes);
      expect(svc.refractory.soft, isTrue);
      expect(svc.refractoryPeaksLastHour, 1);

      svc.setArousalLevel(95);
      svc.applyClimaxEffects(turns: 6, soft: true);
      expect(svc.arousalLevel, 77, reason: '95 − round(0.2×45×2) = 77');
      expect(svc.refractoryPeaksLastHour, 2);

      svc.setArousalLevel(90);
      svc.applyClimaxEffects(turns: 6, soft: true);
      expect(svc.arousalLevel, 66, reason: '90 − round(0.2×40×3) = 66');

      // The cap is what keeps the floor: a fourth peak inside the hour is
      // still counted as 3, and the stamp list holds three, oldest dropped.
      svc.setArousalLevel(80);
      svc.applyClimaxEffects(turns: 6, soft: true);
      expect(svc.arousalLevel, 62, reason: '80 − round(0.2×30×3) = 62');
      expect(svc.refractoryPeaksLastHour, 3);
    });

    test('a climax below the floor costs nothing', () {
      final svc = createTestNsfw();
      svc.setArousalLevel(50);
      svc.applyClimaxEffects(turns: 4, soft: true);
      expect(svc.arousalLevel, 50);
      svc.setArousalLevel(35);
      svc.applyClimaxEffects(turns: 4, soft: true);
      expect(svc.arousalLevel, 35);
      expect(svc.refractoryPeaksLastHour, 2, reason: 'it still counts');
    });

    test(
      'a Continue re-verdict restarts the window without a peak or cost',
      () {
        final svc = createTestNsfw();
        svc.setArousalLevel(100);
        svc.applyClimaxEffects(turns: 6, soft: true); // peak 1 → 90
        final firstPeaks = svc.refractory.peaks;
        svc.setArousalLevel(95);
        svc.applyClimaxEffects(turns: 6, soft: true, newPeak: false);
        expect(
          svc.arousalLevel,
          95,
          reason: 'a re-verdict charges no second cost',
        );
        expect(svc.refractoryPeaksLastHour, 1, reason: 'peaks cannot stack');
        expect(svc.refractoryMinutesRemaining, kTendernessWindowMinutes);
        expect(svc.refractory.peaks, firstPeaks);
      },
    );

    test('soft damping halves gains only — negatives whole, no −10 floor', () {
      final svc = createTestNsfw();
      svc.setArousalLevel(60);
      svc.applyClimaxEffects(turns: 4, soft: true); // peak 1: 60 − 2 = 58
      expect(svc.applyEvalArousalDelta(21), 11, reason: '+21 lands halved');
      expect(
        svc.applyEvalArousalDelta(-20),
        -20,
        reason: 'negatives pass whole',
      );
      svc.setArousalLevel(-30);
      expect(
        svc.applyEvalArousalDelta(-25),
        -25,
        reason:
            'the −10 satedness floor is hard-lock semantics; a soft body\'s '
            'desire stays up, so a real letdown must read true',
      );
    });

    test('the soft chip names the tenderness and the peak count', () {
      expect(
        describeRefractory(15, clockRunning: true, soft: true, peaks: 1).chip,
        'Tender for about 15 min · peak 1',
      );
      expect(
        describeRefractory(30, clockRunning: false, soft: true, peaks: 3).chip,
        'Tender for 2 replies · peak 3',
      );
      expect(
        describeRefractory(30, clockRunning: true).chip,
        'Refractory: about 30 min',
        reason: 'the hard copy is unchanged',
      );
    });

    test('soft state round-trips the snapshot; defaults stay byte-stable', () {
      const soft = Refractory(
        minutes: 12,
        total: 15,
        soft: true,
        peaks: [20, 0],
      );
      final snap = soft.toSnapshot();
      expect(snap[RefractoryKeys.soft], true);
      expect(snap[RefractoryKeys.peaks], [20, 0]);
      expect(Refractory.read(snap), soft);

      // A hard body's snapshot grows no new keys — receipts, rows, and
      // member maps from before PR 3 stay byte-identical.
      final hardSnap = const Refractory(minutes: 30, total: 30).toSnapshot();
      expect(hardSnap.keys, isNot(contains(RefractoryKeys.soft)));
      expect(hardSnap.keys, isNot(contains(RefractoryKeys.peaks)));

      // Junk stamps read leniently, never throw: only in-range numbers
      // count, and the newest three survive an overflow.
      expect(
        Refractory.read({
          RefractoryKeys.minutes: 10,
          RefractoryKeys.peaks: ['x', 70, 12.0, 99, 5, 1, 0],
        })!.peaks,
        [5, 1, 0],
      );
    });

    test(
      'elapse ages the peaks with the window and drops them at the hour',
      () {
        const soft = Refractory(
          minutes: 10,
          total: 15,
          opened: true,
          soft: true,
          peaks: [40, 10],
        );
        final first = soft.elapse(15, arousal: 70);
        expect(first.refractory, const Refractory(soft: true, peaks: [55, 25]));
        expect(first.arousal, 70, reason: 'a soft window just expires');
        final second = first.refractory.elapse(10, arousal: 70);
        expect(second.refractory.peaks, [
          35,
        ], reason: '65 aged past the hour and dropped; 35 is still counted');
      },
    );
  });

  group('warmth tail (PR 4)', () {
    test('the seed is half the would-be lock, floored 15 and capped 120', () {
      expect(warmthTailMinutes(90, soft: false), 45);
      expect(warmthTailMinutes(240, soft: false), 120, reason: 'cap');
      expect(warmthTailMinutes(20, soft: false), 15, reason: 'floor');
      expect(warmthTailMinutes(0, soft: false), 0, reason: 'no lock, no tail');
      expect(
        warmthTailMinutes(0, soft: true),
        15,
        reason:
            'a soft body always had a window — the floor is the research '
            'baseline, not the lock',
      );
    });

    test('a hard climax seeds its tail frozen beside the lock', () {
      final svc = createTestNsfw();
      svc.setArousalLevel(80);
      svc.applyClimaxEffects(turns: 6, fixedMinutes: 60, tailMinutes: 30);
      expect(svc.arousalLevel, 0, reason: 'hard is still absolute');
      expect(svc.refractoryMinutesRemaining, 60);
      expect(svc.refractoryTailMinutes, 30);
      expect(svc.warmthTailActive, isFalse, reason: 'frozen under the lock');
      expect(svc.refractory.tail?.running, isTrue);
    });

    test('judge 0 on a hard card seeds neither lock nor tail', () {
      final svc = createTestNsfw();
      svc.applyClimaxEffects(turns: 0);
      expect(svc.refractory, Refractory.none);
      expect(svc.refractoryTailMinutes, 0);
    });

    test('a new climax re-seeds the tail; a Continue keeps it', () {
      final svc = createTestNsfw();
      svc.setArousalLevel(90);
      svc.applyClimaxEffects(turns: 6, soft: true, tailMinutes: 45);
      expect(svc.refractoryTailMinutes, 45);

      // Second climax (a new peak): the fresh body takes the NEW seed —
      // one tail at a time, oldest warmth wins nothing.
      svc.applyClimaxEffects(turns: 2, soft: true, tailMinutes: 20);
      expect(svc.refractoryTailMinutes, 20);
      expect(svc.refractoryPeaksLastHour, 2);

      // Continue re-verdict (newPeak false): window restarts, tail holds —
      // it adds no body's worth of anything.
      svc.applyClimaxEffects(
        turns: 9,
        soft: true,
        newPeak: false,
        tailMinutes: 99,
      );
      expect(
        svc.refractoryTailMinutes,
        20,
        reason: 'the Continue carries the existing tail, not the passed seed',
      );
      expect(svc.refractoryMinutesRemaining, kTendernessWindowMinutes);
    });

    test('toSnapshot carries the tail nested and read returns it', () {
      const body = Refractory(
        minutes: 30,
        total: 60,
        opened: true,
        tail: Refractory(minutes: 22, total: 37),
      );
      final snap = body.toSnapshot();
      expect(snap[RefractoryKeys.tail], {
        RefractoryKeys.minutes: 22,
        RefractoryKeys.total: 37,
        RefractoryKeys.opened: false,
      });
      expect(Refractory.read(snap), body);
      // Absent by default: a pre-PR-4 snapshot reads tail-free, and the
      // default hard body stays byte-for-byte what it was.
      expect(
        const Refractory(minutes: 10, total: 10).toSnapshot(),
        isNot(contains(RefractoryKeys.tail)),
      );
      expect(
        Refractory.read({
          RefractoryKeys.minutes: 10,
          RefractoryKeys.total: 10,
        })?.tail,
        isNull,
      );
    });
  });
}
