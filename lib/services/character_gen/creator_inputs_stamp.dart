// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/chargen/chargen.dart';
import 'package:front_porch_ai/services/character_gen/gen_run_inputs.dart';

/// Where a character made by AI Create (desktop or web) keeps what it was
/// asked for that its greeting recipe does not carry (the concept, the lore categories and
/// depth, the wizard mode, the interview questions), so a lorebook rewrite
/// or the Profile step after a restart asks the same way. Beside the
/// recipe's own key; additive.
const kCreatorInputsExtensionKey = 'creator_inputs';

const _stampConceptChars = 4000;

/// Write [inputs] and [mode] onto [card] (see [kCreatorInputsExtensionKey]).
/// The questions are written only when the run had its own list.
void stampCreatorInputs(CharacterCard card, GenRunInputs inputs, String mode) {
  final raw = Map<String, dynamic>.from(card.rawExtensions ?? {});
  final concept = inputs.concept;
  final questions = inputs.interviewQuestions;
  raw[kCreatorInputsExtensionKey] = {
    'concept': concept.length > _stampConceptChars
        ? concept.substring(0, _stampConceptChars)
        : concept,
    'loreCategories': inputs.loreCategories,
    'loreDepth': inputs.loreDepth,
    if (mode.isNotEmpty) 'mode': mode,
    if (questions != null)
      'interviewQuestions': InterviewQuestion.listToJson(questions),
  };
  card.rawExtensions = raw;
}

/// What a saved character was asked for, read back from its stamp; null
/// when it carries none. `interviewQuestions` is null when the run asked
/// the standard set.
({
  String concept,
  List<String> loreCategories,
  String loreDepth,
  String mode,
  List<InterviewQuestion>? interviewQuestions,
})?
readCreatorInputs(CharacterCard? card) {
  final raw = card?.rawExtensions?[kCreatorInputsExtensionKey];
  if (raw is! Map) return null;
  String text(String k) => raw[k] is String ? raw[k] as String : '';
  final depth = text('loreDepth');
  return (
    concept: text('concept'),
    loreCategories: [
      if (raw['loreCategories'] is List)
        for (final c in raw['loreCategories'] as List)
          if (c is String && c.trim().isNotEmpty) c,
    ],
    loreDepth: depth.isEmpty ? 'Standard' : depth,
    mode: text('mode'),
    interviewQuestions: InterviewQuestion.listFromJson(
      raw['interviewQuestions'],
    ),
  );
}

/// Whether [card]'s stamp shows its run asked at least one unconditional
/// question. A card with no stamp, or one that never pinned its list,
/// reads as interviewed: only a stamped empty (or conditional-only) list
/// says the interview was skipped.
bool stampHadInterview(CharacterCard? card) {
  final qs = readCreatorInputs(card)?.interviewQuestions;
  if (qs == null) return true;
  return qs.any(
    (q) => !q.isConditional && (q.text?.trim().isNotEmpty ?? q.isStandard),
  );
}
