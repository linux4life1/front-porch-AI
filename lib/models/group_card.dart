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

import 'package:front_porch_ai/models/character_card.dart';

/// Portable interchange format for a group of characters exported as a single PNG.
///
/// This is the data model that gets serialized into the `fpa_group` PNG text chunk.
/// It is deliberately self-contained (full member CharacterCard objects, not ID references)
/// so that a single file can be shared and imported anywhere without requiring the
/// original character files.
///
/// This is a Front Porch innovation. SillyTavern has no equivalent single-file group
/// card format as of 2026 (see open issue #1757).
class GroupCard {
  final String name;
  final List<CharacterCard> members;

  /// Raw portable member data maps (full V2 shape as serialized by CharacterCard.toJson).
  /// This is what we use for high-fidelity import so that lorebooks, extensions,
  /// and all fields survive the roundtrip perfectly.
  final List<Map<String, dynamic>> rawMemberData;

  final String turnOrder; // 'roundRobin' or 'random'
  final bool autoAdvance;
  final bool directorMode;
  final String firstMessage;
  final String scenario;
  final String systemPrompt;

  /// Per-character system prompt overrides scoped to this group only.
  /// Keyed by stable charId. These are separate from the characters' normal
  /// card system prompts and from the group-level systemPrompt.
  ///
  /// Stored at the top level of `data` in the Group Card JSON (additive in spec v1.0).
  /// For backward compatibility, importers also check the legacy location inside
  /// `realism_state.characterSystemPrompts` / `character_system_prompts` and promote the data.
  /// See docs/characters.md for the exact v1.0 rules (no spec version bump).
  final Map<String, String> characterSystemPrompts;

  /// Group-level lorebook (JSON string, same format as character lorebooks).
  /// Takes priority over character and world lorebooks when generating prompts.
  final String? groupLorebook;

  /// Attached world IDs for this group (world lorebooks + descriptions).
  /// Prefer UUIDs (Living Worlds); older cards may still carry names here.
  final List<String> worldIds;

  /// Display names parallel to [worldIds] for legacy importers that only
  /// resolve worlds by name. Empty when unknown.
  final List<String> worldNames;

  /// Whether member character lorebooks should be inherited.
  final bool inheritCharacterLorebooks;

  /// Chaos Mode settings for the group (as they were at export time).
  final bool chaosModeEnabled;
  final bool chaosNsfwEnabled;

  /// The immutable creation-time baseline realism seed.
  /// This is what should be restored on import (not any evolved state).
  final String baselineRealismState;

  /// Portable default per-member realism/needs state for the group definition.
  /// This is the rich blob (including per-char needs vectors, 'enjoysLowHygiene',
  /// and the hidden 'relationships' map for Group Dynamics in small groups) that
  /// is used as the seed for new sessions and split-to-solo after import.
  ///
  /// Added to Group Card round-tripping to fulfill the v30+ schema contract
  /// (see database.dart table comment). Exported groups now carry the full
  /// intended starting state for the definition, not just the frozen baseline.
  final String defaultMemberRealismState;

  /// Per-member objectives snapshot at export time (for portable Group Cards).
  /// Keyed by stable charId. This allows objectives to travel with the card.
  final Map<String, List<Map<String, dynamic>>> memberObjectives;

  /// Future extension point for group-level Front Porch features
  /// (e.g. shared realism defaults, group-wide needs simulation, etc.).
  final Map<String, dynamic>? extensions;

  GroupCard({
    required this.name,
    required this.members,
    List<Map<String, dynamic>>? rawMemberData,
    required this.turnOrder,
    this.autoAdvance = false,
    this.directorMode = false,
    this.firstMessage = '',
    this.scenario = '',
    this.systemPrompt = '',
    Map<String, String>? characterSystemPrompts,
    this.groupLorebook,
    List<String>? worldIds,
    List<String>? worldNames,
    this.inheritCharacterLorebooks = true,
    this.chaosModeEnabled = false,
    this.chaosNsfwEnabled = false,
    this.baselineRealismState = '{}',
    this.defaultMemberRealismState = '{}',
    this.memberObjectives = const {},
    this.extensions,
  }) : rawMemberData = rawMemberData ?? members.map((c) => c.toJson()).toList(),
       characterSystemPrompts = characterSystemPrompts ?? {},
       worldIds = worldIds ?? [],
       worldNames = worldNames ?? [];

