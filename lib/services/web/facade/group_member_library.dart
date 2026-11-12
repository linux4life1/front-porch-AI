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
import 'package:front_porch_ai/services/chat/member_origin_resolver.dart';
import 'package:front_porch_ai/services/group_chat_repository.dart';

/// The library character a group member was copied from: `{id, name}`, or
/// null when the member is gone or its origin cannot be resolved.
///
/// The Avatar Gallery of a group member is the library character's gallery
/// (a member copy has one avatar file and no expression set), exactly as the
/// desktop's Main Settings opens it. Nothing here touches the member's own
/// avatar file under `groups/<id>/avatars/`, which stays its storage key.
Future<Map<String, String>?> memberLibraryCharacter(
  GroupChatRepository groups,
  Iterable<CharacterCard> library,
  String groupId,
  String memberId,
) async {
  final members = await groups.getMembersForGroup(groupId);
  final member = members.where((m) => m.id == memberId).firstOrNull;
  if (member == null) return null;
  final origin = MemberOriginResolver.resolveForCard(
    member.toCharacterCard(resolvedImagePath: ''),
    library,
  );
  final id = origin?.dbId;
  if (origin == null || id == null || id.isEmpty) return null;
  return {'id': id, 'name': origin.name};
}
