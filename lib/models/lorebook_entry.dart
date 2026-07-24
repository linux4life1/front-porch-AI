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

import 'dart:convert';

/// SillyTavern selective-logic modes for secondary keys.
/// Numeric codes match ST's `world_info_logic` exactly.
class SelectiveLogic {
  static const int andAny = 0; // primary + at least one secondary
  static const int notAll = 1; // primary + at least one secondary absent
  static const int notAny = 2; // primary + zero secondaries present
  static const int andAll = 3; // primary + all secondaries present
}

/// A single lorebook entry carrying the full SillyTavern World Info field set.
///
/// Storage is the app's internal JSON blob shape (snake_case, additive — old
/// app versions keep reading blobs written by this class). [fromJson] is the
/// single tolerant decoder for FPAI-internal, ST world info, and V2/V3
/// character_book entry shapes, including the ST card `extensions.*` mapping.
/// Unknown fields are preserved in [extensions] so imports round-trip.
///
/// Runtime-honored fields (verified 2026-07 against `lib/services/chat/`
/// `lorebook_scanner`/`matcher`/`injector`/`timed_effects`): keys + secondary
/// logic, `probability`, regex keys, case/whole-word overrides, `constant`,
/// insertion `order`, `position` (0-6; 7 degrades to before-char), `depth`/@depth,
/// inclusion groups (`group`/`groupWeight`/`useGroupScoring`/`groupOverride`),
/// recursion (`excludeRecursion`/`preventRecursion`/`delayUntilRecursion`),
/// timed effects (`sticky`/`cooldown`/`delay`), and token-budget/`ignoreBudget`.
/// Still stored-only (not yet honored by the engine): `vectorized` (keyword-only
/// matching — no embedding path), the extra scan-source flags
/// (`matchScenario`/`matchCharacterDescription`/…), `role` on @depth entries in
/// text-completion mode, and legacy [stickyDepth].
class LorebookEntry {
  String name;
  List<String> keys;
  List<String> secondaryKeys;
  String content;
  bool enabled;
  bool constant;

  /// Legacy Front Porch sticky-turns: how many turns the entry stays active
  /// after triggering. Distinct from ST's [sticky] timed effect.
  int stickyDepth;

  bool selective;
  int selectiveLogic;
  int order;
  int position;
  int depth;
  int? role;
  int probability;
  bool useProbability;
  String group;
  bool groupOverride;
  int groupWeight;
  bool? useGroupScoring;
  int sticky;
  int cooldown;
  int delay;
  int? scanDepth;
  bool? caseSensitive;
  bool? matchWholeWords;
  bool useRegex;
  bool excludeRecursion;
  bool preventRecursion;
  int delayUntilRecursion;
  bool ignoreBudget;
  bool vectorized;
  bool addMemo;
  bool matchPersonaDescription;
  bool matchCharacterDescription;
  bool matchCharacterPersonality;
  bool matchCharacterDepthPrompt;
  bool matchScenario;
  bool matchCreatorNotes;
  String automationId;
  List<String> triggers;
  Map<String, dynamic>? characterFilter;
  int? displayIndex;
  int? uid;

  /// Unknown/unmodeled fields preserved for lossless round-trip (V2 spec
  /// requires keeping foreign `extensions` data intact).
  Map<String, dynamic> extensions;

  bool isTriggered; // Runtime state for UI indication
  int remainingDepth; // Runtime counter

  /// Runtime: how many keys (primary + secondary) matched on the last
  /// successful scan — inclusion-group scoring reads it. Never serialized.
  int lastMatchScore = 0;

  LorebookEntry({
    String? key,
    List<String>? keys,
    List<String>? secondaryKeys,
    this.name = '',
    this.content = '',
    this.enabled = true,
    this.constant = false,
    this.stickyDepth = 1,
    this.selective = true,
    this.selectiveLogic = SelectiveLogic.andAny,
    this.order = 100,
    this.position = 0,
    this.depth = 4,
    this.role,
    this.probability = 100,
    this.useProbability = true,
    this.group = '',
    this.groupOverride = false,
    this.groupWeight = 100,
    this.useGroupScoring,
    this.sticky = 0,
    this.cooldown = 0,
    this.delay = 0,
    this.scanDepth,
    this.caseSensitive,
    this.matchWholeWords,
    this.useRegex = false,
    this.excludeRecursion = false,
    this.preventRecursion = false,
    this.delayUntilRecursion = 0,
    this.ignoreBudget = false,
    this.vectorized = false,
    this.addMemo = false,
    this.matchPersonaDescription = false,
    this.matchCharacterDescription = false,
    this.matchCharacterPersonality = false,
    this.matchCharacterDepthPrompt = false,
    this.matchScenario = false,
    this.matchCreatorNotes = false,
    this.automationId = '',
    List<String>? triggers,
    this.characterFilter,
    this.displayIndex,
    this.uid,
    Map<String, dynamic>? extensions,
    this.isTriggered = false,
    this.remainingDepth = 0,
  })  : keys = keys ?? (key != null ? parseKeyList(key) : <String>[]),
        secondaryKeys = secondaryKeys ?? <String>[],
        triggers = triggers ?? <String>[],
        extensions = extensions ?? <String, dynamic>{};

