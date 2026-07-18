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

import 'package:front_porch_ai/models/lorebook.dart';

/// Encode as a native SillyTavern world info file: `{"entries": {"0": {…}}}`
/// with ST's exact field names. Round-trips losslessly through
/// `Lorebook.fromJson`, and old FPAI versions can still re-import it.
Map<String, dynamic> encodeStWorldInfo(
  Lorebook book, {
  String name = '',
  String description = '',
}) {
  final entries = <String, dynamic>{};
  final usedUids = <int>{};
  for (var i = 0; i < book.entries.length; i++) {
    final e = book.entries[i];
    var uid = e.uid ?? i;
    while (usedUids.contains(uid)) {
      uid++;
    }
    usedUids.add(uid);
    entries['$uid'] = _stEntry(e, uid, i);
  }
  return {
    if (name.isNotEmpty) 'name': name,
    if (description.isNotEmpty) 'description': description,
    'entries': entries,
  };
}

Map<String, dynamic> _stEntry(LorebookEntry e, int uid, int index) {
  return {
    // Unknown imported data first — known fields overwrite on collision.
    ...e.extensions,
    'uid': uid,
    'key': _stKeys(e),
    'keysecondary': e.secondaryKeys,
    'comment': e.name,
    'addMemo': e.addMemo || e.name.isNotEmpty,
    'content': e.content,
    'constant': e.constant,
    'vectorized': e.vectorized,
    'selective': e.selective,
    'selectiveLogic': e.selectiveLogic,
    'disable': !e.enabled,
    'order': e.order,
    'position': e.position,
    'role': e.role ?? 0,
    'depth': e.depth,
    'probability': e.probability,
    'useProbability': e.useProbability,
    'group': e.group,
    'groupOverride': e.groupOverride,
    'groupWeight': e.groupWeight,
    'useGroupScoring': e.useGroupScoring,
    'sticky': e.sticky,
    'cooldown': e.cooldown,
    'delay': e.delay,
    'scanDepth': e.scanDepth,
    'caseSensitive': e.caseSensitive,
    'matchWholeWords': e.matchWholeWords,
    'excludeRecursion': e.excludeRecursion,
    'preventRecursion': e.preventRecursion,
    'delayUntilRecursion':
        e.delayUntilRecursion == 0 ? false : e.delayUntilRecursion,
    'ignoreBudget': e.ignoreBudget,
    'matchPersonaDescription': e.matchPersonaDescription,
    'matchCharacterDescription': e.matchCharacterDescription,
    'matchCharacterPersonality': e.matchCharacterPersonality,
    'matchCharacterDepthPrompt': e.matchCharacterDepthPrompt,
    'matchScenario': e.matchScenario,
    'matchCreatorNotes': e.matchCreatorNotes,
    'automationId': e.automationId,
    'triggers': e.triggers,
    if (e.characterFilter != null) 'characterFilter': e.characterFilter,
    'displayIndex': e.displayIndex ?? index,
    // FPAI extra: sticky-turns; ST ignores it, FPAI re-imports it.
    'sticky_depth': e.stickyDepth,
  };
}

/// ST has no `use_regex` flag — regex keys are inline `/pattern/flags`.
/// When a V3 book marked useRegex is exported to ST form, wrap bare patterns
/// so they stay regexes.
List<String> _stKeys(LorebookEntry e) {
  if (!e.useRegex) return e.keys;
  return e.keys
      .map((k) => k.startsWith('/') && k.contains(RegExp(r'/[gimsuy]*$'))
          ? k
          : '/$k/')
      .toList();
}

/// Encode as a V2-spec `character_book` for embedding in exported cards.
/// Everything beyond the V2 base rides `entries[].extensions.*` using the
/// exact key names ST and Chub exchange (note the camelCase exceptions
/// `useProbability` and `selectiveLogic` — that is the de-facto standard).
Map<String, dynamic> encodeCharacterBook(Lorebook book) {
  return {
    'entries': [
      for (var i = 0; i < book.entries.length; i++)
        _bookEntry(book.entries[i], i),
    ],
    'name': '',
    'description': '',
    if (book.scanDepth != null) 'scan_depth': book.scanDepth,
    if (book.tokenBudget != null) 'token_budget': book.tokenBudget,
    'recursive_scanning': book.recursiveScanning ?? false,
    'extensions': book.extensions,
  };
}

Map<String, dynamic> _bookEntry(LorebookEntry e, int index) {
  return {
    'keys': e.keys,
    'secondary_keys': e.secondaryKeys,
    'selective': e.selective,
    'content': e.content,
    'enabled': e.enabled,
    'insertion_order': e.order,
    if (e.caseSensitive != null) 'case_sensitive': e.caseSensitive,
    'name': e.name,
    'comment': e.name,
    'id': e.uid ?? index,
    'constant': e.constant,
    'position': e.position == 1 ? 'after_char' : 'before_char',
    'use_regex': e.useRegex,
    'extensions': {
      ...e.extensions,
      'position': e.position,
      'exclude_recursion': e.excludeRecursion,
      'prevent_recursion': e.preventRecursion,
      'delay_until_recursion': e.delayUntilRecursion,
      'display_index': e.displayIndex ?? index,
      'probability': e.probability,
      'useProbability': e.useProbability,
      'depth': e.depth,
      'selectiveLogic': e.selectiveLogic,
      'group': e.group,
      'group_override': e.groupOverride,
      'group_weight': e.groupWeight,
      if (e.scanDepth != null) 'scan_depth': e.scanDepth,
      if (e.caseSensitive != null) 'case_sensitive': e.caseSensitive,
      if (e.matchWholeWords != null) 'match_whole_words': e.matchWholeWords,
      if (e.useGroupScoring != null) 'use_group_scoring': e.useGroupScoring,
      'automation_id': e.automationId,
      'role': e.role ?? 0,
      'vectorized': e.vectorized,
      'sticky': e.sticky,
      'cooldown': e.cooldown,
      'delay': e.delay,
      'match_persona_description': e.matchPersonaDescription,
      'match_character_description': e.matchCharacterDescription,
      'match_character_personality': e.matchCharacterPersonality,
      'match_character_depth_prompt': e.matchCharacterDepthPrompt,
      'match_scenario': e.matchScenario,
      'match_creator_notes': e.matchCreatorNotes,
      'triggers': e.triggers,
      'ignore_budget': e.ignoreBudget,
      // FPAI extra so card sharing between FPAI users keeps sticky-turns.
      'sticky_depth': e.stickyDepth,
    },
  };
}
