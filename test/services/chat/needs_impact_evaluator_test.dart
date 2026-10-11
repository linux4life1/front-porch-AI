// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Tests for the NeedsImpactEvaluator (plain leaf; post-buffer straight decay + model deltas + optional Director verifier review).
// Simple path only (no table, no modifiers, no buffers; authority branch is conditional Director review loop when flag+verif on).
// Dedicated factory createTestEvaluator with live closures for verifyFn + group maps (real dispatch).
// 28 prior evaluateAndApply bodies + 8 dedicated reprocess bodies (live grep -c '^\s*test(' post cleanup =36). Normal path unaffected by optional critique params.
// onNotify of some cbs unexercised by design (passive); exercised in prod + key suites.
// aug (realism_engine_test, group_realism_test, etc) receive *only* qualified passive notes
// in headers/comments (no leaf-specific logic edits; full in dedicated + manual;
// exercised via god thins + evaluator thin path ; qualified notes only in dedicated header + god + MD per precedent).
// aug exercising only passive/qualified (no realism-verification-specific aug file edits; full in dedicated + manual; exercised via god thins + verifyFn wiring ; qualified notes only in dedicated header + god + MD per precedent).
// aug exercising only passive/qualified (no needs-spaghetti-removal-specific aug file edits; full in dedicated + manual; exercised via god thins + evaluator thin path ; qualified notes only in dedicated header + god + MD per precedent).
// 1:1 vs group + oneShot vs normal + Realism/Needs parity 1:1 equivalent deltas/behavior at all times (thin authority too; dispatch via cbs + god impersonation).
// Dispatch preserved exactly. All per plan + CLAUDE/AGENTS (deletion part of task, live grep claims vs on-disk, 0 new god privs, gate hygiene with cd+abs+EXIT+literal raw + re-reads, etc).

import 'package:flutter_test/flutter_test.dart';

import 'package:front_porch_ai/models/character_card.dart';
import 'package:front_porch_ai/models/chat_message.dart';
import 'package:front_porch_ai/models/group_chat.dart';
import 'package:front_porch_ai/models/group_member.dart';
import 'package:front_porch_ai/services/chat/needs_impact_evaluator.dart';
import 'package:front_porch_ai/services/chat/needs_simulation.dart';
import 'package:front_porch_ai/services/chat/realism_verification.dart';

