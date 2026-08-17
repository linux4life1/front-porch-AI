// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Prompt-construction pins for chargen perspective + tense (issue #194).
// The greeting / example-dialog builders used to hard-lock first-person
// present. These tests cover the four combinations and third-person
// pronoun resolution from the Sex field. A recording-LLM test below
// pins the generateCharacter call site so deleting the wiring still
// goes red.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/chargen/chargen.dart';
import 'package:front_porch_ai/services/character_gen_service.dart';
import 'package:front_porch_ai/services/llm_service.dart';

void main() {
  group('resolveNarrativePronouns', () {
    test('female tokens resolve to she/her', () {
      expect(resolveNarrativePronouns('Female').subject, 'she');
      expect(resolveNarrativePronouns('woman').slashSet, 'she/her/her');
      expect(resolveNarrativePronouns('she/her').subject, 'she');
    });

    test('male tokens resolve to he/him', () {
      expect(resolveNarrativePronouns('Male').subject, 'he');
      expect(resolveNarrativePronouns('man').slashSet, 'he/him/his');
      expect(resolveNarrativePronouns('he/him').subject, 'he');
    });

    test('blank, they/them, and unknown fall back to they', () {
      expect(resolveNarrativePronouns('').subject, 'they');
      expect(resolveNarrativePronouns('they/them').subject, 'they');
      expect(resolveNarrativePronouns('nonbinary').subject, 'they');
      expect(resolveNarrativePronouns('android').subject, 'they');
    });

    test('female is not swallowed by the male token', () {
      // "female" contains "male" as a substring — word-boundary check.
      expect(resolveNarrativePronouns('female').subject, 'she');
    });
  });

  group('greeting + example-dialog prompt fragments', () {
    const name = 'Nina';

    test('default first-person present is the historical greeting wording', () {
      const voice = NarrativeVoice.defaults;
      final lead = greetingLeadIn(
        name: name,
        voice: voice,
        pronouns: NarrativePronouns.they,
      );
      final rule = greetingPersonRule(
        name: name,
        voice: voice,
        pronouns: NarrativePronouns.they,
      );
      expect(
        lead,
        'Write an opening roleplay message as Nina (first person: "I", "my", "me"). This is the very first moment of the story — set the scene and introduce who Nina is through vivid prose. Output ONLY the message text.',
      );
      expect(
        rule,
        '- First person ONLY ("I", "my", "me") — never third person, never use "Nina" to refer to yourself',
      );
      expect(
        exampleDialogueVoiceRule(
          name: name,
          voice: voice,
          pronouns: NarrativePronouns.they,
        ),
        isNull,
      );
    });

    test('first person past keeps I/my/me and asks for past tense', () {
      const voice = NarrativeVoice(tense: NarrativeTense.past);
      final lead = greetingLeadIn(
        name: name,
        voice: voice,
        pronouns: NarrativePronouns.they,
      );
      final rule = greetingPersonRule(
        name: name,
        voice: voice,
        pronouns: NarrativePronouns.they,
      );
      expect(lead, contains('first person past tense'));
      expect(rule, contains('past tense'));
      expect(rule, contains('"I", "my", "me"'));
      expect(rule, startsWith('- First person'));
      expect(
        exampleDialogueVoiceRule(
          name: name,
          voice: voice,
          pronouns: NarrativePronouns.they,
        ),
        contains('first person past tense'),
      );
    });

    test('third person present uses she/her from Female', () {
      const voice = NarrativeVoice(perspective: NarrativePerspective.third);
      final pronouns = resolveNarrativePronouns('Female');
      final lead = greetingLeadIn(name: name, voice: voice, pronouns: pronouns);
      final rule = greetingPersonRule(
        name: name,
        voice: voice,
        pronouns: pronouns,
      );
      expect(lead, contains('third person present tense: she/her/her'));
      expect(rule, contains('she/her/her'));
      expect(rule, contains('Never first person'));
      expect(
        exampleDialogueVoiceRule(name: name, voice: voice, pronouns: pronouns),
        contains('third person present tense'),
      );
    });

    test('third person past uses he/him from Male', () {
      const voice = NarrativeVoice(
        perspective: NarrativePerspective.third,
        tense: NarrativeTense.past,
      );
      final pronouns = resolveNarrativePronouns('Male');
      final lead = greetingLeadIn(name: name, voice: voice, pronouns: pronouns);
      final rule = greetingPersonRule(
        name: name,
        voice: voice,
        pronouns: pronouns,
      );
      expect(lead, contains('third person past tense: he/him/his'));
      expect(rule, contains('he walked'));
      expect(rule, contains('Never first person'));
      expect(
        exampleDialogueVoiceRule(name: name, voice: voice, pronouns: pronouns),
        contains('third person past tense'),
      );
    });

    test(
      'default leaves description/personality on historical third person',
      () {
        expect(
          cardFieldVoiceClause(
            voice: NarrativeVoice.defaults,
            pronouns: NarrativePronouns.they,
          ),
          isNull,
        );
      },
    );

    test('past tense names description, personality, and example dialog', () {
      const voice = NarrativeVoice(tense: NarrativeTense.past);
      final clause = cardFieldVoiceClause(
        voice: voice,
        pronouns: NarrativePronouns.they,
      );
      expect(clause, contains('past tense'));
      expect(
        exampleDialogueVoiceRule(
          name: name,
          voice: voice,
          pronouns: NarrativePronouns.they,
        ),
        contains('past tense'),
      );
    });

    test('third person card fields use gender pronouns', () {
      const voice = NarrativeVoice(perspective: NarrativePerspective.third);
      final she = cardFieldVoiceClause(
        voice: voice,
        pronouns: resolveNarrativePronouns('Female'),
      );
      final he = cardFieldVoiceClause(
        voice: voice,
        pronouns: resolveNarrativePronouns('Male'),
      );
      expect(she, contains('she/her/her'));
      expect(he, contains('he/him/his'));
    });
  });

  group('generateCharacter threads voice into greeting + example prompts', () {
    test('third + past + Female lands she/her in both prompts', () async {
      final llm = _RecordingLlm();
      final gen = CharacterGenService(llm);
      await gen.generateCharacter(
        name: 'Nina',
        concept: 'a tired baker',
        sex: 'Female',
        narrativePerspective: 'third',
        narrativeTense: 'past',
        generateLorebook: false,
        altGreetingCount: 0,
        generateDescription: true,
      );

      final greeting = llm.prompts.firstWhere(
        (p) => p.contains('NARRATIVE STRUCTURE'),
        orElse: () => '',
      );
      final example = llm.prompts.firstWhere(
        (p) => p.contains('WRITE exactly 3 example exchanges'),
        orElse: () => '',
      );
      final base = llm.prompts.firstWhere(
        (p) => p.contains('Create a roleplay character card'),
        orElse: () => '',
      );
      expect(greeting, isNotEmpty, reason: 'greeting prompt must fire');
      expect(example, isNotEmpty, reason: 'example-dialog prompt must fire');
      expect(base, isNotEmpty, reason: 'base-card prompt must fire');
      expect(greeting, contains('third person past tense'));
      expect(greeting, contains('she/her/her'));
      expect(greeting, isNot(contains('First person ONLY')));
      expect(example, contains('third person past tense'));
      expect(example, contains('she/her/her'));
      expect(
        base,
        contains(
          '"description": (string) 2-3 paragraphs, third person past tense (she/her/her)',
        ),
      );
      expect(
        base,
        contains(
          '"personality": (string) 2-3 paragraphs, third person past tense (she/her/her)',
        ),
      );
    });

    test(
      'omitted voice stays on the historical first-person present lines',
      () async {
        final llm = _RecordingLlm();
        final gen = CharacterGenService(llm);
        await gen.generateCharacter(
          name: 'Nina',
          concept: 'a tired baker',
          generateLorebook: false,
          altGreetingCount: 0,
          generateDescription: true,
        );

        final greeting = llm.prompts.firstWhere(
          (p) => p.contains('NARRATIVE STRUCTURE'),
          orElse: () => '',
        );
        expect(
          greeting,
          contains(
            'Write an opening roleplay message as Nina (first person: "I", "my", "me")',
          ),
        );
        expect(
          greeting,
          contains(
            'First person ONLY ("I", "my", "me") — never third person, never use "Nina" to refer to yourself',
          ),
        );
        final base = llm.prompts.firstWhere(
          (p) => p.contains('Create a roleplay character card'),
          orElse: () => '',
        );
        expect(
          base,
          contains('2-3 paragraphs, third person. Physical appearance ONLY'),
        );
        expect(
          base,
          contains(
            '2-3 paragraphs, third person. Go beyond surface-level traits',
          ),
        );
        expect(base, isNot(contains('past tense')));
      },
    );

    test('generateCharacter stamps voice onto the returned card', () async {
      final llm = _RecordingLlm();
      final gen = CharacterGenService(llm);
      final card = await gen.generateCharacter(
        name: 'Nina',
        concept: 'a tired baker',
        sex: 'Female',
        narrativePerspective: 'third',
        narrativeTense: 'past',
        generateLorebook: false,
        altGreetingCount: 0,
        generateDescription: true,
      );
      expect(card, isNotNull);
      final stamped = readNarrativeVoice(card);
      expect(stamped.perspective, 'third');
      expect(stamped.tense, 'past');
      expect(stamped.sex, 'Female');
    });
  });

  group('Enhance keeps the card voice', () {
    test('omitted voice resolves to first-person present', () {
      final resolved = resolveEnhanceVoice();
      expect(resolved.perspective, 'first');
      expect(resolved.tense, 'present');
      expect(resolved.sex, isEmpty);
      expect(resolved.voice.isDefault, isTrue);
    });

    test('stamped third+past+Female is kept when Enhance omits params', () {
      final card = CharacterCard(name: 'Nina');
      stampNarrativeVoice(
        card,
        voice: const NarrativeVoice(
          perspective: NarrativePerspective.third,
          tense: NarrativeTense.past,
        ),
        sex: 'Female',
      );
      final resolved = resolveEnhanceVoice(source: card);
      expect(resolved.perspective, 'third');
      expect(resolved.tense, 'past');
      expect(resolved.sex, 'Female');
    });

    test(
      'enhanceCharacter on a third+past+Female card does not force defaults',
      () async {
        final card = CharacterCard(
          name: 'Nina',
          description: 'Original description of Nina.',
          personality: 'Original personality of Nina.',
          scenario: 'A quiet bar after hours.',
        );
        stampNarrativeVoice(
          card,
          voice: const NarrativeVoice(
            perspective: NarrativePerspective.third,
            tense: NarrativeTense.past,
          ),
          sex: 'Female',
        );
        final llm = _RecordingLlm();
        final gen = CharacterGenService(llm);
        await gen.enhanceCharacter(
          source: card,
          selection: const EnhanceSelection(
            greetings: true,
            exampleDialogue: true,
          ),
          chatGrounding: 'User: hi\nNina: she wiped flour off her hands.',
        );

        final greeting = llm.prompts.firstWhere(
          (p) => p.contains('NARRATIVE STRUCTURE'),
          orElse: () => '',
        );
        final example = llm.prompts.firstWhere(
          (p) => p.contains('Write example dialogue exchanges'),
          orElse: () => '',
        );
        final enrich = llm.prompts.firstWhere(
          (p) => p.contains('rewrite these three fields'),
          orElse: () => '',
        );
        expect(greeting, isNotEmpty, reason: 'greeting prompt must fire');
        expect(example, isNotEmpty, reason: 'example-dialog prompt must fire');
        expect(enrich, isNotEmpty, reason: 'enrichment prompt must fire');
        expect(greeting, contains('third person past tense'));
        expect(greeting, contains('she/her/her'));
        expect(greeting, isNot(contains('First person ONLY')));
        expect(example, contains('third person past tense'));
        expect(example, contains('she/her/her'));
        expect(enrich, contains('third person past tense (she/her/her)'));
      },
    );

    test('desktop Enhance and the web facade both forward voice', () {
      // Call-site pin: deleting either wire leaves Enhance on defaults
      // even when the card was stamped third+past.
      final wizard = File(
        'lib/ui/pages/home/enhance/enhance_wizard_page.dart',
      ).readAsStringSync();
      expect(wizard, contains('readNarrativeVoice(widget.character)'));
      expect(wizard, contains('narrativePerspective: voice.perspective'));
      final facade = File(
        'lib/services/web/facade/chargen_facade.dart',
      ).readAsStringSync();
      expect(facade, contains("body['narrativePerspective']"));
      expect(facade, contains('narrativePerspective: narrativePerspective'));
    });
  });
}

/// Answers every chargen stage with a valid stub and records every prompt
/// so the voice wiring can be asserted at the real call site.
class _RecordingLlm extends LLMService {
  final prompts = <String>[];

  static const _card =
      '{"description":"A wiry woman in a flour-dusted apron.","personality":"Hungry, sharp, kind under it.","scenario":"{{char}} is counting tips at the counter.","first_message":"I wipe flour off the apron and nod you in.","example_dialogue":"<START>\\n{{user}}: hi\\n{{char}}: yeah.","tags":["baker"]}';

  @override
  Stream<String> generateStream(GenerationParams params) async* {
    prompts.add(params.prompt);
    if (params.prompt.contains('WRITE exactly 3 example exchanges')) {
      yield '<START>\n{{user}}: hi\n{{char}}: She wipes flour off her hands.\n';
      return;
    }
    if (params.prompt.contains('NARRATIVE STRUCTURE')) {
      yield 'She counts the tips and looks up.';
      return;
    }
    if (params.prompt.contains('Create a roleplay character card')) {
      yield _card;
      return;
    }
    yield 'I talk like the shop taught me: short, warm, and tired.';
  }

  @override
  bool get isReady => true;

  @override
  String get backendName => 'narrative-voice-test';
}