  Map<String, dynamic> toJson() {
    final result = <String, dynamic>{
      'name': name,
      'members': members.map((c) => c.toJson()).toList(),
      'turn_order': turnOrder,
      'auto_advance': autoAdvance,
      'director_mode': directorMode,
      'first_message': firstMessage,
      'scenario': scenario,
      'system_prompt': systemPrompt,
    };
    if (characterSystemPrompts.isNotEmpty) {
      result['character_system_prompts'] = characterSystemPrompts;
    }
    if (groupLorebook != null && groupLorebook!.isNotEmpty) {
      result['group_lorebook'] = groupLorebook;
    }
    if (worldIds.isNotEmpty) {
      result['world_ids'] = worldIds;
    }
    // Dual-ref for older importers that still bind by name (Living Worlds).
    if (worldNames.isNotEmpty) {
      result['world_names'] = worldNames;
    }
    result['inherit_character_lorebooks'] = inheritCharacterLorebooks;

    result['chaos_mode_enabled'] = chaosModeEnabled;
    result['chaos_nsfw_enabled'] = chaosNsfwEnabled;

    if (baselineRealismState.isNotEmpty && baselineRealismState != '{}') {
      result['baseline_realism_state'] = baselineRealismState;
    }

    if (defaultMemberRealismState.isNotEmpty &&
        defaultMemberRealismState != '{}') {
      result['default_member_realism_state'] = defaultMemberRealismState;
    }

    if (memberObjectives.isNotEmpty) {
      result['member_objectives'] = memberObjectives;
    }

    if (extensions != null && extensions!.isNotEmpty) {
      result['extensions'] = extensions;
      if (extensions!.containsKey('realism_state')) {
        result['realism_state'] = extensions!['realism_state'];
      }
    }

    // High-fidelity portable member data (including avatar_base64 for round-trip
    // visuals + _original_stable_id for realism relationship remapping). This is
    // what makes Group Card export include 100% of members (even avatar-less ones)
    // with fully extractable data. Written explicitly so it survives the PNG chunk.
    if (rawMemberData.isNotEmpty) {
      result['raw_member_data'] = rawMemberData;
    }

    return result;
  }

  factory GroupCard.fromJson(Map<String, dynamic> json) {
    final rawMembers = (json['members'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();

    // Prefer the high-fidelity raw_member_data (contains avatar_base64,
    // _original_stable_id, full extensions, etc.) when present. This is what
    // enables 100% member fidelity for avatar-less characters in exported groups.
    final suppliedRaw = (json['raw_member_data'] as List<dynamic>?)
        ?.whereType<Map<String, dynamic>>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
    final effectiveRaw = (suppliedRaw != null && suppliedRaw.isNotEmpty)
        ? suppliedRaw
        : rawMembers;

    final members = rawMembers.map((m) {
      final data = m['data'] is Map ? Map<String, dynamic>.from(m['data']) : m;
      return CharacterCard(
        // minimal reconstruction for display; rawMemberData is used for fidelity
        name: (data['name'] ?? data['data']?['name'] ?? 'Unknown').toString(),
        // ... other fields can remain minimal since we rely on rawMemberData
      );
    }).toList();

    Map<String, String> charPrompts = {};
    final rawPrompts = json['character_system_prompts'];
    if (rawPrompts is Map) {
      charPrompts = rawPrompts.map(
        (k, v) => MapEntry(k.toString(), (v ?? '').toString()),
      );
    }

    final worldIds =
        (json['world_ids'] as List<dynamic>?)
            ?.map((e) => e.toString())
            .toList() ??
        [];
    final worldNames =
        (json['world_names'] as List<dynamic>?)
            ?.map((e) => e.toString())
            .toList() ??
        [];

    return GroupCard(
      name: json['name'] ?? 'Group',
      members: members,
      rawMemberData: effectiveRaw,
      turnOrder: json['turn_order'] ?? 'roundRobin',
      autoAdvance: json['auto_advance'] ?? false,
      directorMode: json['director_mode'] ?? false,
      firstMessage: json['first_message'] ?? '',
      scenario: json['scenario'] ?? '',
      systemPrompt: json['system_prompt'] ?? '',
      characterSystemPrompts: charPrompts,
      groupLorebook: json['group_lorebook']?.toString(),
      worldIds: worldIds,
      worldNames: worldNames,
      inheritCharacterLorebooks: json['inherit_character_lorebooks'] ?? true,
      chaosModeEnabled: json['chaos_mode_enabled'] ?? false,
      chaosNsfwEnabled: json['chaos_nsfw_enabled'] ?? false,
      baselineRealismState: json['baseline_realism_state']?.toString() ?? '{}',
      defaultMemberRealismState:
          json['default_member_realism_state']?.toString() ?? '{}',
      memberObjectives: (json['member_objectives'] is Map)
          ? (json['member_objectives'] as Map).map(
              (k, v) => MapEntry(
                k.toString(),
                (v as List)
                    .map((e) => Map<String, dynamic>.from(e as Map))
                    .toList(),
              ),
            )
          : const {},
      extensions: json['extensions'] is Map
          ? Map<String, dynamic>.from(json['extensions'])
          : null,
    );
  }
}
