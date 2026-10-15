// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The interview question set: the standard eleven in the sketch's order and
// wording, rendered for the chosen voice and pronouns; the row model the
// editors and the relay share; what one run asks.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/services/character_gen_service.dart';
import 'package:front_porch_ai/services/chargen/chargen.dart';

import 'support/marker_chargen_llm.dart';

const _first = NarrativeVoice();
const _thirdPast = NarrativeVoice(
  perspective: NarrativePerspective.third,
  tense: NarrativeTense.past,
);

List<String> _render(
  List<InterviewQuestion>? qs, {
  NarrativeVoice voice = _first,
  NarrativePronouns pronouns = NarrativePronouns.they,
  String relationship = '',
  bool nsfw = false,
}) => renderInterviewQuestions(
  qs,
  voice: voice,
  pronouns: pronouns,
  relationship: relationship,
  nsfwEnabled: nsfw,
);

/// The third-person wording the approved sketch shows, she/her, in order.
const _sketchShe = [
  "How does {{char}} talk? Give two quick samples of her voice, in her own words: first, how she'd explain something to someone she's trying to impress — then how she'd say the same thing to someone she completely trusts.",
  'What does she want today, right now — and what does she want her life to look like a year from now?',
  'Tell me about a moment from her past that shaped who she is — what it left her afraid of, what she hides because of it, and how she steers people away when they get close to it.',
  "{{char}}'s relationship to {{user}} is: [the relationship you chose]. Who are they to her, really — what does she want from them, and what's unresolved or unspoken between them?",
  "How does she treat someone who's just met her versus someone she's come to trust completely? What changes?",
  "When she's cornered, or when someone truly angers her — what does she actually do? Show it, don't tell it.",
  "How does she act around someone she's starting to like, how does she make sure they never guess, and what does she actually say to them?",
  'What brings her genuine joy or peace, the thing that lets her guard down — and what small, ordinary thing puts her off every time?',
  'How does she live? What does she do for money, what does an ordinary day look like, and what does she never skip?',
  "When it comes to sex and intimacy: what does she crave, where are her hard limits, is she dominant or submissive — and if there's someone she desires, what do they do to her?",
  'Now describe her physical appearance — what she looks like, how she carries herself, and what she is wearing and carrying in this opening scene. Be specific.',
];

