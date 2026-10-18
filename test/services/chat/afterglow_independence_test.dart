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

// Afterglow depends on the Realism Engine. Full stop.
//
// THE BUG, as a user hit it: 18+ on, Realism Engine on, Afterglow on — and
// nothing ever happens. Arousal pins at 100 forever. The Porch Life row shows
// the switch live and ungreyed the whole time, because its one declared
// dependency is satisfied.
//
// The cooldown's only trigger is climax detection, and climax detection rode
// the needs-impact eval, which opens
//
//     if (!getNeedsSimEnabled() || !getRealismEnabled()) return;
//
// `CharacterCard.needsSimEnabled` DEFAULTS FALSE, so on most cards that eval
// never ran and Afterglow never started. A dependency nobody declared.
//
// TWO PROPERTIES ARE PINNED HERE, and the second exists because the first
// attempt at this fix got it wrong:
//
//   1. Climax does not route through Needs.
//   2. Climax runs POST-GENERATION. It reads the reply. An earlier draft moved
//      it onto the pre-generation arousal eval, which scores the USER's
//      message — it would have judged a reply that did not exist yet, lagged a
//      turn, re-fired on the same climax still in recent history, and put the
//      pre-gen judge in the business of scoring the character's own words,
//      which the settled rule forbids because a reroll would reroll it.
//      The full unit and golden suites were GREEN on that version. Nothing
//      tested when it ran. That is what the second group is for.

import 'package:flutter_test/flutter_test.dart';

