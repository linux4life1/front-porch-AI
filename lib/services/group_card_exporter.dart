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
import 'dart:io';

import 'package:path/path.dart' as p;

import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/models/character_card.dart';
import 'package:front_porch_ai/models/group_card.dart';
import 'package:front_porch_ai/models/group_chat.dart';
import 'package:front_porch_ai/services/group_card_service.dart';
import 'package:front_porch_ai/services/group_chat_repository.dart';
import 'package:front_porch_ai/services/storage_service.dart';
import 'package:front_porch_ai/services/v2_card_service.dart';
import 'package:front_porch_ai/utils/character_id.dart';

/// Builds a portable Front Porch Group Card (the `fpa_group` PNG) for a group
/// chat with zero-compromise member fidelity.
///
/// This is the single source of truth for the group-export snapshot logic that
/// used to live inline in `home_page._exportGroup`. The desktop UI and the web
/// library facade both call it so the two paths can never diverge (every member
/// is always embedded — real avatar or a synthesized full-V2 placeholder — plus
/// per-member objectives and the stable-id remap keys an importer needs).
class GroupCardExporter {
  GroupCardExporter(this._groups, this._storage, this._db);

  final GroupChatRepository _groups;
  final StorageService _storage;
  final AppDatabase _db;

  /// Assemble the portable [GroupCard] for [group]. Returns null when the group
  /// has no members (nothing to export). All members are included with embedded
  /// avatar bytes (real or synthesized) for perfect round-trip fidelity.
  Future<GroupCard?> buildGroupCard(GroupChat group) async {
    final members = await _groups.getMembersForGroup(group.id);
    if (members.isEmpty) return null;

    // Always produce a CharacterCard for 100% of members (resolve the private
    // avatar path when the file exists; '' otherwise — downstream tolerates it).
    final memberCards = <CharacterCard>[];
    for (final m in members) {
      String? resolvedPath;
      if (m.avatarFilename != null) {
        final candidate = p.join(
          _storage.groupsDir.path,
          group.id,
          'avatars',
          m.avatarFilename!,
        );
        if (await File(candidate).exists()) resolvedPath = candidate;
      }
      memberCards.add(m.toCharacterCard(resolvedImagePath: resolvedPath ?? ''));
    }

    // Snapshot per-character objectives so they travel with the card.
    final memberObjectives = <String, List<Map<String, dynamic>>>{};
    try {
      for (final card in memberCards) {
        final charId = card.stableGroupId;
        final objs = await _db.getObjectivesForCharacter(charId);
        if (objs.isNotEmpty) {
          memberObjectives[charId] = objs
              .map(
                (o) => {
                  'objective': o.objective,
                  'tasks': o.tasks,
                  'isPrimary': o.isPrimary,
                  'active': o.active,
                  'checkFrequency': o.checkFrequency,
                  'injectionDepth': o.injectionDepth,
                },
              )
              .toList();
        }
      }
    } catch (_) {
      // Best-effort objectives snapshot.
    }

    // Embed current avatar images (or synthesize full placeholder PNGs with
    // complete V2 metadata) as base64 for perfect roundtrip fidelity. Every
    // member gets an avatar_base64 + an _original_stable_id (file basename when a
    // real avatar existed, else the group_members UUID) so realism relationships,
    // objectives, prompts etc. remap correctly even for avatar-less members.
    final rawMembersWithAvatars = <Map<String, dynamic>>[];
    for (var i = 0; i < memberCards.length; i++) {
      final card = memberCards[i];
      final m = members[i];
      final raw = Map<String, dynamic>.from(card.toJson());

      String? stableIdForRemap;
      var hasRealAvatar = false;
      if (card.imagePath != null && card.imagePath!.isNotEmpty) {
        try {
          stableIdForRemap = p.basenameWithoutExtension(card.imagePath!);
          final imageFile = File(card.imagePath!);
          if (await imageFile.exists()) {
            raw['avatar_base64'] = base64Encode(await imageFile.readAsBytes());
            hasRealAvatar = true;
          }
        } catch (_) {
          // Best effort — don't fail the whole export over one avatar.
        }
      }

      if (!hasRealAvatar) {
        try {
          final bytes = await V2CardService().encodeCharacterCardToPngBytes(
            card,
            null,
          );
          raw['avatar_base64'] = base64Encode(bytes);
        } catch (_) {
          // Textual data still travels; the import side has its own fallback.
        }
        stableIdForRemap ??= m.id;
      }

      if (stableIdForRemap != null && stableIdForRemap.isNotEmpty) {
        raw['_original_stable_id'] = stableIdForRemap;
      }

      // Portable library origin (distinct from _original_stable_id, which is the
      // realism-remap instance id) so a re-import can reconnect to the source.
      final originLibStableId = m.originStableId;
      if (originLibStableId != null && originLibStableId.isNotEmpty) {
        raw['_origin_library_stable_id'] = originLibStableId;
      }

      rawMembersWithAvatars.add(raw);
    }

    // For the realism snapshot we send the immutable baseline seed, not the
    // evolved state from chatting.
    return GroupCard(
      name: group.name,
      members: memberCards,
      rawMemberData: rawMembersWithAvatars,
      turnOrder: group.turnOrder.name,
      autoAdvance: group.autoAdvance,
      directorMode: group.directorMode,
      firstMessage: group.firstMessage,
      scenario: group.scenario,
      systemPrompt: group.systemPrompt,
      characterSystemPrompts: group.characterSystemPrompts,
      chaosModeEnabled: group.chaosModeEnabled,
      chaosNsfwEnabled: group.chaosNsfwEnabled,
      groupLorebook: group.groupLorebook,
      worldIds: group.worldIds,
      inheritCharacterLorebooks: group.inheritCharacterLorebooks,
      baselineRealismState: group.baselineRealismState,
      defaultMemberRealismState: group.defaultMemberRealismState,
      memberObjectives: memberObjectives,
      extensions: _buildExtensions(group),
    );
  }

  /// Build + write the group card PNG to [outputPath]. Returns false when the
  /// group has no members. No custom source image → an auto-collage is generated
  /// from the member avatars (the magic path).
  Future<bool> exportToFile(GroupChat group, String outputPath) async {
    final card = await buildGroupCard(group);
    if (card == null) return false;
    await GroupCardService().saveGroupCardAsPng(card, outputPath);
    return true;
  }

  /// The legacy/extra realism-state extension blob carried on the card so older
  /// external readers can still find a `realism_state`.
  Map<String, dynamic>? _buildExtensions(GroupChat group) {
    final hasBaseline =
        group.baselineRealismState.isNotEmpty &&
        group.baselineRealismState != '{}';
    final hasDefault =
        group.defaultMemberRealismState.isNotEmpty &&
        group.defaultMemberRealismState != '{}';
    if (hasBaseline) {
      return {
        'realism_state': jsonDecode(group.baselineRealismState),
        if (hasDefault)
          'default_member_realism_state': jsonDecode(
            group.defaultMemberRealismState,
          ),
      };
    }
    if (hasDefault) {
      return {
        'default_member_realism_state': jsonDecode(
          group.defaultMemberRealismState,
        ),
      };
    }
    return null;
  }
}