void main() {
  group('the standard set', () {
    test('eleven keys in the sketch order, two of them conditional', () {
      final std = standardInterviewQuestions();
      expect(std.map((q) => q.key), kStandardInterviewKeys);
      expect(std.length, 11);
      expect(std.where((q) => q.isConditional).map((q) => q.key), [
        'relationship',
        'intimacy',
      ]);
      expect(std.any((q) => q.isEdited), isFalse);
    });

    test('nine asked as strangers with 18+ off, eleven with both set', () {
      expect(_render(null).length, 9);
      expect(_render(null, relationship: 'stranger').length, 9);
      final all = _render(null, relationship: 'old friend', nsfw: true);
      expect(all.length, 11);
      expect(all[3], contains('is: old friend.'));
      expect(all[3], isNot(contains(kRelationshipSlot)));
      expect(all[9], contains('sex and intimacy'));
    });

    test('first person is the voice the creator always used', () {
      final qs = _render(null);
      expect(
        qs.first,
        startsWith('How do you talk? Give me two quick samples'),
      );
      expect(qs.last, startsWith('Now describe your physical appearance'));
      expect(qs.join('\n'), isNot(contains('{{char}}')));
    });
  });

  group('third person', () {
    test('she/her matches the sketch word for word', () {
      final std = standardInterviewQuestions();
      for (var i = 0; i < std.length; i++) {
        expect(
          interviewQuestionText(
            std[i],
            voice: _thirdPast,
            pronouns: NarrativePronouns.she,
          ),
          _sketchShe[i],
          reason: 'question ${i + 1}',
        );
      }
    });

    test('he and they read as English', () {
      final bad = RegExp(
        r"\bthey's|\bthey (is|has|does|was|wants|hides|steers|desires|looks|carries|trusts|speaks)\b",
      );
      for (final p in [NarrativePronouns.he, NarrativePronouns.they]) {
        final all = _render(
          null,
          voice: _thirdPast,
          pronouns: p,
          relationship: 'rival',
          nsfw: true,
        );
        expect(all.length, 11);
        final text = all.join('\n');
        expect(bad.hasMatch(text), isFalse, reason: '${p.subject}: $text');
        expect(text, isNot(contains(' you ')));
      }
      final they = _render(
        null,
        voice: _thirdPast,
        pronouns: NarrativePronouns.they,
        relationship: 'rival',
      );
      expect(they[0], contains('someone they completely trust.'));
      expect(they[2], contains('what they hide because of it'));
      expect(they[3], contains('Who is {{user}} to them'));
      expect(they[8], contains('what do they never skip'));
    });

    test('tense changes the seed, not the questions', () {
      const present = NarrativeVoice(perspective: NarrativePerspective.third);
      expect(
        _render(null, voice: present, pronouns: NarrativePronouns.she),
        _render(null, voice: _thirdPast, pronouns: NarrativePronouns.she),
      );
    });
  });

  group('rows the user shaped', () {
    test('an edited standard row is kept as written in any voice', () {
      final rows = standardInterviewQuestions();
      rows[0] = rows[0].withText('Say three things only you would say.');
      expect(rows[0].isEdited, isTrue);
      expect(rows[0].isStandard, isTrue);
      final she = _render(
        rows,
        voice: _thirdPast,
        pronouns: NarrativePronouns.she,
      );
      expect(she.first, 'Say three things only you would say.');
      expect(she[1], _sketchShe[1]);
    });

    test('an edited conditional row keeps its condition', () {
      final rows = standardInterviewQuestions();
      rows[3] = rows[3].withText('What do you owe {{user}}?');
      expect(rows[3].condition, InterviewCondition.relationship);
      expect(_render(rows).length, 9);
      expect(
        _render(rows, relationship: 'debtor')[3],
        'What do you owe {{user}}?',
      );
    });

    test(
      'custom rows go in verbatim, blanks are dropped, twelve is the cap',
      () {
        final rows = [
          ...standardInterviewQuestions(),
          const InterviewQuestion(text: 'What do you hum when nobody listens?'),
          const InterviewQuestion(text: '   '),
          const InterviewQuestion(text: 'A thirteenth question never asked.'),
        ];
        final asked = _render(rows, relationship: 'rival', nsfw: true);
        expect(asked.length, 12);
        expect(asked.last, 'What do you hum when nobody listens?');
        expect(asked, isNot(contains('A thirteenth question never asked.')));
      },
    );

    test('a blank custom row does not keep the conditional rows alive', () {
      // Grok, 2026-10-14: the gate once ran before blanks were dropped, so
      // a blank unconditional row let the two conditional questions run on
      // their own.
      final rows = [
        const InterviewQuestion(key: 'voice', text: '   '),
        ...standardInterviewQuestions().where((q) => q.isConditional),
      ];
      expect(_render(rows, relationship: 'rival', nsfw: true), isEmpty);
      expect(
        interviewAsksNothing(
          rows,
          voice: _first,
          pronouns: NarrativePronouns.they,
        ),
        isTrue,
      );
      expect(
        interviewAsksNothing(
          standardInterviewQuestions(),
          voice: _first,
          pronouns: NarrativePronouns.they,
        ),
        isFalse,
      );
    });

    test('no rows, or only the conditional rows, means no interview', () {
      expect(_render(const []), isEmpty);
      final onlyConditional = standardInterviewQuestions()
          .where((q) => q.isConditional)
          .toList();
      expect(
        _render(onlyConditional, relationship: 'rival', nsfw: true),
        isEmpty,
      );
      expect(_render([const InterviewQuestion(text: 'One question.')]), [
        'One question.',
      ]);
    });
  });

  group('the wire shape', () {
    test('absent is the standard set, an empty list is no interview', () {
      expect(InterviewQuestion.listFromJson(null), isNull);
      expect(InterviewQuestion.listFromJson('no'), isNull);
      expect(InterviewQuestion.listFromJson(const []), isEmpty);
    });

    test('junk is dropped, the condition follows the key, the cap holds', () {
      final rows = InterviewQuestion.listFromJson([
        {'key': 'relationship', 'text': null, 'condition': 'nsfw'},
        {'key': 'nonsense', 'text': 'Kept as a custom row.'},
        {'key': 'voice', 'text': '  Edited voice.  '},
        {'text': 'x' * (kInterviewQuestionMaxChars + 50)},
        'junk',
        {'key': null, 'text': null},
        for (var i = 0; i < 20; i++) {'text': 'extra $i'},
      ])!;
      expect(rows.length, kInterviewQuestionCap);
      expect(rows[0].condition, InterviewCondition.relationship);
      expect(rows[1].key, isNull);
      expect(rows[1].text, 'Kept as a custom row.');
      expect(rows[1].isConditional, isFalse);
      expect(rows[2].text, 'Edited voice.');
      expect(rows[3].text!.length, kInterviewQuestionMaxChars);
    });

    test('a round trip keeps every row', () {
      final rows = standardInterviewQuestions();
      rows[9] = rows[9].withText('Edited 18+ question.');
      rows.add(const InterviewQuestion(text: 'Custom.'));
      final back = InterviewQuestion.listFromJson(
        InterviewQuestion.listToJson(rows),
      )!;
      expect(back.map((q) => q.key), rows.map((q) => q.key));
      expect(back.map((q) => q.text), rows.map((q) => q.text));
      expect(back.map((q) => q.condition), rows.map((q) => q.condition));
    });

    test('the view the phone reads carries cap, pronouns and the rows', () {
      final view = standardInterviewView(
        perspective: 'third',
        tense: 'past',
        sex: 'male',
      );
      expect(view['cap'], kInterviewQuestionCap);
      expect(view['pronouns'], {'subject': 'he', 'possessive': 'his'});
      final rows = view['rows'] as List;
      expect(rows.length, 11);
      expect((rows[3] as Map)['condition'], 'relationship');
      expect((rows[3] as Map)['text'], contains(kRelationshipSlot));
      expect((rows[0] as Map)['text'], contains('his voice'));
    });
  });

  group('the seed', () {
    test('first person present is the seed the creator always used', () {
      final seed = interviewSeed(
        name: 'Mara',
        personality: 'Dry.',
        scenario: 'A storm.',
        voice: _first,
        pronouns: NarrativePronouns.she,
      );
      expect(seed, startsWith('You are Mara.\nYour personality: Dry.\n'));
      expect(
        seed,
        contains('Answer each question in first person, fully in-character. '),
      );
      expect(seed, endsWith('emotional register.'));
      expect(interviewAnswerLead('Mara', _first), 'Mara: ');
    });

    test('third person names the voice, the tense and the quoting rule', () {
      final seed = interviewSeed(
        name: 'Mara',
        personality: 'Dry.',
        scenario: 'A storm.',
        voice: _thirdPast,
        pronouns: NarrativePronouns.she,
        definesChar: true,
      );
      expect(seed, startsWith('You are narrating Mara.\n'));
      expect(
        seed,
        contains('third person, past tense, about Mara (she/her/her)'),
      );
      expect(seed, contains("quote Mara's own words when she speaks"));
      expect(seed, endsWith('In the questions, {{char}} is Mara.'));
      expect(interviewAnswerLead('Mara', _thirdPast), 'Answer: ');
      final they = interviewSeed(
        name: 'Rook',
        personality: 'Blunt.',
        scenario: 'A dock.',
        voice: _thirdPast,
        pronouns: NarrativePronouns.they,
      );
      expect(they, contains("quote Rook's own words when they speak"));
    });
  });

  group('the run inputs carry the list', () {
    GenRunInputs trip(GenRunInputs inputs) => GenRunInputs.fromJson(
      jsonDecode(jsonEncode(inputs.toJson())) as Map<String, dynamic>,
    );

    test('a list round-trips, [] stays [], absent stays null', () {
      const custom = [
        InterviewQuestion(key: 'voice'),
        InterviewQuestion(text: 'What does {{char}} keep in her boots?'),
        InterviewQuestion(
          key: 'intimacy',
          text: 'EDITED What does she want at night?',
          condition: InterviewCondition.nsfw,
        ),
      ];
      final kept = trip(
        const GenRunInputs(
          name: 'Mara',
          concept: 'x',
          interviewQuestions: custom,
        ),
      ).interviewQuestions;
      expect(kept?.map((q) => q.toJson()), custom.map((q) => q.toJson()));

      final none = trip(
        const GenRunInputs(name: 'Mara', concept: 'x', interviewQuestions: []),
      ).interviewQuestions;
      expect(
        none,
        isNotNull,
        reason: '[] is "no interview", not the standard set',
      );
      expect(none, isEmpty);

      expect(
        trip(const GenRunInputs(name: 'Mara', concept: 'x')).interviewQuestions,
        isNull,
      );
      expect(
        GenRunInputs.fromJson(const {'name': 'Mara'}).interviewQuestions,
        isNull,
        reason:
            'a pending file written before the editor asks the standard set',
      );
    });
  });

  group('the creator asks the run\'s questions in its voice', () {
    String asked(String prompt) => prompt.substring(
      prompt.lastIndexOf('Question: ') + 'Question: '.length,
      prompt.lastIndexOf('\n\n'),
    );
    List<String> interviewPrompts(MarkerChargenLlm llm) => [
      for (final p in llm.prompts)
        if (p.contains('Question: ')) p,
    ];
    final markerCard = jsonDecode(markerCardJson()) as Map<String, dynamic>;

    test('third person past, she: the list in order, the seed and the lead '
        'in that voice', () async {
      const custom = 'What does {{char}} keep under the chart-room floor?';
      final llm = MarkerChargenLlm();
      final paused = await CharacterGenService(llm).generateProfile(
        inputs: const GenRunInputs(
          name: 'Mira Holt',
          concept: 'A cartographer of drowned coasts.',
          sex: 'female',
          relationship: 'old friend',
          narrativePerspective: 'third',
          narrativeTense: 'past',
          altGreetingCount: 0,
          interviewQuestions: [
            InterviewQuestion(key: 'voice'),
            InterviewQuestion(text: custom),
            InterviewQuestion(
              key: 'relationship',
              condition: InterviewCondition.relationship,
            ),
            InterviewQuestion(key: 'wound'),
            InterviewQuestion(
              key: 'intimacy',
              condition: InterviewCondition.nsfw,
            ),
            InterviewQuestion(key: 'appearance'),
          ],
        ),
      );

      final prompts = interviewPrompts(llm);
      expect(prompts.map(asked).toList(), [
        _sketchShe[0],
        custom,
        _sketchShe[3].replaceAll(kRelationshipSlot, 'old friend'),
        _sketchShe[2],
        _sketchShe[10],
      ], reason: 'the 18+ row is dropped with 18+ off');
      for (final p in prompts) {
        expect(p, startsWith('You are narrating Mira Holt.\n'));
        expect(
          p,
          contains(
            'Answer each question in third person, past tense, about Mira '
            'Holt (she/her/her)',
          ),
        );
        expect(p, contains('In the questions, {{char}} is Mira Holt.'));
        expect(p, endsWith('\n\nAnswer: '));
      }
      expect(paused!.interviewTranscript, contains('Q: $custom\nA: '));
    });

    test('first person present asks the standard set with the seed the '
        'creator always sent', () async {
      final llm = MarkerChargenLlm();
      await CharacterGenService(llm).generateProfile(
        inputs: const GenRunInputs(
          name: 'Mira Holt',
          concept: 'A cartographer of drowned coasts.',
          altGreetingCount: 0,
        ),
      );
      final prompts = interviewPrompts(llm);
      expect(prompts, hasLength(9));
      // The seed exactly as gen_interview_steps.dart wrote it before the
      // questions became editable.
      final oldSeed =
          'You are Mira Holt.\n'
          'Your personality: ${markerCard['personality']}\n'
          'Your scenario: ${markerCard['scenario']}\n\n'
          'Answer each question in first person, fully in-character. Be '
          'specific, vivid, and emotionally honest — but keep each answer '
          'TIGHT: a few sharp sentences, under ~150 words. Depth over length; '
          'do not ramble. Respond as Mira Holt would speak — use their '
          'vocabulary, cadence, and emotional register.';
      expect(
        prompts.first,
        '$oldSeed\n\n'
        'Question: How do you talk? Give me two quick samples of your voice: '
        'first, how you\'d explain something to someone you\'re trying to '
        'impress — then how you\'d say the same thing to someone you '
        'completely trust.\n\n'
        'Mira Holt: ',
      );
      expect(prompts.last, endsWith('Be specific.\n\nMira Holt: '));
    });

    test('[] asks nothing: no transcript, the facts still read, and Phase B '
        'still writes the example dialogue', () async {
      final llm = MarkerChargenLlm(
        toolAnswers: {
          kIdentityFactsToolName: {
            'occupation': 'cartographer',
            'ambitions': ['map the drowned city'],
            'likes': ['salt wind'],
          },
        },
      );
      final gen = CharacterGenService(llm);
      final paused = await gen.generateProfile(
        inputs: const GenRunInputs(
          name: 'Mira Holt',
          concept: 'A cartographer of drowned coasts.',
          altGreetingCount: 0,
          generateLorebook: false,
          interviewQuestions: [],
        ),
      );

      expect(paused, isNotNull);
      expect(
        llm.sent('Question: '),
        isFalse,
        reason: '[] is not the standard set',
      );
      expect(paused!.interviewTranscript, '');
      expect(
        llm.sent('You have just completed an in-character'),
        isFalse,
        reason: 'no interview, no interview rewrite',
      );
      expect(llm.toolChoices, contains(kIdentityFactsToolName));
      expect(paused.facts?.occupation, 'cartographer');
      final facts = llm.promptWith('Read the facts this character profile');
      expect(facts, isNot(contains('INTERVIEW (their own words)')));

      final card = await gen.completeCharacter(paused: paused);
      expect(card, isNotNull);
      final dialogue = llm.promptWith('Write example dialogue exchanges');
      expect(
        dialogue,
        isNotEmpty,
        reason: 'dialogue is written with no interview',
      );
      expect(dialogue, isNot(contains('SOURCE MATERIAL')));
      expect(card!.mesExample, contains('mapped every one of them twice'));
      expect(
        llm.promptWith('Seed Porch Life identity'),
        isNot(contains('INTERVIEW (their own words)')),
      );

      // The Profile step's rewrite reads no transcript and says so.
      await gen.rewriteProfile(
        paused: paused,
        description: 'Short and plain.',
        personality: 'Cheerful.',
        scenario: paused.card.scenario,
        direction: 'Make her braver.',
      );
      final rewrite = llm.promptWith('You have just completed an in-character');
      expect(
        rewrite,
        startsWith(
          'You have just completed an in-character interview with Mira '
          'Holt.\n',
        ),
      );
      expect(
        rewrite,
        contains(
          'INTERVIEW TRANSCRIPT:\n(No interview was run. Work from the current '
          'fields and the direction.)\n',
        ),
      );
    });
  });
}