import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/chat/afterglow_pass.dart';
import 'package:front_porch_ai/services/chat/climax_eval.dart';
import 'package:front_porch_ai/services/chat/group_realism_store.dart';
import 'package:front_porch_ai/services/chat/nsfw_service.dart';
import 'package:front_porch_ai/services/chat/realism_scope.dart';
import 'package:front_porch_ai/services/chat/realism_tools.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('the check asks one question, and asks it well', () {
    test('the prompt carries the criteria, not just the question', () {
      final p = ClimaxEval.buildPrompt(
        charName: 'Jennifer',
        reply: 'she shuddered and went limp',
        recentExchange: '',
        toolsMode: false,
      );

      expect(p, contains('CLIMAX DETECTION'));
      expect(
        p,
        contains('are NOT a climax'),
        reason:
            'without explicit criteria a model — especially a reasoning '
            'one — almost never answers true, and the Lust bar stays pinned '
            'at the top forever',
      );
      expect(
        p,
        contains('she shuddered and went limp'),
        reason:
            'it judges the REPLY; a prompt without the reply in it is '
            'judging nothing',
      );
    });

    test('both fields are required in the tool schema', () {
      final params =
          ClimaxEval.tools.single['function']['parameters']
              as Map<String, dynamic>;

      expect(
        params['required'],
        containsAll(['is_climax', 'refractory_turns']),
        reason:
            'optional means never emitted — a model fills in what the '
            'schema demands and skips what it does not, which is how orgasm '
            'detection was silently off on every tools-capable backend once '
            'before',
      );
    });

    test('a true verdict yields the refractory, false yields nothing', () {
      expect(
        ClimaxEval.parseRefractory('{"is_climax":true,"refractory_turns":6}'),
        6,
      );
      expect(
        ClimaxEval.parseRefractory('{"is_climax":false,"refractory_turns":0}'),
        isNull,
      );
    });

    test('a loose backend still gets read correctly', () {
      expect(
        ClimaxEval.parseRefractory(
          '{"is_climax":"true","refractory_turns":"4"}',
        ),
        4,
        reason: 'quoted values are the local-model floor',
      );
      expect(
        ClimaxEval.parseRefractory('{"is_climax":true}'),
        5,
        reason:
            'a missing refractory must not discard a climax that WAS '
            'reported — fall back to the middle of the range',
      );
      expect(
        ClimaxEval.parseRefractory('{"is_climax":true,"refractory_turns":99}'),
        12,
        reason:
            'and it stays clamped — to the widened 0-12 ceiling (the '
            'Afterglow overhaul widened the range on purpose)',
      );
      expect(ClimaxEval.parseRefractory(null), isNull);
      expect(ClimaxEval.parseRefractory('nonsense'), isNull);
    });
  });

  test('the realism tools no longer carry it either', () {
    for (final tool in [
      kEmotionalEvalTools,
      kOneShotEvalTools,
      kNeedsImpactEvalTools,
    ]) {
      final params =
          tool.single['function']['parameters'] as Map<String, dynamic>;
      expect((params['properties'] as Map).containsKey('is_climax'), isFalse);
    }
  });

  // THE PERSONALITY JUDGE (docs/design/afterglow-recovery-overhaul.md PR 1).
  // Every character refracted at ~6 turns because two commits deleted the
  // card's input to the cooldown number: the June consolidation dropped the
  // guidance sentence, the August extraction dropped the personality itself,
  // and the parser's floor turned the judge's "0 — no cooldown" into a
  // 15-minute lock. These guards pin all three restorations.
  group('the judge sees who the character is', () {
    test('the physiology reaches the standalone prompt', () {
      final p = ClimaxEval.buildPrompt(
        charName: 'Vera',
        reply: 'she shuddered and went limp',
        recentExchange: '',
        toolsMode: false,
        physiology: 'insatiable, recovers in minutes',
      );

      expect(p, contains('insatiable, recovers in minutes'));
      expect(
        p,
        contains('use their traits to decide'),
        reason:
            'the guidance sentence is what made the April judge personality-'
            'aware; dropping it in June is half the "everyone refracts ~6" '
            'report',
      );
      expect(p, contains('0 to 12'));
      expect(p, contains('0 is a valid, common answer'));
    });

    test('the rubric is de-anchored — no numeric tilt toward a long lock', () {
      final p = ClimaxEval.rubric('Vera');
      expect(p, isNot(contains('3 to 7')));
      expect(p, isNot(contains('~6-7')));
      expect(p, isNot(contains('~3 for')));
    });

    test('an empty physiology omits the traits line', () {
      final p = ClimaxEval.rubric('Vera');
      expect(p, isNot(contains('Who Vera is')));
      expect(ClimaxEval.rubric('Vera', ''), ClimaxEval.rubric('Vera'));
    });

    test('a 0 verdict survives the parser', () {
      expect(
        ClimaxEval.parseRefractory('{"is_climax":true,"refractory_turns":0}'),
        0,
        reason:
            'the old clamp(1, 10) silently turned "no cooldown needed" into '
            'a 15-minute lock — no refractory was inexpressible',
      );
    });

    group('physiologyFor reads the card in the agreed order', () {
      CharacterCard card({
        String personality = '',
        String description = '',
        List<String> into = const [],
        List<String> notInto = const [],
      }) => CharacterCard(
        name: 'Vera',
        personality: personality,
        description: description,
        frontPorchExtensions: FrontPorchExtensions(
          intimateInto: into,
          intimateNotInto: notInto,
        ),
      );

      test('intimate preferences first, then personality', () {
        final p = ClimaxEval.physiologyFor(
          card(
            personality: 'insatiable, recovers in minutes',
            into: const ['long slow mornings'],
            notInto: const ['being rushed'],
          ),
        );
        expect(
          p.indexOf('Into: long slow mornings'),
          lessThan(p.indexOf('insatiable')),
          reason: 'authored intimate preferences are the sharper signal',
        );
        expect(p, contains('Not into: being rushed'));
      });

      test('a blank personality falls back to the description', () {
        final p = ClimaxEval.physiologyFor(
          card(description: 'a reserved clockmaker'),
        );
        expect(p, contains('a reserved clockmaker'));
      });

      test('the slot is capped at 600 chars', () {
        final p = ClimaxEval.physiologyFor(card(personality: 'x' * 900));
        expect(p.length, 600);
      });

      test('nothing authored yields nothing', () {
        expect(ClimaxEval.physiologyFor(card()), isEmpty);
        expect(ClimaxEval.physiologyFor(null), isEmpty);
      });
    });

    test('a group judges the reply speaker, never another member', () async {
      final groupMap = <String, Map<String, dynamic>>{};
      final nsfw = NsfwService(
        getGroupInt: (id, key) => (groupMap[id]?[key] as num?)?.toInt() ?? 0,
        getGroupValue: (id, key) => groupMap[id]?[key],
        setGroupValue: (id, key, v) {
          (groupMap[id] ??= {})[key] = v;
        },
      );
      nsfw.loadNsfwScalars(arousalLevel: 80, nsfwCooldownEnabled: true);

      // Ada leads the roster; Vera spoke this turn. Post-gen has already
      // made the active character the speaker — the pass must read HER card.
      final ada = CharacterCard(
        name: 'Ada',
        personality: 'reserved, allergic to spontaneity',
      )..dbId = 'ada';
      final vera = CharacterCard(
        name: 'Vera',
        personality: 'insatiable, recovers in minutes',
        frontPorchExtensions: FrontPorchExtensions(
          intimateInto: const ['long slow mornings'],
        ),
      )..dbId = 'vera';

      var prompt = '';
      final eval = ClimaxEval(
        fire:
            ({
              required debugLabel,
              required tools,
              required buildPrompt,
            }) async {
              prompt = buildPrompt(toolsMode: false);
              return '{"is_climax":true,"refractory_turns":2}';
            },
      );
      final messages = [
        ChatMessage(
          text: 'she shuddered and went limp',
          sender: 'Vera',
          isUser: false,
        ),
      ];
      final scope = RealismScope(
        messages: messages,
        activeCharacter: () => vera,
        setActiveCharacter: (_) {},
        activeGroup: () => GroupChat(id: 'g1', name: 'The porch'),
        groupCharacters: () => [ada, vera],
        observerMode: () => false,
        realismEnabled: () => true,
        needsSimEnabled: () => false,
        realismSettings: () => throw UnimplementedError(),
        clockRunning: () => false,
        characterIdFor: (c) => c.dbId ?? '',
        groups: GroupRealismStore(
          isGroup: () => true,
          groupCharacters: () => [ada, vera],
          characterIdFor: (c) => c.dbId ?? '',
          hostId: () => 'g1',
          activeCharacter: () => vera,
          isGenerating: () => false,
          nextCharacter: () => null,
          workFieldsFor: (_) => throw UnimplementedError(),
        ),
        needs: () => throw UnimplementedError(),
        relationship: () => throw UnimplementedError(),
        nsfw: () => nsfw,
        time: () => throw UnimplementedError(),
        pending: () => null,
        setPending: (_) {},
        emotion: () => '',
        setEmotion: (_) {},
        intensity: () => '',
        setIntensity: (_) {},
        cause: () => '',
        setCause: (_) {},
        heldTurns: () => 0,
        setHeldTurns: (_) {},
        saveChat: () async {},
        notify: () {},
      );
      final pass = AfterglowPass(
        scope,
        eval,
        fusedReply: () => null,
        isGuestAuthoredMessage: (_) => false,
        resolveGroupSpeakerForMessage: (_) => null,
      );

      await pass.runClimaxPass('she shuddered and went limp');

      expect(prompt, contains('about Vera'));
      expect(
        prompt,
        contains('insatiable, recovers in minutes'),
        reason: 'the judge must see the SPEAKER\'s traits',
      );
      expect(prompt, contains('Into: long slow mornings'));
      expect(
        prompt,
        isNot(contains('allergic to spontaneity')),
        reason:
            'the nsfw_injection group contract: never the previous '
            'speaker\'s card — that is how one body gets another\'s cooldown',
      );
      expect(nsfw.refractoryMinutesRemaining, 30);
    });
  });
}
