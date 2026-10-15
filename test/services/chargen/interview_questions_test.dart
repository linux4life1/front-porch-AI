// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The interview question set: the standard eleven in the sketch's order and
// wording, rendered for the chosen voice and pronouns; the row model the
// editors and the relay share; what one run asks.

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/services/chargen/chargen.dart';

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
}
