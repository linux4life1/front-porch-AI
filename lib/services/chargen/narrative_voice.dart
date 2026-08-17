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

import 'package:front_porch_ai/models/models.dart';

// Perspective + tense for AI character generation (character text +
// example dialog + greetings).
//
// Default is first-person present — the historical baked-in voice. Other
// combinations are opt-in from the creator's output settings. Third person
// resolves he/she/they from the Sex field so pronouns stay consistent.
//
// Create stamps the choice onto the card (`extensions.narrative_voice`) so
// Enhance can keep it. Params override the stamp; omitted voice stays default.

enum NarrativePerspective { first, third }

enum NarrativeTense { present, past }

/// Resolved third-person pronoun set. First person always uses I/my/me.
class NarrativePronouns {
  const NarrativePronouns({
    required this.subject,
    required this.object,
    required this.possessive,
    required this.possessiveNoun,
    required this.reflexive,
  });

  final String subject;
  final String object;
  final String possessive;
  final String possessiveNoun;
  final String reflexive;

  /// Compact "she/her/hers" (or he/him, they/them) for prompt instructions.
  String get slashSet => '$subject/$object/$possessive';

  static const they = NarrativePronouns(
    subject: 'they',
    object: 'them',
    possessive: 'their',
    possessiveNoun: 'theirs',
    reflexive: 'themselves',
  );
  static const she = NarrativePronouns(
    subject: 'she',
    object: 'her',
    possessive: 'her',
    possessiveNoun: 'hers',
    reflexive: 'herself',
  );
  static const he = NarrativePronouns(
    subject: 'he',
    object: 'him',
    possessive: 'his',
    possessiveNoun: 'his',
    reflexive: 'himself',
  );
}

/// Chosen voice for one generation run. Defaults match the pre-option prompts.
class NarrativeVoice {
  const NarrativeVoice({
    this.perspective = NarrativePerspective.first,
    this.tense = NarrativeTense.present,
  });

  final NarrativePerspective perspective;
  final NarrativeTense tense;

  static const defaults = NarrativeVoice();

  bool get isDefault =>
      perspective == NarrativePerspective.first &&
      tense == NarrativeTense.present;

  bool get isFirst => perspective == NarrativePerspective.first;
  bool get isPast => tense == NarrativeTense.past;

  String get perspectiveLabel => isFirst ? 'First person' : 'Third person';
  String get tenseLabel => isPast ? 'Past' : 'Present';

  static NarrativePerspective parsePerspective(String? raw) {
    switch ((raw ?? '').trim().toLowerCase()) {
      case 'third':
      case 'third person':
      case 'third-person':
        return NarrativePerspective.third;
      default:
        return NarrativePerspective.first;
    }
  }

  static NarrativeTense parseTense(String? raw) {
    switch ((raw ?? '').trim().toLowerCase()) {
      case 'past':
        return NarrativeTense.past;
      default:
        return NarrativeTense.present;
    }
  }

  factory NarrativeVoice.parse({String? perspective, String? tense}) {
    return NarrativeVoice(
      perspective: parsePerspective(perspective),
      tense: parseTense(tense),
    );
  }
}

/// Map the creator's free-text Sex field to he/she/they.
///
/// Unknown, blank, or explicitly they/them/nonbinary → they/them. Check
/// feminine tokens before masculine so "female" is not swallowed by "male".
NarrativePronouns resolveNarrativePronouns(String sex) {
  final s = sex.trim().toLowerCase();
  if (s.isEmpty) return NarrativePronouns.they;
  if (_hasAny(s, _theyTokens)) return NarrativePronouns.they;
  if (_hasAny(s, _sheTokens)) return NarrativePronouns.she;
  if (_hasAny(s, _heTokens)) return NarrativePronouns.he;
  return NarrativePronouns.they;
}

const _sheTokens = [
  'female',
  'woman',
  'girl',
  'she/her',
  'she',
  'lady',
  'feminine',
];
const _heTokens = [
  'male',
  'man',
  'boy',
  'he/him',
  'he',
  'gentleman',
  'masculine',
];
const _theyTokens = [
  'they/them',
  'nonbinary',
  'non-binary',
  'enby',
  'agender',
  'genderfluid',
  'nb',
];

bool _hasAny(String haystack, List<String> tokens) {
  for (final t in tokens) {
    if (t.contains('/')) {
      if (haystack.contains(t)) return true;
      continue;
    }
    if (RegExp('\\b${RegExp.escape(t)}\\b').hasMatch(haystack)) return true;
  }
  return false;
}

/// Opening line of the greeting prompt. Default is the historical first-person
/// present sentence so the unchanged path stays byte-equivalent.
String greetingLeadIn({
  required String name,
  required NarrativeVoice voice,
  required NarrativePronouns pronouns,
}) {
  if (voice.isDefault) {
    return 'Write an opening roleplay message as $name (first person: "I", "my", "me"). This is the very first moment of the story — set the scene and introduce who $name is through vivid prose. Output ONLY the message text.';
  }
  final voicePhrase = _voicePhrase(voice, pronouns);
  return 'Write an opening roleplay message as $name ($voicePhrase). This is the very first moment of the story — set the scene and introduce who $name is through vivid prose. Output ONLY the message text.';
}

