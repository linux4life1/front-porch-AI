// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/foundation.dart';
import 'package:front_porch_ai/services/character_gen/gen_llm_caller.dart';
import 'package:front_porch_ai/services/character_gen/gen_run_state.dart';
import 'package:front_porch_ai/services/chargen/chargen.dart';
import 'package:front_porch_ai/services/llm_service.dart';

/// The identity facts pass: one structured call that reads the profile and
/// the whole interview for the Front Porch fields (birthday, work, opening
/// task and stance, lists, creator notes). Tools first when the backend
/// speaks them; text JSON is the floor (the Porch Life transport).
class GenIdentityFacts {
  GenIdentityFacts(this._state, this._llm);

  final GenRunState _state;
  final GenLlmCaller _llm;

  /// Null when the model answered nothing usable; the card keeps its
  /// fields and every one stays editable.
  Future<IdentityFacts?> read({
    required String name,
    required String age,
    required String sex,
    required String relationship,
    required String description,
    required String personality,
    required String scenario,
    required String interviewTranscript,
    required bool nsfwEnabled,
    void Function(String)? onProgress,
  }) async {
    final prompt = _prompt(
      name: name,
      age: age,
      sex: sex,
      relationship: relationship,
      description: description,
      personality: personality,
      scenario: scenario,
      interviewTranscript: interviewTranscript,
      nsfwEnabled: nsfwEnabled,
    );
    Object? raw;
    try {
      final resp = await _state.llm.generateWithTools(
        GenerationParams(
          prompt: prompt,
          maxLength: 768,
          minLength: 16,
          temperature: 0.5,
          reasoningEnabled: false,
          reasoningMaxTokens: 0,
          mandatoryReasoningHeadroom: true,
          toolChoice: kIdentityFactsToolName,
        ),
        identityFactsToolSchema(nsfw: nsfwEnabled),
      );
      for (final call in resp?.calls ?? const <LlmToolCall>[]) {
        if (call.name == kIdentityFactsToolName) {
          raw = Map<String, dynamic>.from(call.arguments);
          break;
        }
      }
    } catch (e) {
      debugPrint('CharacterGen: identity facts tools miss ($e) — text floor');
    }
    raw ??= await _llm.call(
      prompt,
      maxLen: 1024,
      minLen: 16,
      isJsonMode: true,
      onProgress: onProgress,
    );
    if (raw == null) return null;
    final facts = parseIdentityFacts(
      raw,
      nsfw: nsfwEnabled,
      age: age,
      relationship: relationship,
      name: name,
    );
    debugPrint(
      'CharacterGen: identity facts read birthday=${facts.birthday} '
      'job=${facts.occupation} warmth=${facts.warmth} '
      'ambitions=${facts.ambitions.length} likes=${facts.likes.length}',
    );
    return facts.isEmpty ? null : facts;
  }

  String _prompt({
    required String name,
    required String age,
    required String sex,
    required String relationship,
    required String description,
    required String personality,
    required String scenario,
    required String interviewTranscript,
    required bool nsfwEnabled,
  }) {
    final ageLine = age.trim().isEmpty ? 'not given' : age.trim();
    final rel = hasRelationshipToUser(relationship)
        ? relationship.trim()
        : 'none (they have not met)';
    final yearLine = age.trim().isEmpty
        ? '- "birth_year": a year of birth that fits the profile\n'
        : '';
    final intimate = nsfwEnabled
        ? '- "intimate_into": 2-5 short suggestive tastes for 18+ scenes\n'
              '- "intimate_not_into": 2-4 hard limits / not interested\n'
        : 'Do NOT emit intimate_into or intimate_not_into.\n';
    return '''Read the facts this character profile implies for $name. Output ONLY a JSON object.
No markdown. No explanation.

FORM:
Age: $ageLine
Sex: ${sex.trim().isEmpty ? 'not given' : sex.trim()}
Relationship to {{user}}: $rel

DESCRIPTION:
$description

PERSONALITY:
$personality

SCENARIO (the opening situation):
$scenario

INTERVIEW (their own words):
${capInterview(interviewTranscript)}

Keys:
- "birthday_month": 1-12 and "birthday_day": 1-31, your choice (the year comes from the age)
$yearLine- "occupation": their job, or "" when the profile implies none. Never invent a job
- "occupation_brief": one sentence on what that work is like ("" without a job)
- "hours": their usual working hours, 24-hour "HH:MM-HH:MM" ("" without a job)
- "work_days": the days they work, 1 = Monday ... 7 = Sunday
- "current_task": what they are doing or after as the story opens, one sentence in their own voice
- "relationship_warmth": how they stand with {{user}} as it opens: strangers, warm, guarded or cold
- "ambitions": 2-4 long-term goals across the whole story, not today's to-do
- "plan_lines": 2-4 short sentences on how they mean to get there
- "likes": 3-6 small specific things they warm to
- "dislikes": 2-4 things that make them bristle
$intimate- "creator_notes": a two or three sentence pitch for this character, for someone browsing cards. No real people's names
Rules: lists are short phrases, one thing per string. Nothing about {{user}}'s belongings or choices.

Respond with ONLY the JSON:''';
  }
}