  /// Compat surface for the many read sites (editor prefill, chips, token
  /// estimates) that treat keys as one comma-separated string.
  String get key => keys.join(', ');

  /// Display label: name if available, otherwise key, otherwise 'Unnamed Entry'
  String get displayName {
    if (name.isNotEmpty) return name;
    if (key.isNotEmpty) return key;
    return 'Unnamed Entry';
  }

  /// Content with V3 decorator lines (`@@…`) removed — decorators are
  /// directives for the engine, never prose for the model. Stored content
  /// keeps them so exports round-trip byte-identical.
  String get injectableContent {
    if (!content.contains('@@')) return content;
    return content
        .split('\n')
        .where((line) => !line.trimLeft().startsWith('@@'))
        .join('\n')
        .trim();
  }

  static final RegExp _completeRegexKey = RegExp(r'^/(.+)/[gimsuy]*$');

  /// Split a comma-separated key string, keeping `/regex/flags` keys atomic
  /// even when the pattern itself contains commas (e.g. `/a{1,2}/i`).
  static List<String> parseKeyList(String raw) {
    final out = <String>[];
    var pending = '';
    for (final part in raw.split(',')) {
      final candidate = pending.isEmpty ? part : '$pending,$part';
      final trimmed = candidate.trim();
      if (trimmed.startsWith('/') && !_completeRegexKey.hasMatch(trimmed)) {
        pending = candidate;
        continue;
      }
      pending = '';
      if (trimmed.isNotEmpty) out.add(trimmed);
    }
    final rest = pending.trim();
    if (rest.isNotEmpty) out.add(rest);
    return out;
  }

  static List<String> _stringList(dynamic value) {
    if (value is List) {
      return value
          .where((v) => v != null)
          .map((v) => v.toString().trim())
          .where((s) => s.isNotEmpty)
          .toList();
    }
    if (value is String && value.trim().isNotEmpty) {
      return parseKeyList(value);
    }
    return <String>[];
  }

  static int _int(dynamic v, int fallback) =>
      v is int ? v : (v is num ? v.toInt() : fallback);
  static int? _intOrNull(dynamic v) =>
      v is int ? v : (v is num ? v.toInt() : null);
  static bool _bool(dynamic v, bool fallback) => v is bool ? v : fallback;
  static bool? _boolOrNull(dynamic v) => v is bool ? v : null;

  /// Every top-level JSON key fromJson understands (both snake and camel
  /// spellings). Anything else is preserved into [extensions].
  static const Set<String> _knownTopLevelKeys = {
    'name', 'comment', 'keys', 'key', 'secondary_keys', 'keysecondary',
    'content', 'enabled', 'disable', 'constant', 'sticky_depth',
    'selective', 'selectiveLogic', 'selective_logic',
    'order', 'insertion_order', 'position', 'depth', 'role',
    'probability', 'useProbability', 'use_probability',
    'group', 'groupOverride', 'group_override',
    'groupWeight', 'group_weight', 'useGroupScoring', 'use_group_scoring',
    'sticky', 'cooldown', 'delay',
    'scanDepth', 'scan_depth', 'caseSensitive', 'case_sensitive',
    'matchWholeWords', 'match_whole_words', 'use_regex', 'useRegex',
    'excludeRecursion', 'exclude_recursion',
    'preventRecursion', 'prevent_recursion',
    'delayUntilRecursion', 'delay_until_recursion',
    'ignoreBudget', 'ignore_budget', 'vectorized', 'addMemo', 'add_memo',
    'matchPersonaDescription', 'match_persona_description',
    'matchCharacterDescription', 'match_character_description',
    'matchCharacterPersonality', 'match_character_personality',
    'matchCharacterDepthPrompt', 'match_character_depth_prompt',
    'matchScenario', 'match_scenario',
    'matchCreatorNotes', 'match_creator_notes',
    'automationId', 'automation_id', 'triggers',
    'characterFilter', 'character_filter',
    'displayIndex', 'display_index', 'uid', 'id', 'extensions',
  };

