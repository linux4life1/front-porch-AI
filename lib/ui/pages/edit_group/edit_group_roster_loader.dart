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
import 'package:front_porch_ai/ui/widgets/group_realism_dynamics_editor.dart';

/// A group's members as the editor needs them: cards for the Details tab and
/// realism rows (mid, name, origin, avatar) for the Realism tab. The origin
/// lets the realism editor recover seeds from groups made before the
/// id-keying fix. A member whose private avatar is gone is skipped.
Future<({List<CharacterCard> cards, List<GroupRealismMember> realism})>
loadEditGroupRoster(
  GroupChatRepository groupRepo,
  StorageService storage,
  String groupId,
) async {
  final cards = <CharacterCard>[];
  final realism = <GroupRealismMember>[];
  for (final m in await groupRepo.getMembersForGroup(groupId)) {
    final fn = m.avatarFilename;
    if (fn == null) continue;
    final avatarPath = p.join(storage.groupsDir.path, groupId, 'avatars', fn);
    if (!await File(avatarPath).exists()) continue;
    final card = m.toCharacterCard(resolvedImagePath: avatarPath);
    cards.add(card);
    realism.add(
      GroupRealismMember(
        mid: m.id,
        name: m.name,
        originStableId: m.originStableId,
        avatarPath: avatarPath,
        extensions: card.frontPorchExtensions,
      ),
    );
  }
  return (cards: cards, realism: realism);
}
