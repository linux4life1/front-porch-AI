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

import 'package:front_porch_ai/services/chargen/identity_facts.dart';
import 'package:front_porch_ai/services/chargen/narrative_voice.dart';

/// The creator's interview questions: the standard set, the row model the
/// editors and the relay share, and the rendering for one voice.
///
/// A row is a standard question (by key, rendered for the voice), an edited
/// one (its text is literal, kept whatever the voice does later) or a custom
/// one (no key). The two conditional rows are asked only when their setting
/// holds and keep that condition through an edit.

enum InterviewCondition { relationship, nsfw }

const int kInterviewQuestionCap = 12;

const int kInterviewQuestionMaxChars = 1000;

/// Stands in for the chosen relationship in the editor; filled at run time.
const String kRelationshipSlot = '[the relationship you chose]';

const List<String> kStandardInterviewKeys = [
  'voice',
  'wants',
  'wound',
  'relationship',
  'social',
  'pressure',
  'attraction',
  'joy',
  'living',
  'intimacy',
  'appearance',
];

InterviewCondition? standardConditionOf(String key) => switch (key) {
  'relationship' => InterviewCondition.relationship,
  'intimacy' => InterviewCondition.nsfw,
  _ => null,
};

class InterviewQuestion {
  const InterviewQuestion({this.key, this.text, this.condition});

  /// A standard question's key, null for a custom row.
  final String? key;

  /// Literal text: an edit of a standard row, or a custom row's text. Null
  /// renders the standard question for the voice.
  final String? text;

  final InterviewCondition? condition;

  bool get isStandard => key != null;
  bool get isEdited => key != null && text != null;
  bool get isConditional => condition != null;

  InterviewQuestion withText(String? text) =>
      InterviewQuestion(key: key, text: text, condition: condition);

  Map<String, dynamic> toJson() => {
    'key': key,
    'text': text,
    'condition': condition?.name,
  };

  /// Null when [raw] is absent or not a list; an empty list stays empty.
  /// Junk entries are dropped, an unknown key makes a custom row, the
  /// condition comes from the key (a custom row is never conditional), text
  /// is trimmed to [kInterviewQuestionMaxChars], and the list is capped.
  static List<InterviewQuestion>? listFromJson(Object? raw) {
    if (raw is! List) return null;
    final out = <InterviewQuestion>[];
    for (final item in raw) {
      if (item is! Map) continue;
      final rawKey = item['key'];
      final key = rawKey is String && kStandardInterviewKeys.contains(rawKey)
          ? rawKey
          : null;
      final rawText = item['text'];
      String? text = rawText is String ? rawText.trim() : null;
      if (text != null && text.length > kInterviewQuestionMaxChars) {
        text = text.substring(0, kInterviewQuestionMaxChars).trim();
      }
      if (key == null && text == null) continue;
      out.add(
        InterviewQuestion(
          key: key,
          text: text,
          condition: key == null ? null : standardConditionOf(key),
        ),
      );
      if (out.length >= kInterviewQuestionCap) break;
    }
    return out;
  }

  static List<Map<String, dynamic>> listToJson(List<InterviewQuestion> qs) => [
    for (final q in qs) q.toJson(),
  ];
}

List<InterviewQuestion> standardInterviewQuestions() => [
  for (final key in kStandardInterviewKeys)
    InterviewQuestion(key: key, condition: standardConditionOf(key)),
];

/// Pronoun forms the third-person templates need, including the verb
/// agreement that "they" changes.
class _P {
  const _P(this.p);

  final NarrativePronouns p;

  bool get plural => p.subject == 'they';
  String get sub => p.subject;
  String get obj => p.object;
  String get pos => p.possessive;
  String get refl => p.reflexive;
  String get d => "$sub'd";
  String get isC => plural ? "they're" : "$sub's";
  String get hasC => plural ? "they've" : "$sub's";
  String get does => plural ? 'do' : 'does';
  String get be => plural ? 'are' : 'is';
  String v(String singular, String pluralForm) =>
      plural ? pluralForm : singular;
}

const Map<String, String> _firstPerson = {
  'voice':
      'How do you talk? Give me two quick samples of your voice: first, how '
      'you\'d explain something to someone you\'re trying to impress — then '
      'how you\'d say the same thing to someone you completely trust.',
  'wants':
      'What do you want today, right now — and what do you want your life to '
      'look like a year from now?',
  'wound':
      'Tell me about a moment from your past that shaped who you are — what '
      'it left you afraid of, what you hide because of it, and how you steer '
      'people away when they get close to it.',
  'relationship':
      'Your relationship to {{user}} is: $kRelationshipSlot. Who are they to '
      'you, really — what do you want from them, and what\'s unresolved or '
      'unspoken between you?',
  'social':
      'How do you treat someone who\'s just met you versus someone you\'ve '
      'come to trust completely? What changes?',
  'pressure':
      'When you\'re cornered, or when someone truly angers you — what do you '
      'actually do? Show me, don\'t tell me.',
  'attraction':
      'How do you act around someone you\'re starting to like, how do you '
      'make sure they never guess, and what do you actually say to them?',
  'joy':
      'What brings you genuine joy or peace, the thing that lets your guard '
      'down — and what small, ordinary thing puts you off every time?',
  'living':
      'How do you live? What do you do for money, what does an ordinary day '
      'look like, and what do you never skip?',
  'intimacy':
      'When it comes to sex and intimacy: what do you crave, where are your '
      'hard limits, are you dominant or submissive — and if there\'s someone '
      'you desire, what do they do to you?',
  'appearance':
      'Now describe your physical appearance in your own words — what you '
      'look like, how you carry yourself, and what you are wearing and '
      'carrying in this opening scene. Be specific.',
};

