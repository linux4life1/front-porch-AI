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

import 'dart:io';

import 'package:path/path.dart' as p;

import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/services.dart';

/// A group's members as the editor needs them: their cards, with each
/// card's `dbId` the member's id in the group. A member whose private avatar
/// is gone is skipped.
Future<List<CharacterCard>> loadEditGroupRoster(
  GroupChatRepository groupRepo,
  StorageService storage,
  String groupId,
) async {
  final cards = <CharacterCard>[];
  for (final m in await groupRepo.getMembersForGroup(groupId)) {
    final fn = m.avatarFilename;
    if (fn == null) continue;
    final avatarPath = p.join(storage.groupsDir.path, groupId, 'avatars', fn);
    if (!await File(avatarPath).exists()) continue;
    cards.add(m.toCharacterCard(resolvedImagePath: avatarPath));
  }
  return cards;
}
