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

import 'package:front_porch_ai/models/greeting_realism_seed.dart';

/// Turn order strategies for group chats.
enum TurnOrder {
  /// Characters respond in fixed order after each user message.
  roundRobin,

  /// A random character is picked to respond after each user message.
  random,
}

/// A lightweight wrapper representing a multi-character conversation.
///
/// After the clean-break decoupling (2026-05), group membership is no longer
/// stored as characterIds referencing the singular library. The authoritative
/// list of members for a group lives in the group_members table (loaded via
/// GroupChatRepository or joined queries). GroupChat itself no longer carries
/// or manages the member ID list.
class GroupChat {
  final String id;

  /// Portable, device-independent stable id for this group (schema v34).
  ///
  /// Distinct from [id] (which is a device-local `group_<timestamp>` handle):
  /// this id travels inside the exported Group Card and is preserved on import,
  /// so a shared group can be UPDATED in place on The Stoop (no duplicate) and
  /// re-associated after switching devices — the group-level analogue of a
  /// character's stable id. Null until first generated (lazily on export via
  /// [GroupChatRepository.ensureStableId]) or carried in from an imported card.
  String? stableId;

  String name;
  TurnOrder turnOrder;
  bool autoAdvance; // auto-trigger next character after one responds
  bool directorMode; // start in director mode when entering this group
  String firstMessage; // custom group greeting (empty = use first character's)
  /// Parallel to [firstMessage], same as a character card's alternate
  /// greetings. Empty when the group has no custom opener (member greets
  /// are used instead). Stored on `defaultMemberRealismState`.
  List<String> alternateGreetings;
  List<GreetingRealismSeed?> greetingSeeds;
  String
  scenario; // group-level scenario override (empty = use first character's)
  String
  systemPrompt; // group-level system prompt override (empty = use global)

  /// Portable default realism/needs state for this group (definition-level).
  /// JSON map of charId → realism blob. Travels with Group Cards and is used
  /// as the seed when starting new group sessions or splitting members to solo.
  /// Added in v30 (clean replacement for old hidden checkpoint system).
  String defaultMemberRealismState;

  /// Immutable creation-time baseline realism/needs seed for this group definition.
  ///
  /// This is the **frozen snapshot** of per-character realism values (bond, trust, emotion,
  /// time of day, day count, etc.) that were explicitly seeded when the group was first
  /// created or imported via Group Card. It is **never mutated** by normal chat activity.
  ///
  /// Contrast with [defaultMemberRealismState], which holds the live/evolving per-character
  /// state for new sessions and can change over time.
  ///
  /// When exporting a Group Card, we deliberately export this baseline (not the evolved
  /// state) so that re-importing the card recreates the group exactly as the creator
  /// intended it at birth.
  ///
  /// Stored in its own first-class column (v31) rather than inside a JSON blob.
  String baselineRealismState;

  /// Per-character system prompt overrides that only apply inside *this* group.
  /// Keyed by the GroupMember.id (UUID) of the member inside this group.
  /// These take precedence over the member's normal `systemPrompt` (from their card)
  /// when that member speaks in this group, but sit \"under\" the group-level `systemPrompt`.
  ///
  /// Stored in its own first-class column on the groups table (v32).
  /// The previous transitional storage inside defaultMemberRealismState JSON
  /// has been fully removed (no more Path B blob merging).
  /// See docs/characters.md "Prompt Priority in Groups" for the hierarchy.
  Map<String, String> characterSystemPrompts;

  /// Worlds linked to this group (for world lorebook injection).
  List<String> worldIds;

  /// Group-level lorebook entries (JSON string, same format as Character.lorebook).
  /// Takes highest priority in prompt construction.
  String groupLorebook;

  /// Whether to inherit/append lorebooks from participating characters.
  /// When false, only group + world lorebooks are used.
  bool inheritCharacterLorebooks;

  /// Whether Chaos Mode (Chance Time) is enabled for this group.
  bool chaosModeEnabled;

  /// Whether NSFW events are included in the Chance Time pool for this group.
  bool chaosNsfwEnabled;