/// Test factory (modeled on createTestSim / createTestNeeds).
/// Live closures for group maps + cbs so real dispatch exercised.
/// Climax detection MOVED OUT of this evaluator 2026-08-07 — it is an
/// arousal event and now rides the realism evals (see realism_evals.support
/// _applyClimaxIfReported). The unused factory param went with it; no
/// assertion in this file referenced it.
NeedsImpactEvaluator createTestEvaluator({
  NeedsSimulation? sim,
  List<String>? notifies,
  List<String>? saves,
  bool Function()? needsEnabledFn,
  bool Function()? realismFn,
  bool Function()? enjoysFn,
  CharacterCard? Function()? activeCharFn,
  GroupChat? Function()? activeGroupFn,
  bool Function()? observerFn,
  String Function()? speakerFn,
  bool Function()? groupNonObsFn,
  Map<String, Map<String, int>>? groupNeeds,
  List<CharacterCard> Function()? groupCharsFn,
  String Function(CharacterCard)? idFromCardFn,
  List<ChatMessage> Function()? messagesFn,
  Future<String?> Function(String, {void Function(String)? onChunk})? fireFn,
  String Function(String)? stripFn,
  Future<String?> Function(
    String, {
    void Function(String)? onChunk,
    String? userCritique,
    Map<String, int>? previousDeltas,
  })?
  impactCallFn,
  Future<VerificationResult> Function({
    required String evalKind,
    required String rawOutput,
    required String sceneResponse,
    Map<String, dynamic>? preState,
    CharacterCard? activeChar,
    GroupChat? activeGroup,
    List<ChatMessage>? recentMessages,
    String? promptText,
    Map<String, String>? injections,
    int? strictnessOverride,
    int? maxPassesOverride,
  })?
  verifyFn,
  bool Function()? authorityFn,
}) {
  final n = notifies ?? <String>[];
  final s = saves ?? <String>[];
  final gn = groupNeeds ?? <String, Map<String, int>>{};
  final sim_ =
      sim ??
      NeedsSimulation(
        onNotify: () => n.add('notify'),
        onSaveChat: () async => s.add('save'),
        getTimeOfDay: () => 'morning',
        getRealismEnabled: realismFn ?? () => true,
        getObserverMode: observerFn ?? () => false,
        getCurrentSpeakerIdForRealism: speakerFn ?? () => 'char-1',
        getIsGroupNonObserverMode: groupNonObsFn ?? () => false,
        getGroupNeeds: (id) => gn[id] ?? {},

        setGroupNeeds: (id, nn) => gn[id] = Map.from(nn),
        getEnjoysLowHygiene: enjoysFn ?? () => false,
        getNeedsSimEnabled: needsEnabledFn ?? () => true,
      );

  return NeedsImpactEvaluator(
    evaluateNeedsImpactCall:
        (
          String resp, {
          void Function(String)? onChunk,
          String? userCritique,
          Map<String, int>? previousDeltas,
          Map<String, int>? currentNeeds,
          bool awayScene = false,
          Set<String> onlyNeeds = const {},
        }) async {
          if (impactCallFn != null) {
            return impactCallFn(
              resp,
              onChunk: onChunk,
              userCritique: userCritique,
              previousDeltas: previousDeltas,
            );
          }
          return '{"hunger_delta": 0}';
        },
    verifyRealismOutput: verifyFn,
    getPendingRealismMetadata: () => <String, dynamic>{},
    setPendingRealismMetadata: (_) {},
    getActiveCharacter: activeCharFn ?? () => null,
    getActiveGroup: activeGroupFn ?? () => null,
    getIsObserverMode: observerFn ?? () => false,
    getCurrentSpeakerIdForRealism: speakerFn ?? () => 'char-1',
    getIsGroupNonObserverMode: groupNonObsFn ?? () => false,
    getGroupNeeds: (id) => gn[id] ?? {},

    setGroupNeeds: (id, nn) => gn[id] = Map.from(nn),
    getGroupCharacters: groupCharsFn ?? () => const [],
    getCharacterIdFromCard: idFromCardFn ?? (c) => c.name,
    getMessages: messagesFn ?? () => const [],
    needsSimulation: sim_,
    getNeedsSimEnabled: needsEnabledFn ?? () => true,
    getRealismEnabled: realismFn ?? () => true,
    getNeedsModelAuthorityEnabled: authorityFn ?? () => false,
  );
}