  /// Tolerant decoder for FPAI-internal blobs, ST world info entries, and
  /// V2/V3 character_book entries (with the ST card `extensions.*` mapping).
  /// Secondary keys stay separate; nothing is coerced into [stickyDepth].
  factory LorebookEntry.fromJson(Map<String, dynamic> json) {
    final ext = json['extensions'] is Map
        ? Map<String, dynamic>.from(json['extensions'] as Map)
        : <String, dynamic>{};
    // Reads a value by priority: top-level candidates first, then card
    // extensions candidates (removing consumed extension keys so only
    // genuinely unknown data remains preserved).
    dynamic pick(List<String> topKeys, [List<String> extKeys = const []]) {
      for (final k in topKeys) {
        if (json.containsKey(k) && json[k] != null) return json[k];
      }
      for (final k in extKeys) {
        if (ext.containsKey(k)) return ext.remove(k);
      }
      return null;
    }

    // Keys: keys[] > key (list, or string via parseKeyList). NEVER merged
    // with secondary keys — that was the old importer's corruption bug.
    final primary = _stringList(pick(['keys']) ?? pick(['key']));
    final secondary =
        _stringList(pick(['secondary_keys']) ?? pick(['keysecondary']));

    bool enabled = true;
    final enabledRaw = pick(['enabled']);
    final disableRaw = pick(['disable']);
    if (enabledRaw != null) {
      enabled = enabledRaw == true;
    } else if (disableRaw != null) {
      enabled = disableRaw != true;
    }

    // ST world info stores position as int; V2 cards as a string with the
    // numeric truth (0-7) riding extensions.position — the numeric wins.
    final extPos = ext.remove('position');
    final topPos = json['position'];
    int position = 0;
    if (extPos is int) {
      position = extPos;
    } else if (topPos is int) {
      position = topPos;
    } else if (topPos is String) {
      position = topPos == 'after_char' ? 1 : 0;
    }

    // delayUntilRecursion: ST legacy `true` ≡ level 1; numbers are levels.
    final durRaw = pick(['delay_until_recursion', 'delayUntilRecursion'],
        ['delay_until_recursion']);
    final delayUntilRecursion = durRaw is bool ? (durRaw ? 1 : 0) : _int(durRaw, 0);

    final uidRaw = pick(['uid']) ?? pick(['id']);
    final uid = _intOrNull(uidRaw);
    if (uidRaw != null && uid == null) ext['id'] = uidRaw; // V3 string ids

    final filterRaw = pick(['characterFilter', 'character_filter']);
    final triggersRaw = pick(['triggers'], ['triggers']);
    final stickyDepth = _int(pick(['sticky_depth'], ['sticky_depth']), 1);

    // Preserve any top-level key we don't model (ST world info entries carry
    // everything top-level, and ST keeps adding fields) so nothing is lost on
    // round-trip. Runtime-only ST junk is skipped.
    for (final k in json.keys) {
      if (json[k] == null) continue;
      if (_knownTopLevelKeys.contains(k) || k == 'hash' || k == 'world') {
        continue;
      }
      ext.putIfAbsent(k, () => json[k]);
    }

    return LorebookEntry(
      name: pick(['name'])?.toString() ?? pick(['comment'])?.toString() ?? '',
      keys: primary,
      secondaryKeys: secondary,
      content: pick(['content'])?.toString() ?? '',
      enabled: enabled,
      constant: pick(['constant']) == true,
      stickyDepth: stickyDepth > 0 ? stickyDepth : 1,
      selective: _bool(pick(['selective']), true),
      selectiveLogic:
          _int(pick(['selectiveLogic', 'selective_logic'], ['selectiveLogic']), 0),
      order: _int(pick(['order', 'insertion_order']), 100),
      position: position,
      depth: _int(pick(['depth'], ['depth']), 4),
      role: _intOrNull(pick(['role'], ['role'])),
      probability: _int(pick(['probability'], ['probability']), 100),
      useProbability:
          _bool(pick(['useProbability', 'use_probability'], ['useProbability']), true),
      group: pick(['group'], ['group'])?.toString() ?? '',
      groupOverride:
          _bool(pick(['groupOverride', 'group_override'], ['group_override']), false),
      groupWeight:
          _int(pick(['groupWeight', 'group_weight'], ['group_weight']), 100),
      useGroupScoring: _boolOrNull(
          pick(['useGroupScoring', 'use_group_scoring'], ['use_group_scoring'])),
      sticky: _int(pick(['sticky'], ['sticky']), 0),
      cooldown: _int(pick(['cooldown'], ['cooldown']), 0),
      delay: _int(pick(['delay'], ['delay']), 0),
      scanDepth: _intOrNull(pick(['scanDepth', 'scan_depth'], ['scan_depth'])),
      caseSensitive: _boolOrNull(
          pick(['caseSensitive', 'case_sensitive'], ['case_sensitive'])),
      matchWholeWords: _boolOrNull(
          pick(['matchWholeWords', 'match_whole_words'], ['match_whole_words'])),
      useRegex: _bool(pick(['use_regex', 'useRegex']), false),
      excludeRecursion: _bool(
          pick(['excludeRecursion', 'exclude_recursion'], ['exclude_recursion']),
          false),
      preventRecursion: _bool(
          pick(['preventRecursion', 'prevent_recursion'], ['prevent_recursion']),
          false),
      delayUntilRecursion: delayUntilRecursion,
      ignoreBudget:
          _bool(pick(['ignoreBudget', 'ignore_budget'], ['ignore_budget']), false),
      vectorized: _bool(pick(['vectorized'], ['vectorized']), false),
      addMemo: _bool(pick(['addMemo', 'add_memo']), false),
      matchPersonaDescription: _bool(
          pick(['matchPersonaDescription', 'match_persona_description'],
              ['match_persona_description']),
          false),
      matchCharacterDescription: _bool(
          pick(['matchCharacterDescription', 'match_character_description'],
              ['match_character_description']),
          false),
      matchCharacterPersonality: _bool(
          pick(['matchCharacterPersonality', 'match_character_personality'],
              ['match_character_personality']),
          false),
      matchCharacterDepthPrompt: _bool(
          pick(['matchCharacterDepthPrompt', 'match_character_depth_prompt'],
              ['match_character_depth_prompt']),
          false),
      matchScenario: _bool(
          pick(['matchScenario', 'match_scenario'], ['match_scenario']), false),
      matchCreatorNotes: _bool(
          pick(['matchCreatorNotes', 'match_creator_notes'],
              ['match_creator_notes']),
          false),
      automationId:
          pick(['automationId', 'automation_id'], ['automation_id'])?.toString() ??
              '',
      triggers: triggersRaw is List
          ? triggersRaw.map((t) => t.toString()).toList()
          : <String>[],
      characterFilter: filterRaw is Map
          ? Map<String, dynamic>.from(filterRaw)
          : null,
      displayIndex:
          _intOrNull(pick(['displayIndex', 'display_index'], ['display_index'])),
      uid: uid,
      extensions: ext,
    );
  }

