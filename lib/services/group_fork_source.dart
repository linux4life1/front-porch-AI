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

import 'package:flutter/foundation.dart';

import 'package:front_porch_ai/database/database.dart' hide World;
import 'package:front_porch_ai/models/group_chat.dart';
import 'package:front_porch_ai/models/world.dart';
import 'package:front_porch_ai/services/world_chain.dart';
import 'package:front_porch_ai/services/world_store/group_world_choice.dart';
import 'package:front_porch_ai/utils/group_realism_blobs.dart';

/// What the 1:1 chat a group was made from had switched on, so Edit Group
/// and web Group Settings can offer to fill in settings that groups forked
/// before the fix were saved without.
class ForkedGroupSource {
  const ForkedGroupSource({
    required this.realismOn,
    required this.needsOn,
    required this.worlds,
    this.hostName,
  });

  final bool realismOn;
  final bool needsOn;

  /// Where that chat is; null when it has no worlds.
  final GroupWorldChoice? worlds;

  /// The character the 1:1 was with; null when the card is gone.
  final String? hostName;

  /// The chat had realism on, but [group] saves no member seeds, so a new
  /// chat would start with realism off.
  bool realismMissingFrom(GroupChat group) =>
      realismOn &&
      parseGroupRealismSeeds(group.defaultMemberRealismState).isEmpty;

  /// The chat is somewhere, but [group] starts new chats nowhere.
  bool worldMissingFrom(GroupChat group) =>
      worlds != null &&
      group.worldIds.isEmpty &&
      (group.loreWorldIds?.isEmpty ?? true);

  /// Whether [group]'s settings for new chats are missing something the
  /// chat had. Inherit alone does not count: it is a choice the user can
  /// make either way, and counting it kept the notice up for good.
  bool differsFrom(GroupChat group) =>
      realismMissingFrom(group) || worldMissingFrom(group);
}

/// The first chat of [group] when the group was made from a 1:1 (its
/// parent session has no group), read as a [ForkedGroupSource]. Null for a
/// group made any other way.
Future<ForkedGroupSource?> findForkedGroupSource(
  AppDatabase db,
  GroupChat group, {
  required World? Function(String id) lookup,
}) async {
  final sessions = await db.getSessionsForGroup(group.id);
  if (sessions.isEmpty) return null;
  final first = sessions.last; // newest first
  final parentId = first.parentSession;
  if (parentId == null) return null;
  final parent = await db.getSessionById(parentId);
  if (parent == null || parent.groupId != null) return null;
  final slots = await db.getChatWorldAttachments(first.id);
  return ForkedGroupSource(
    realismOn: first.realismEnabled,
    needsOn: first.needsSimEnabled,
    worlds: groupWorldChoiceFromChat(
      primaryId: slots.primaryId,
      loreIds: slots.loreIds,
      lookup: lookup,
    ),
    hostName: await _cardName(db, parent.characterId),
  );
}

Future<String?> _cardName(AppDatabase db, String? characterId) async {
  if (characterId == null || characterId.isEmpty) return null;
  try {
    final name = (await db.getCharacterById(characterId)).name.trim();
    return name.isEmpty ? null : name;
  } catch (e) {
    // A deleted card: the notice says "a 1:1 chat" instead of a name.
    debugPrint('[groups] no card for the chat a group came from: $e');
    return null;
  }
}

/// "Hollow Creek, starting at The Mill Kitchen" for where [choice] starts
/// new chats, or just the world when it has no starred place. Null with no
/// Setting.
String? groupMeetLine(
  GroupWorldChoice choice,
  World? Function(String id) lookup,
) {
  final id = choice.settingId;
  final setting = id == null ? null : lookup(id);
  if (setting == null) return null;
  final root = topWorldOf(setting, lookup);
  final start = setting.id == root.id ? startingPlaceOf(root, lookup) : setting;
  return start.id == root.id
      ? root.name
      : '${root.name}, starting at ${start.name}';
}