/// The RULES bullet that used to hard-lock first person.
String greetingPersonRule({
  required String name,
  required NarrativeVoice voice,
  required NarrativePronouns pronouns,
}) {
  if (voice.isDefault) {
    return '- First person ONLY ("I", "my", "me") — never third person, never use "$name" to refer to yourself';
  }
  if (voice.isFirst) {
    final tenseBit = voice.isPast
        ? 'past tense ("I walked", "I said", not "I walk")'
        : 'present tense ("I walk", "I say", not "I walked")';
    return '- First person $tenseBit ONLY ("I", "my", "me") — never third person, never use "$name" to refer to yourself';
  }
  final p = pronouns;
  final tenseBit = voice.isPast
      ? 'past tense ("${p.subject} walked", "${p.subject} said")'
      : 'present tense ("${p.subject} walks", "${p.subject} says")';
  return '- Third person $tenseBit ONLY — narrate $name as ${p.subject}/${p.object}/${p.possessive}. Never first person ("I", "my", "me"). You MAY use "$name" as the narrator.';
}

/// Extra RULES line for example dialogue. Null on the default path so that
/// prompt stays unchanged when the user did not pick a voice.
String? exampleDialogueVoiceRule({
  required String name,
  required NarrativeVoice voice,
  required NarrativePronouns pronouns,
}) {
  if (voice.isDefault) return null;
  if (voice.isFirst) {
    final tenseBit = voice.isPast ? 'past tense' : 'present tense';
    return '- Write every {{char}} response in first person $tenseBit ("I", "my", "me") — never third person, never use "$name" to refer to {{char}}';
  }
  final p = pronouns;
  final tenseBit = voice.isPast ? 'past tense' : 'present tense';
  return '- Write every {{char}} response in third person $tenseBit — narrate $name as ${p.subject}/${p.object}/${p.possessive}. Never first person ("I", "my", "me")';
}

/// Voice clause for description / personality field specs.
///
/// Null on the default path so those strings stay the historical
/// "third person" / "Third-person" wording. Past tense and third-person
/// pronouns are appended only when the user opted out of the default.
String? cardFieldVoiceClause({
  required NarrativeVoice voice,
  required NarrativePronouns pronouns,
}) {
  if (voice.isDefault) return null;
  if (voice.isFirst) {
    return voice.isPast
        ? 'first person past tense ("I", "my", "me")'
        : 'first person present tense ("I", "my", "me")';
  }
  final tense = voice.isPast ? 'past tense' : 'present tense';
  return 'third person $tense (${pronouns.slashSet})';
}

/// PNG extension key (sibling of `front_porch`) so the stamp survives
/// save/reload without growing FrontPorchExtensions.
const kNarrativeVoiceExtensionKey = 'narrative_voice';

/// Perspective/tense/sex after params + card stamp + defaults are resolved.
class ResolvedNarrativeVoice {
  const ResolvedNarrativeVoice({
    this.perspective = 'first',
    this.tense = 'present',
    this.sex = '',
  });

  final String perspective;
  final String tense;
  final String sex;

  NarrativeVoice get voice =>
      NarrativeVoice.parse(perspective: perspective, tense: tense);
}

/// Write the Create choice onto [card] so a later Enhance can read it.
void stampNarrativeVoice(
  CharacterCard card, {
  required NarrativeVoice voice,
  required String sex,
}) {
  final raw = Map<String, dynamic>.from(card.rawExtensions ?? {});
  raw[kNarrativeVoiceExtensionKey] = {
    'perspective': voice.isFirst ? 'first' : 'third',
    'tense': voice.isPast ? 'past' : 'present',
    if (sex.trim().isNotEmpty) 'sex': sex.trim(),
  };
  card.rawExtensions = raw;
}

/// Read a stamped voice. Missing/malformed → first-person present, empty sex.
ResolvedNarrativeVoice readNarrativeVoice(CharacterCard? card) {
  final raw = card?.rawExtensions?[kNarrativeVoiceExtensionKey];
  if (raw is! Map) return const ResolvedNarrativeVoice();
  final map = Map<String, dynamic>.from(raw);
  final voice = NarrativeVoice.parse(
    perspective: map['perspective']?.toString(),
    tense: map['tense']?.toString(),
  );
  return ResolvedNarrativeVoice(
    perspective: voice.isFirst ? 'first' : 'third',
    tense: voice.isPast ? 'past' : 'present',
    sex: (map['sex']?.toString() ?? '').trim(),
  );
}

/// Params win when non-empty. Empty/omitted falls back to the card stamp,
/// then to first-person present.
ResolvedNarrativeVoice resolveEnhanceVoice({
  String? narrativePerspective,
  String? narrativeTense,
  String? sex,
  CharacterCard? source,
}) {
  final stamped = readNarrativeVoice(source);
  final p = narrativePerspective?.trim() ?? '';
  final t = narrativeTense?.trim() ?? '';
  final s = sex?.trim() ?? '';
  return ResolvedNarrativeVoice(
    perspective: p.isNotEmpty ? p : stamped.perspective,
    tense: t.isNotEmpty ? t : stamped.tense,
    sex: s.isNotEmpty ? s : stamped.sex,
  );
}

String _voicePhrase(NarrativeVoice voice, NarrativePronouns pronouns) {
  if (voice.isFirst) {
    return voice.isPast
        ? 'first person past tense: "I", "my", "me"'
        : 'first person: "I", "my", "me"';
  }
  final tense = voice.isPast ? 'past tense' : 'present tense';
  return 'third person $tense: ${pronouns.slashSet}';
}
