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

import 'package:drift/drift.dart' as drift;
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;
import 'package:uuid/uuid.dart';

import 'package:front_porch_ai/database/database.dart' hide AvatarImage, World;
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/chat/chat.dart';
import 'package:front_porch_ai/services/character_repository.dart';
import 'package:front_porch_ai/utils/utils.dart';

/// Creates a group member (decoupled model): copies the character's avatar
/// into the group's private storage and inserts a group_members row. The one
/// writer behind a live add in a chat (GroupRoster.addCharacterToGroup), the
/// 1:1 fork, and Edit group's "+ Add a character" when the chat is closed.
Future<String> insertGroupMemberRow({
  required AppDatabase db,
  required Directory groupsDir,
  required CharacterRepository characters,
  required String groupId,
  required CharacterCard character,
  bool asLite = false,
}) async {
  final mid = const Uuid().v4();
  final avDir = Directory(path.join(groupsDir.path, groupId, 'avatars'));
  await avDir.create(recursive: true);

  await characters.duplicateCharacter(
    character,
    targetDirOverride: avDir.path,
    forcedBasename: mid,
    skipLibraryInsert: true,
  );

  await db.insertGroupMember(
    GroupMembersCompanion(
      id: drift.Value(mid),
      groupId: drift.Value(groupId),
      name: drift.Value(character.name),
      description: drift.Value(character.description),
      personality: drift.Value(character.personality),
      scenario: drift.Value(character.scenario),
      firstMessage: drift.Value(character.firstMessage),
      mesExample: drift.Value(character.mesExample),
      systemPrompt: drift.Value(character.systemPrompt),
      postHistoryInstructions: drift.Value(character.postHistoryInstructions),
      alternateGreetings: drift.Value(jsonEncode(character.alternateGreetings)),
      tags: drift.Value(jsonEncode(character.tags)),
      avatarFilename: drift.Value('$mid.png'),
      ttsVoice: drift.Value(character.ttsVoice),
      lorebook: drift.Value(
        character.lorebook != null
            ? jsonEncode(character.lorebook!.toJson())
            : null,
      ),
      worldNames: drift.Value(jsonEncode(character.allWorldNames)),
      frontPorchExtensions: drift.Value(
        encodeMemberFrontPorch(
          joiningMemberFrontPorch(
            asLite
                ? cloneFrontPorchTier(
                    character.frontPorchExtensions,
                    lite: true,
                  )
                : character.isLite
                ? cloneFrontPorchTier(
                    character.frontPorchExtensions,
                    lite: false,
                  )
                : character.frontPorchExtensions,
          ),
        ),
      ),
      rawExtensions: drift.Value(
        character.rawExtensions != null
            ? jsonEncode(character.rawExtensions!)
            : null,
      ),
      // Provenance: stamp which library character this member was copied from
      // so a chat can later collapse back to a 1:1 with the original (no orphans).
      memberState: drift.Value(
        GroupMember.encodeProvenance(
          originStableId: character.stableGroupId,
          originLibraryDbId: character.dbId,
        ),
      ),
    ),
  );
  return mid;
}

/// Deletes member [mid]'s row and private avatar, and what was filed under
/// their instance id (objectives, embeddings, data bank). The storage half of
/// a removal, shared by the chat's roster and Edit group.
Future<void> deleteGroupMemberRows({
  required AppDatabase db,
  required Directory groupsDir,
  required String groupId,
  required String mid,
  String? avatarFilename,
}) async {
  await db.deleteGroupMember(mid);
  if (avatarFilename != null) {
    try {
      final f = File(
        path.join(groupsDir.path, groupId, 'avatars', avatarFilename),
      );
      if (await f.exists()) await f.delete();
    } catch (e) {
      debugPrint('[Cast] avatar delete failed (non-fatal): $e');
    }
  }
  await db.deleteObjectivesForCharacter(mid);
  await db.deleteEmbeddingsForCharacter(mid);
  await db.deleteDataBankEntriesForCharacter(mid);
}
