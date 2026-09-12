// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Generic characters must not be taught as she/her. Unknown/empty Sex
// resolves to they/them; a female Sex field still maps to she/her.
// Proven red: defaultApiSystemPrompt, the intimate-agency line, the
// standing-mood chip, the chargen quirk example, and the needs-eval
// prompt all hardcoded she/her for every character.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/chargen/chargen.dart';
import 'package:front_porch_ai/services/chat/chat.dart';
import 'package:front_porch_ai/services/chat/prompt_injection/preferences_injection.dart';
import 'package:front_porch_ai/services/chat_service.dart';
import 'package:front_porch_ai/services/waifu/waifu.dart';

final _she = RegExp(r'\b(she|her|hers|herself)\b', caseSensitive: false);

void main() {
  group('Sex field → NarrativePronouns', () {
    test('empty, blank, unknown, and they-tokens default to they/them', () {
      for (final sex in ['', '  ', 'android', 'they/them', 'nonbinary']) {
        final p = resolveNarrativePronouns(sex);
        expect(p.subject, 'they', reason: 'sex="$sex"');
        expect(p.object, 'them', reason: 'sex="$sex"');
        expect(p.possessive, 'their', reason: 'sex="$sex"');
      }
    });

    test('female Sex still maps to she/her', () {
      for (final sex in ['Female', 'woman', 'girl', 'she/her', 'she']) {
        expect(
          resolveNarrativePronouns(sex).subject,
          'she',
          reason: 'sex="$sex" must keep she/her',
        );
      }
    });

    test('male Sex still maps to he/him', () {
      expect(resolveNarrativePronouns('Male').subject, 'he');
      expect(resolveNarrativePronouns('man').slashSet, 'he/him/his');
    });
  });

  group('runtime prompts do not default a generic character to she/her', () {
    test('remote system prompt examples use they, not she', () {
      expect(defaultApiSystemPrompt, contains('they clenched their jaw'));
      expect(defaultApiSystemPrompt, contains('"Like this," they said.'));
      expect(
        defaultApiSystemPrompt,
        contains('*They leaned against the doorframe'),
      );
      expect(
        _she.hasMatch(defaultApiSystemPrompt),
        isFalse,
        reason: 'generic writing examples must not teach the model she/her',
      );
    });

    test('intimate-agency injection uses they/them', () {
      final txt = PreferencesInjection(
        getActiveCharacter: () => CharacterCard(
          name: 'Alex',
          frontPorchExtensions: FrontPorchExtensions(
            intimateInto: ['being held down'],
            intimateNotInto: ['an audience'],
          ),
        ),
        getIsGroupNonObserverMode: () => false,
        getCurrentSpeakerIdForRealism: () => '',
        getGroupCharacters: () => const [],
        getCharacterIdFromCard: (c) => c.name,
        getNsfwEnabled: () => true,
        getIntimateAgencyEnabled: () => true,
      ).buildPreferencesInjection();

      expect(txt, contains('theirs to ACT on'));
      expect(txt, contains('in their own register'));
      expect(txt, contains('can raise it themselves'));
      expect(txt, contains('marks their mood'));
      expect(txt, contains('as fits who they are'));
      expect(txt, contains('not the only thing they want'));
      expect(_she.hasMatch(txt), isFalse);
    });

    test('standing-mood chip says not at their best', () {
      final m = deriveMoodBaseline(
        needs: const {'energy': 10},
        timeOfDay: 'afternoon',
      );
      expect(m.summary, 'not at their best — they are exhausted');
      expect(m.summary, isNot(contains('her')));
    });

    test('chargen personality example is they, not she', () {
      final src = File(
        'lib/services/chargen/character_gen_prompts.dart',
      ).readAsStringSync();
      expect(src, contains("people they've just met"));
      expect(src, isNot(contains("people she's just met")));
    });

    test('needs-eval prompt does not charge "her" as the generic body', () {
      final src = File(
        'lib/services/chat/llm_eval_engine.dart',
      ).readAsStringSync();
      expect(src, contains('mentioning their empty stomach'));
      expect(src, contains('COST them'));
      expect(src, contains('their body and mood'));
      expect(src, isNot(contains('her empty stomach')));
      expect(src, isNot(contains('COST her')));
      expect(src, isNot(contains('to her body and mood')));
    });
  });

  group('Waifu Coder copy is they/them, not she/her', () {
    test('slash blurbs never call the coder she', () {
      for (final c in kWaifuSlashCommands) {
        expect(
          _she.hasMatch(c.blurb),
          isFalse,
          reason: '/${c.name}: ${c.blurb}',
        );
      }
    });

    test('doom-loop ask copy uses they', () {
      final why = waifuAskWhy(
        name: 'bash',
        args: const {'command': 'true'},
        doomLoop: true,
      );
      expect(why, startsWith('They already ran'));
      expect(_she.hasMatch(why), isFalse);
    });
  });
}