  /// Internal FPAI blob shape (snake_case, additive). Old app versions read
  /// `keys[]` first, so blobs written here stay backward-readable.
  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'keys': keys,
      'secondary_keys': secondaryKeys,
      'content': content,
      'enabled': enabled,
      'constant': constant,
      'sticky_depth': stickyDepth,
      'selective': selective,
      'selective_logic': selectiveLogic,
      'order': order,
      'position': position,
      'depth': depth,
      if (role != null) 'role': role,
      'probability': probability,
      'use_probability': useProbability,
      'group': group,
      'group_override': groupOverride,
      'group_weight': groupWeight,
      if (useGroupScoring != null) 'use_group_scoring': useGroupScoring,
      'sticky': sticky,
      'cooldown': cooldown,
      'delay': delay,
      if (scanDepth != null) 'scan_depth': scanDepth,
      if (caseSensitive != null) 'case_sensitive': caseSensitive,
      if (matchWholeWords != null) 'match_whole_words': matchWholeWords,
      'use_regex': useRegex,
      'exclude_recursion': excludeRecursion,
      'prevent_recursion': preventRecursion,
      'delay_until_recursion': delayUntilRecursion,
      'ignore_budget': ignoreBudget,
      'vectorized': vectorized,
      'add_memo': addMemo,
      'match_persona_description': matchPersonaDescription,
      'match_character_description': matchCharacterDescription,
      'match_character_personality': matchCharacterPersonality,
      'match_character_depth_prompt': matchCharacterDepthPrompt,
      'match_scenario': matchScenario,
      'match_creator_notes': matchCreatorNotes,
      'automation_id': automationId,
      'triggers': triggers,
      if (characterFilter != null) 'character_filter': characterFilter,
      if (displayIndex != null) 'display_index': displayIndex,
      if (uid != null) 'uid': uid,
      'extensions': extensions,
    };
  }

  /// Deep copy carrying every field — the entry editor clones, overwrites the
  /// simple fields, and returns, so advanced/imported data survives edits.
  LorebookEntry clone() {
    final copy = LorebookEntry.fromJson(
      jsonDecode(jsonEncode(toJson())) as Map<String, dynamic>,
    );
    copy.isTriggered = isTriggered;
    copy.remainingDepth = remainingDepth;
    return copy;
  }
}