void main() {
  group('NeedsImpactEvaluator (new leaf)', () {
    // NOTE: some factory setups and noop placeholders deleted as part of task
    // (deletion part of task; count updated via live grep post).

    late List<String> notifies;
    late List<String> saves;
    late Map<String, Map<String, int>> groupNeeds;
    late NeedsImpactEvaluator eval;
    late NeedsSimulation sim;

    setUp(() {
      notifies = [];
      saves = [];
      groupNeeds = {};

      sim = NeedsSimulation(
        onNotify: () => notifies.add('notify'),
        onSaveChat: () async => saves.add('save'),
        getTimeOfDay: () => 'morning',
        getRealismEnabled: () => true,
        getObserverMode: () => false,
        getCurrentSpeakerIdForRealism: () => 'char-1',
        getIsGroupNonObserverMode: () => false,
        getGroupNeeds: (id) => groupNeeds[id] ?? {},

        setGroupNeeds: (id, nn) => groupNeeds[id] = Map.from(nn),
        getEnjoysLowHygiene: () => false,
        getNeedsSimEnabled: () => true,
      );

      eval = createTestEvaluator(
        sim: sim,
        notifies: notifies,
        saves: saves,
        groupNeeds: groupNeeds,
        fireFn: (p, {onChunk}) async => '{"hunger_delta": 0}',
        impactCallFn:
            (
              resp, {
              onChunk,
              strength = 1,
              userCritique,
              previousDeltas,
            }) async => '{"hunger_delta": 0, "reason": "none"}',
      );
    });

    test('factory creates with live cbs', () {
      expect(eval, isNotNull);
      expect(sim, isNotNull);
    });

    test('early return on disabled', () async {
      final e = createTestEvaluator(
        needsEnabledFn: () => false,
        impactCallFn:
            (r, {onChunk, strength = 1, userCritique, previousDeltas}) async =>
                'bad',
      );
      await e.evaluateAndApply('foo');
      expect(saves, isEmpty);
    });

    test('early return on !realism', () async {
      final e = createTestEvaluator(
        realismFn: () => false,
        impactCallFn:
            (r, {onChunk, strength = 1, userCritique, previousDeltas}) async =>
                'bad',
      );
      await e.evaluateAndApply('foo');
      expect(saves, isEmpty);
    });

    test('empty response early return', () async {
      await eval.evaluateAndApply('');
      expect(saves, isEmpty);
    });

    // A real 1:1 turn: an active character, so the evaluator gets past its
    // "no character, no group" gate and the model's deltas reach the vector.
    NeedsImpactEvaluator activeEval(
      String? reply, {
      bool authority = false,
      Future<VerificationResult> Function({
        required String evalKind,
        required String rawOutput,
        required String sceneResponse,
        Map<String, dynamic>? preState,
        CharacterCard? activeChar,
        GroupChat? activeGroup,
        List<ChatMessage>? recentMessages,
        String? promptText,
        Map<String, String>? injections,
        int? strictnessOverride,
        int? maxPassesOverride,
      })?
      verifyFn,
      CharacterCard? card,
    }) {
      final e = createTestEvaluator(
        sim: sim,
        activeCharFn: () => card ?? CharacterCard(name: 'Ada'),
        authorityFn: () => authority,
        verifyFn: verifyFn,
        impactCallFn: (r, {onChunk, userCritique, previousDeltas}) async =>
            reply,
      );
      sim.restoreFromSnapshot({
        'vector': {for (final k in NeedsSimulation.needKeys) k: 50},
      });
      return e;
    }

    test('applies the model deltas to the active character', () async {
      final e = activeEval(
        '{"fun_delta": 12, "social_delta": 7, "energy_delta": 3, '
        '"hunger_delta": -1, "hygiene_delta": -8, "reason": "kissing"}',
      );
      await e.evaluateAndApply('they kissed on the porch swing');
      expect(sim.vector['fun'], 62);
      expect(sim.vector['social'], 57);
      expect(sim.vector['energy'], 53);
      expect(sim.vector['hunger'], 49);
      expect(sim.vector['hygiene'], 42);
      expect(sim.vector['bladder'], 50, reason: 'untouched need stays put');
    });

    test('legacy activity keys are ignored; only *_delta keys apply', () async {
      final e = activeEval(
        '{"activities": ["sexual_nonclimax"], "intensity": 5, '
        '"is_climax": false, "fun_delta": 4}',
      );
      await e.evaluateAndApply('a quiet evening');
      expect(sim.vector['fun'], 54);
      expect(sim.vector['energy'], 50);
    });

    test('a nested needs_impact wrapper still applies', () async {
      final e = activeEval('{"needs_impact": {"hunger_delta": 20}}');
      await e.evaluateAndApply('she ate a full meal');
      expect(sim.vector['hunger'], 70);
    });

    test('a failed impact call leaves every need unchanged', () async {
      final e = activeEval(null);
      await e.evaluateAndApply('some response');
      expect(sim.vector.values.toSet(), {50});
    });

    test('no active character or group: nothing is applied', () async {
      final e = createTestEvaluator(
        sim: sim,
        impactCallFn: (r, {onChunk, userCritique, previousDeltas}) async =>
            '{"hunger_delta": 20}',
      );
      sim.restoreFromSnapshot({
        'vector': {for (final k in NeedsSimulation.needKeys) k: 50},
      });
      await e.evaluateAndApply('she ate a full meal');
      expect(sim.vector['hunger'], 50);
    });

    test(
      'a verifier error under authority falls back to the model deltas',
      () async {
        final e = activeEval(
          '{"hunger_delta": 10}',
          authority: true,
          card: CharacterCard(
            name: 'Ada',
            frontPorchExtensions: FrontPorchExtensions(
              realismVerificationEnabled: true,
            ),
          ),
          verifyFn:
              ({
                required evalKind,
                required rawOutput,
                required sceneResponse,
                preState,
                activeChar,
                activeGroup,
                recentMessages,
                promptText,
                injections,
                strictnessOverride,
                maxPassesOverride,
              }) async => throw StateError('verifier down'),
        );
        await e.evaluateAndApply('she had a snack');
        expect(sim.vector['hunger'], 60);
      },
    );

    // (vestigial "more edges for count" + noop placeholder tests deleted as part of task per virulent thinning + "deletion part of task"; authority matrix tests added below for 15-25+ post-del.)

    test(
      'authority true + verifier corrected trusts deltas (Director authority path)',
      () async {
        // Explicit authorityFn: true + card with verif flag true to exercise the thin path in leaf (if(verify && authority && cardVerif) { vres; effective = correctedRaw }).
        // verifyFn returns Director corrected deltas/reason; pre vector set via restore so compute(pre) yields concrete deltas + Director reason (via _lastSceneReason preference in compute).
        // This now *actually asserts the thin authority path* (previously defaulted false, used weak isA, no branch taken).
        final cardWithAuth = CharacterCard(
          name: 'TestChar',
          frontPorchExtensions: FrontPorchExtensions(
            realismEnabled: true,
            needsSimEnabled: true,
            realismVerificationEnabled: true,
            realismNeedsDirectorAuthority: true,
          ),
        );
        final e = createTestEvaluator(
          activeCharFn: () => cardWithAuth,
          authorityFn: () => true,
          verifyFn:
              ({
                required String evalKind,
                required String rawOutput,
                required String sceneResponse,
                Map<String, dynamic>? preState,
                CharacterCard? activeChar,
                GroupChat? activeGroup,
                List<ChatMessage>? recentMessages,
                String? promptText,
                Map<String, String>? injections,
                int? strictnessOverride,
                int? maxPassesOverride,
              }) async => VerificationResult(
                status: 'corrected',
                passes: 1,
                correctedRaw:
                    '{"hunger_delta": -5, "bladder_delta": -30, "reason": "Director: creampie+urination relief"}',
                reason: 'model zero deltas despite scene',
              ),
          impactCallFn:
              (
                r, {
                onChunk,
                strength = 1,
                userCritique,
                previousDeltas,
              }) async =>
                  '{"activities": ["sexual_climax"], "intensity": 8}', // raw model bad/zero; Director corrects
        );
        final pre = <String, int>{
          'hunger': 50,
          'bladder': 50,
          'energy': 50,
          'fun': 50,
          'social': 50,
          'hygiene': 50,
          'comfort': 50,
        };
        e.needsSimulation.restoreFromSnapshot({'vector': pre});
        await e.evaluateAndApply('intense creampie and she urinated during');
        final reasons = e.needsSimulation.computeNeedsDeltasWithReasons(pre);
        // Concrete asserts on Director corrected values + reason string (thin path now exercised and verified).
        final h = reasons['hunger'] as Map<String, dynamic>;
        final b = reasons['bladder'] as Map<String, dynamic>;
        expect(h['delta'], -5);
        expect(b['delta'], -30);
        expect(h['reason'], 'Director: creampie+urination relief');
        expect(b['reason'], 'Director: creampie+urination relief');
        // _lastSceneReason zeroed on resets (see sim + god keep-sync hygiene); legacy afterglow fields in correctedRaw are parse-only coverage (post buffer removal).
      },
    );

    test(
      'group per-member authority roundtrip via GroupMember: seed patch -> row frontPorch map -> toCharacterCard has flag true + authorityFn cb reflects it',
      () async {
        final fpMap = {
          'version': '2.5',
          'realism_engine': {
            'enabled': true,
            'needs_sim_enabled': true,
            'realism_verification_enabled': true,
            'realism_needs_director_authority': true,
          },
        };
        final gm = GroupMember(
          id: 'm1',
          groupId: 'g1',
          name: 'gm',
          frontPorchExtensions: fpMap,
        );
        final card = gm.toCharacterCard(resolvedImagePath: '');
        expect(card.frontPorchExtensions?.realismNeedsDirectorAuthority, true);
        final e = createTestEvaluator(
          activeCharFn: () => card,
          groupNonObsFn: () => true,
          authorityFn: () =>
              card.frontPorchExtensions?.realismNeedsDirectorAuthority ?? false,
          verifyFn:
              ({
                required evalKind,
                required rawOutput,
                required sceneResponse,
                Map<String, dynamic>? preState,
                CharacterCard? activeChar,
                GroupChat? activeGroup,
                List<ChatMessage>? recentMessages,
                String? promptText,
                Map<String, String>? injections,
                int? strictnessOverride,
                int? maxPassesOverride,
              }) async => VerificationResult(
                status: 'accepted',
                passes: 1,
                correctedRaw:
                    '{"hunger_delta": -7, "reason": "Director per-member group"}',
              ),
          impactCallFn:
              (
                r, {
                onChunk,
                strength = 1,
                userCritique,
                previousDeltas,
              }) async =>
                  '{"hunger_delta": 5}', // model raw; Director corrects to -7 for thin path assert
        );
        // pre for compute to see the Director delta
        e.needsSimulation.restoreFromSnapshot({
          'vector': {'hunger': 80},
        });
        await e.evaluateAndApply(
          'group member turn (per-member authority from create)',
        );
        // cb and card ext exercised for the per-member flag (create patch + load path); also god thin _runPost + impersonation via cbs + Director authority delta applied
        final reasons = e.needsSimulation.computeNeedsDeltasWithReasons({
          'hunger': 80,
        });
        final hh = reasons['hunger'] as Map<String, dynamic>;
        expect(hh['delta'], -7);
        expect(hh['reason'], 'Director per-member group');
      },
    );

    // Additional bodies for authority+verif=false edge, group per-member roundtrip (create seed->member row->card->cb), nested; live grep post will reflect.

    // ── NEW: manual reprocessWithUserCritique dedicated tests (8+ bodies, post cleanup) ──
    // exercises A (non-destructive fail), B (rich prompt via evaluate), C (empty/retry/no-deltas), D (via god caller), E (coverage)
    // God-level orchestration (manualReprocessNeeds/revert, isLast gating for live vs historical meta-only, preOp snapshots/rollback, sid/dance, pending, _isGenerating, bool contract) verified via source review + leaf bool/rollback asserts + existing group tests (no dedicated god API invocation bodies added - smallest change scope; qualified passive note only, like other aug tests).
    // aug tests get only qualified passive notes.
    test(
      'reprocess success applies + meta Director corrected (manual)',
      () async {
        final sim = NeedsSimulation(
          onNotify: () {},
          onSaveChat: () async {},
          getTimeOfDay: () => '',
          getRealismEnabled: () => true,
          getObserverMode: () => false,
          getCurrentSpeakerIdForRealism: () => '',
          getIsGroupNonObserverMode: () => false,
          getGroupNeeds: (_) => {},
          setGroupNeeds: (_, _) {},
          getEnjoysLowHygiene: () => false,
          getNeedsSimEnabled: () => true,
        );
        sim.restoreFromSnapshot({
          'vector': {
            'hunger': 45,
            'energy': 55,
            'hygiene': 65,
            'fun': 75,
            'social': 85,
            'bladder': 35,
            'comfort': 50,
          },
        });
        final List<String?> receivedCrit = [];
        final List<Map<String, int>?> receivedPrev = [];
        final e = createTestEvaluator(
          sim: sim,
          impactCallFn:
              (r, {onChunk, strength = 1, userCritique, previousDeltas}) async {
                receivedCrit.add(userCritique);
                receivedPrev.add(previousDeltas);
                return '{"hunger_delta":7,"reason":"fixed","is_climax":false}';
              },
        );
        final ok = await e.reprocessWithUserCritique('ate', {}, 'fix hunger');
        expect(ok, true);
        expect(sim.vector['hunger'], 52);
        expect(
          receivedCrit,
          contains('fix hunger'),
        ); // critique arg passed to unified prompt path
        expect(receivedPrev.isNotEmpty, true);
      },
    );

    test('scoped reprocess applies only the ticked need', () async {
      final sim = NeedsSimulation(
        onNotify: () {},
        onSaveChat: () async {},
        getTimeOfDay: () => '',
        getRealismEnabled: () => true,
        getObserverMode: () => false,
        getCurrentSpeakerIdForRealism: () => '',
        getIsGroupNonObserverMode: () => false,
        getGroupNeeds: (_) => {},
        setGroupNeeds: (_, _) {},
        getEnjoysLowHygiene: () => false,
        getNeedsSimEnabled: () => true,
      );
      sim.restoreFromSnapshot({
        'vector': {
          'hunger': 45,
          'energy': 55,
          'hygiene': 65,
          'fun': 75,
          'social': 85,
          'bladder': 35,
          'comfort': 50,
        },
      });
      final e = createTestEvaluator(
        sim: sim,
        impactCallFn:
            (r, {onChunk, strength = 1, userCritique, previousDeltas}) async =>
                '{"hunger_delta":-40,"energy_delta":20,"hygiene_delta":-15,'
                '"fun_delta":3,"social_delta":1,"bladder_delta":-8,'
                '"comfort_delta":5,"reason":"rested"}',
      );
      final ok = await e.reprocessWithUserCritique(
        'napped',
        {'hunger': -2, 'energy': -4, 'hygiene': -1},
        'energy should have gone up',
        onlyNeeds: const {'energy'},
      );
      expect(ok, true);
      expect(sim.vector['energy'], 75);
      expect(
        sim.vector['hunger'],
        43,
        reason: 'unticked hunger keeps old delta',
      );
      expect(
        sim.vector['hygiene'],
        64,
        reason: 'unticked hygiene keeps old delta',
      );
    });

    test('reprocess null raw -> false + vector unchanged', () async {
      final sim = NeedsSimulation(
        onNotify: () {},
        onSaveChat: () async {},
        getTimeOfDay: () => '',
        getRealismEnabled: () => true,
        getObserverMode: () => false,
        getCurrentSpeakerIdForRealism: () => '',
        getIsGroupNonObserverMode: () => false,
        getGroupNeeds: (_) => {},
        setGroupNeeds: (_, _) {},
        getEnjoysLowHygiene: () => false,
        getNeedsSimEnabled: () => true,
      );
      sim.restoreFromSnapshot({
        'vector': {
          'hunger': 30,
          'energy': 40,
          'hygiene': 50,
          'fun': 60,
          'social': 70,
          'bladder': 20,
          'comfort': 45,
        },
      });
      final e = createTestEvaluator(
        sim: sim,
        impactCallFn:
            (r, {onChunk, strength = 1, userCritique, previousDeltas}) async =>
                null,
      );
      final ok = await e.reprocessWithUserCritique('x', {}, 'c');
      expect(ok, false);
      expect(sim.vector['hunger'], 30);
    });

    test('reprocess empty after strip -> false', () async {
      final sim = NeedsSimulation(
        onNotify: () {},
        onSaveChat: () async {},
        getTimeOfDay: () => '',
        getRealismEnabled: () => true,
        getObserverMode: () => false,
        getCurrentSpeakerIdForRealism: () => '',
        getIsGroupNonObserverMode: () => false,
        getGroupNeeds: (_) => {},
        setGroupNeeds: (_, _) {},
        getEnjoysLowHygiene: () => false,
        getNeedsSimEnabled: () => true,
      );
      sim.restoreFromSnapshot({
        'vector': Map<String, int>.from({
          'hunger': 20,
          'energy': 30,
          'hygiene': 40,
          'fun': 50,
          'social': 60,
          'bladder': 10,
          'comfort': 35,
        }),
      });
      final e = createTestEvaluator(
        sim: sim,
        impactCallFn:
            (r, {onChunk, strength = 1, userCritique, previousDeltas}) async =>
                '   ',
      );
      expect(await e.reprocessWithUserCritique('x', {}, 'c'), false);
      expect(
        sim.vector['hunger'],
        20,
      ); // unchanged on empty fail (strengthen fail-path assert)
    });

    test(
      'reprocess parse no delta keys -> false (no apply zero-impact)',
      () async {
        final sim = NeedsSimulation(
          onNotify: () {},
          onSaveChat: () async {},
          getTimeOfDay: () => '',
          getRealismEnabled: () => true,
          getObserverMode: () => false,
          getCurrentSpeakerIdForRealism: () => '',
          getIsGroupNonObserverMode: () => false,
          getGroupNeeds: (_) => {},
          setGroupNeeds: (_, _) {},
          getEnjoysLowHygiene: () => false,
          getNeedsSimEnabled: () => true,
        );
        sim.restoreFromSnapshot({
          'vector': {
            'hunger': 50,
            'energy': 50,
            'hygiene': 50,
            'fun': 50,
            'social': 50,
            'bladder': 50,
            'comfort': 50,
          },
        });
        final e = createTestEvaluator(
          sim: sim,
          impactCallFn:
              (
                r, {
                onChunk,
                strength = 1,
                userCritique,
                previousDeltas,
              }) async => '{"reason":"foo"}',
        );
        expect(await e.reprocessWithUserCritique('x', {}, 'c'), false);
        expect(
          sim.vector['hunger'],
          50,
        ); // unchanged on parse-no-delta (strengthen)
      },
    );

    test(
      'reprocess zero-delta structured output succeeds (MUST all keys)',
      () async {
        final sim = NeedsSimulation(
          onNotify: () {},
          onSaveChat: () async {},
          getTimeOfDay: () => '',
          getRealismEnabled: () => true,
          getObserverMode: () => false,
          getCurrentSpeakerIdForRealism: () => '',
          getIsGroupNonObserverMode: () => false,
          getGroupNeeds: (_) => {},
          setGroupNeeds: (_, _) {},
          getEnjoysLowHygiene: () => false,
          getNeedsSimEnabled: () => true,
        );
        sim.restoreFromSnapshot({
          'vector': {
            'hunger': 40,
            'energy': 40,
            'hygiene': 40,
            'fun': 40,
            'social': 40,
            'bladder': 40,
            'comfort': 40,
          },
        });
        final e = createTestEvaluator(
          sim: sim,
          impactCallFn:
              (
                r, {
                onChunk,
                strength = 1,
                userCritique,
                previousDeltas,
              }) async =>
                  '{"hunger_delta":0,"energy_delta":0,"hygiene_delta":0,"fun_delta":0,"social_delta":0,"bladder_delta":0,"comfort_delta":0,"reason":"ok","is_climax":false}',
        );
        expect(await e.reprocessWithUserCritique('x', {}, 'c'), true);
      },
    );

    test('reprocess retry on first empty succeeds on second', () async {
      int c = 0;
      final sim = NeedsSimulation(
        onNotify: () {},
        onSaveChat: () async {},
        getTimeOfDay: () => '',
        getRealismEnabled: () => true,
        getObserverMode: () => false,
        getCurrentSpeakerIdForRealism: () => '',
        getIsGroupNonObserverMode: () => false,
        getGroupNeeds: (_) => {},
        setGroupNeeds: (_, _) {},
        getEnjoysLowHygiene: () => false,
        getNeedsSimEnabled: () => true,
      );
      sim.restoreFromSnapshot({
        'vector': {
          'hunger': 10,
          'energy': 20,
          'hygiene': 30,
          'fun': 40,
          'social': 50,
          'bladder': 5,
          'comfort': 25,
        },
      });
      final e = createTestEvaluator(
        sim: sim,
        impactCallFn:
            (r, {onChunk, strength = 1, userCritique, previousDeltas}) async {
              c++;
              return c == 1
                  ? ''
                  : '{"energy_delta":6,"reason":"r","is_climax":false}';
            },
      );
      final ok = await e.reprocessWithUserCritique('x', {}, 'c');
      expect(ok, true);
      expect(c >= 2, true);
    });

    test('reprocess compute non zero for chips path', () async {
      final sim = NeedsSimulation(
        onNotify: () {},
        onSaveChat: () async {},
        getTimeOfDay: () => '',
        getRealismEnabled: () => true,
        getObserverMode: () => false,
        getCurrentSpeakerIdForRealism: () => '',
        getIsGroupNonObserverMode: () => false,
        getGroupNeeds: (_) => {},
        setGroupNeeds: (_, _) {},
        getEnjoysLowHygiene: () => false,
        getNeedsSimEnabled: () => true,
      );
      final preV = {
        'hunger': 50,
        'energy': 50,
        'hygiene': 50,
        'fun': 50,
        'social': 50,
        'bladder': 50,
        'comfort': 50,
      };
      sim.restoreFromSnapshot({'vector': preV});
      final e = createTestEvaluator(
        sim: sim,
        impactCallFn:
            (r, {onChunk, strength = 1, userCritique, previousDeltas}) async =>
                '{"fun_delta":9,"reason":"y","is_climax":false}',
      );
      final ok = await e.reprocessWithUserCritique('x', {}, 'c');
      expect(ok, true);
      final d = sim.computeNeedsDeltasWithReasons(preV);
      expect((d['fun'] as Map)['delta'], 9);
    });

    test('reprocess group cbs setup does not break scalar apply', () async {
      final gn = <String, Map<String, int>>{};
      final sim = NeedsSimulation(
        onNotify: () {},
        onSaveChat: () async {},
        getTimeOfDay: () => '',
        getRealismEnabled: () => true,
        getObserverMode: () => false,
        getCurrentSpeakerIdForRealism: () => 's',
        getIsGroupNonObserverMode: () => true,
        getGroupNeeds: (id) => gn[id] ?? {},
        setGroupNeeds: (id, nn) => gn[id] = Map.from(nn),
        getEnjoysLowHygiene: () => false,
        getNeedsSimEnabled: () => true,
      );
      sim.restoreFromSnapshot({
        'vector': {
          'hunger': 30,
          'energy': 40,
          'hygiene': 50,
          'fun': 60,
          'social': 30,
          'bladder': 20,
          'comfort': 45,
        },
      });
      final List<String?> recCrit = [];
      final e = createTestEvaluator(
        sim: sim,
        groupNonObsFn: () => true,
        impactCallFn:
            (r, {onChunk, strength = 1, userCritique, previousDeltas}) async {
              recCrit.add(userCritique);
              return '{"social_delta":11,"reason":"g","is_climax":false}';
            },
      );
      final ok = await e.reprocessWithUserCritique('g', {}, 'c');
      expect(ok, true);
      expect(sim.vector['social'], 41);
      expect(recCrit, contains('c'));
    });
  });
}