String _thirdPerson(String key, _P p) => switch (key) {
  'voice' =>
    'How does {{char}} talk? Give two quick samples of ${p.pos} voice, in '
        '${p.pos} own words: first, how ${p.d} explain something to someone '
        '${p.isC} trying to impress — then how ${p.d} say the same thing to '
        'someone ${p.sub} completely ${p.v('trusts', 'trust')}.',
  'wants' =>
    'What ${p.does} ${p.sub} want today, right now — and what ${p.does} '
        '${p.sub} want ${p.pos} life to look like a year from now?',
  'wound' =>
    'Tell me about a moment from ${p.pos} past that shaped who ${p.sub} '
        '${p.be} — what it left ${p.obj} afraid of, what ${p.sub} '
        '${p.v('hides', 'hide')} because of it, and how ${p.sub} '
        '${p.v('steers', 'steer')} people away when they get close to it.',
  'relationship' =>
    '{{char}}\'s relationship to {{user}} is: $kRelationshipSlot. '
        '${p.v('Who are they to ${p.obj}, really — what ${p.does} ${p.sub} want from them', 'Who is {{user}} to them, really — what do they want from {{user}}')}, '
        'and what\'s unresolved or unspoken between them?',
  'social' =>
    'How ${p.does} ${p.sub} treat someone who\'s just met ${p.obj} versus '
        'someone ${p.hasC} come to trust completely? What changes?',
  'pressure' =>
    'When ${p.isC} cornered, or when someone truly angers ${p.obj} — what '
        '${p.does} ${p.sub} actually do? Show it, don\'t tell it.',
  'attraction' =>
    'How ${p.does} ${p.sub} act around someone ${p.isC} starting to like, '
        'how ${p.does} ${p.sub} make sure '
        '${p.v('they never guess', 'that person never guesses')}, and what '
        '${p.does} ${p.sub} actually say to them?',
  'joy' =>
    'What brings ${p.obj} genuine joy or peace, the thing that lets ${p.pos} '
        'guard down — and what small, ordinary thing puts ${p.obj} off every '
        'time?',
  'living' =>
    'How ${p.does} ${p.sub} live? What ${p.does} ${p.sub} do for money, what '
        'does an ordinary day look like, and what ${p.does} ${p.sub} never '
        'skip?',
  'intimacy' =>
    'When it comes to sex and intimacy: what ${p.does} ${p.sub} crave, where '
        'are ${p.pos} hard limits, ${p.be} ${p.sub} dominant or submissive — '
        'and if there\'s someone ${p.sub} ${p.v('desires', 'desire')}, '
        '${p.v('what do they do to ${p.obj}', 'what does that person do to them')}?',
  'appearance' =>
    'Now describe ${p.pos} physical appearance — what ${p.sub} '
        '${p.v('looks', 'look')} like, how ${p.sub} '
        '${p.v('carries', 'carry')} ${p.refl}, and what ${p.sub} ${p.be} '
        'wearing and carrying in this opening scene. Be specific.',
  _ => '',
};

/// The standard question [key] for [voice]; the relationship slot is kept.
String standardInterviewText(
  String key, {
  required NarrativeVoice voice,
  required NarrativePronouns pronouns,
}) =>
    voice.isFirst ? (_firstPerson[key] ?? '') : _thirdPerson(key, _P(pronouns));

/// What the editor shows for [q]: its literal text, else the standard text.
String interviewQuestionText(
  InterviewQuestion q, {
  required NarrativeVoice voice,
  required NarrativePronouns pronouns,
}) {
  final text = q.text;
  if (text != null) return text;
  final key = q.key;
  if (key == null) return '';
  return standardInterviewText(key, voice: voice, pronouns: pronouns);
}