  GroupChat({
    required this.id,
    required this.name,
    this.stableId,
    this.turnOrder = TurnOrder.roundRobin,
    this.autoAdvance = false,
    this.directorMode = false,
    this.firstMessage = '',
    this.alternateGreetings = const [],
    this.greetingSeeds = const [],
    this.scenario = '',
    this.systemPrompt = '',
    this.defaultMemberRealismState = '{}',
    this.baselineRealismState = '{}',
    Map<String, String>? characterSystemPrompts,
    this.worldIds = const [],
    this.groupLorebook = '',
    this.inheritCharacterLorebooks = true,
    this.chaosModeEnabled = false,
    this.chaosNsfwEnabled = false,
  }) : characterSystemPrompts = characterSystemPrompts ?? {};

  /// Custom group opener + alts. Empty when the group uses a member greet.
  List<String> get allGreetings {
    final greetings = <String>[
      if (firstMessage.trim().isNotEmpty) firstMessage,
      ...alternateGreetings.where((g) => g.trim().isNotEmpty),
    ];
    return greetings;
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      if (stableId != null) 'stable_id': stableId,
      'name': name,
      // NOTE: character_ids intentionally removed (clean break 2026-05).
      // Membership now lives exclusively in the group_members table (UUID keys).
      // This toJson is primarily for debug/legacy paths; GroupCard is the
      // portable interchange that carries full member definitions.
      'turn_order': turnOrder.name,
      'auto_advance': autoAdvance,
      'director_mode': directorMode,
      'first_message': firstMessage,
      'alternate_greetings': alternateGreetings,
      'greeting_seeds': [
        for (final s in compactGreetingSeeds(greetingSeeds)) s?.toJson(),
      ],
      'scenario': scenario,
      'system_prompt': systemPrompt,
      'default_member_realism_state': defaultMemberRealismState,
      'baseline_realism_state': baselineRealismState,
      'character_system_prompts': characterSystemPrompts,
      'world_ids': worldIds,
      'group_lorebook': groupLorebook,
      'inherit_character_lorebooks': inheritCharacterLorebooks,
      'chaos_mode_enabled': chaosModeEnabled,
      'chaos_nsfw_enabled': chaosNsfwEnabled,
    };
  }

  factory GroupChat.fromJson(Map<String, dynamic> json) {
    final rawCharPrompts = json['character_system_prompts'];
    final charPrompts = (rawCharPrompts is Map)
        ? rawCharPrompts.map(
            (k, v) => MapEntry(k.toString(), (v ?? '').toString()),
          )
        : <String, String>{};

    final rawWorldIds = json['world_ids'];
    final worldIdsList = (rawWorldIds is List)
        ? rawWorldIds.map((e) => e.toString()).toList()
        : <String>[];

    final pairedOpening = compactGreetingPairs(
      greetingSlotsFromRaw(json['alternate_greetings']),
      parseGreetingSeeds(json['greeting_seeds']),
    );

    return GroupChat(
      id: json['id'] ?? '',
      stableId:
          (json['stable_id'] is String &&
              (json['stable_id'] as String).trim().isNotEmpty)
          ? (json['stable_id'] as String).trim()
          : null,
      name: json['name'] ?? 'Group Chat',
      // character_ids from legacy JSON ignored (clean break — no adoption).
      // Real members come from group_members table after load.
      turnOrder: TurnOrder.values.firstWhere(
        (e) => e.name == json['turn_order'],
        orElse: () => TurnOrder.roundRobin,
      ),
      autoAdvance: json['auto_advance'] ?? false,
      directorMode: json['director_mode'] ?? false,
      firstMessage: json['first_message'] ?? '',
      alternateGreetings: pairedOpening.greetings,
      greetingSeeds: pairedOpening.seeds,
      scenario: json['scenario'] ?? '',
      systemPrompt: json['system_prompt'] ?? '',
      defaultMemberRealismState: json['default_member_realism_state'] ?? '{}',
      baselineRealismState: json['baseline_realism_state'] ?? '{}',
      characterSystemPrompts: charPrompts,
      worldIds: worldIdsList,
      groupLorebook: json['group_lorebook'] ?? '',
      inheritCharacterLorebooks: json['inherit_character_lorebooks'] ?? true,
      chaosModeEnabled: json['chaos_mode_enabled'] ?? false,
      chaosNsfwEnabled: json['chaos_nsfw_enabled'] ?? false,
    );
  }
}