/// The questions one run asks, in order. Null [questions] is the standard
/// set. The cap applies first; a conditional row is dropped when its setting
/// does not hold; blank rows are dropped; the relationship slot is filled.
/// A list with no unconditional row left asks nothing: the two conditional
/// rows cannot be removed, and "remove them all" has to mean no interview.
List<String> renderInterviewQuestions(
  List<InterviewQuestion>? questions, {
  required NarrativeVoice voice,
  required NarrativePronouns pronouns,
  required String relationship,
  required bool nsfwEnabled,
}) {
  final rows = (questions ?? standardInterviewQuestions())
      .take(kInterviewQuestionCap)
      .toList();
  final hasRelationship = hasRelationshipToUser(relationship);
  final out = <String>[];
  var unconditional = false;
  for (final q in rows) {
    if (q.condition == InterviewCondition.relationship && !hasRelationship) {
      continue;
    }
    if (q.condition == InterviewCondition.nsfw && !nsfwEnabled) continue;
    final text = interviewQuestionText(
      q,
      voice: voice,
      pronouns: pronouns,
    ).replaceAll(kRelationshipSlot, relationship.trim()).trim();
    if (text.isEmpty) continue;
    if (!q.isConditional) unconditional = true;
    out.add(text);
  }
  // Decided after blanks are dropped: a blank custom row must not keep the
  // two conditional questions alive on their own.
  return unconditional ? out : const [];
}

/// Whether [rows] would ask nothing: no unconditional row with text, which
/// the editors show as "no interview" in place of the remove-them-all hint.
bool interviewAsksNothing(
  List<InterviewQuestion> rows, {
  required NarrativeVoice voice,
  required NarrativePronouns pronouns,
}) => !rows.any(
  (q) =>
      !q.isConditional &&
      interviewQuestionText(
        q,
        voice: voice,
        pronouns: pronouns,
      ).trim().isNotEmpty,
);

String _clip(String s, int max) => s.length > max ? s.substring(0, max) : s;

/// The system seed every interview prompt starts with. First person present
/// is the seed the creator always used, byte for byte.
String interviewSeed({
  required String name,
  required String personality,
  required String scenario,
  String? worldLore,
  String chatGrounding = '',
  required NarrativeVoice voice,
  required NarrativePronouns pronouns,
  bool definesChar = false,
}) {
  final lore = worldLore != null && worldLore.trim().isNotEmpty;
  final grounded = chatGrounding.trim().isNotEmpty;
  const tight =
      'Be specific, vivid, and emotionally honest — but keep each answer '
      'TIGHT: a few sharp sentences, under ~150 words. Depth over length; do '
      'not ramble. ';
  final charLine = definesChar ? '\nIn the questions, {{char}} is $name.' : '';
  if (voice.isFirst) {
    final past = voice.isPast
        ? 'Answer each question in first person, past tense ("I was", '
              '"I said"), fully in-character. '
        : 'Answer each question in first person, fully in-character. ';
    return 'You are $name.\n'
        'Your personality: ${_clip(personality, 400)}\n'
        'Your scenario: ${_clip(scenario, 200)}\n\n'
        '${lore ? "You exist in the following established world. Use its terminology, locations, and facts:\n$worldLore\n\n" : ""}'
        '${grounded ? "How you have ACTUALLY been played in a real chat with {{user}} — this is the source of truth for your voice, manner, and history. Every answer must stay true to it:\n$chatGrounding\n\n" : ""}'
        '$past$tight'
        'Respond as $name would speak — use their vocabulary, cadence, and '
        'emotional register.$charLine';
  }
  final p = _P(pronouns);
  final tense = voice.isPast ? 'past' : 'present';
  return 'You are narrating $name.\n'
      '$name\'s personality: ${_clip(personality, 400)}\n'
      '$name\'s scenario: ${_clip(scenario, 200)}\n\n'
      '${lore ? "$name exists in the following established world. Use its terminology, locations, and facts:\n$worldLore\n\n" : ""}'
      '${grounded ? "How $name has ACTUALLY been played in a real chat with {{user}} — this is the source of truth for $name's voice, manner, and history. Every answer must stay true to it:\n$chatGrounding\n\n" : ""}'
      'Answer each question in third person, $tense tense, about $name '
      '(${pronouns.slashSet}), fully in-character. Show how $name thinks and '
      'acts, and quote $name\'s own words when ${p.sub} '
      '${p.v('speaks', 'speak')}. $tight'
      'Keep $name\'s vocabulary, cadence, and emotional register in the '
      'quoted lines.$charLine';
}

/// What each interview prompt ends with, so the model answers in the voice.
String interviewAnswerLead(String name, NarrativeVoice voice) =>
    voice.isFirst ? '$name: ' : 'Answer: ';

/// The standard set rendered for display (slot kept), for the phone's
/// editor: `{cap, pronouns: {subject, possessive}, rows: [{key, condition,
/// text}]}`.
Map<String, dynamic> standardInterviewView({
  String? perspective,
  String? tense,
  String? sex,
}) {
  final voice = NarrativeVoice.parse(perspective: perspective, tense: tense);
  final pronouns = resolveNarrativePronouns(sex ?? '');
  return {
    'cap': kInterviewQuestionCap,
    'pronouns': {
      'subject': pronouns.subject,
      'possessive': pronouns.possessive,
    },
    'rows': [
      for (final q in standardInterviewQuestions())
        {
          'key': q.key,
          'condition': q.condition?.name,
          'text': interviewQuestionText(q, voice: voice, pronouns: pronouns),
        },
    ],
  };
}
