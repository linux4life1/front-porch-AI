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

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/pages/edit_character_page.dart'
    show leaveCharacterEditor;
import 'package:front_porch_ai/ui/pages/edit_character_page/edit_character_page.dart'
    show memberGroupViewOfTemplate;
import 'package:front_porch_ai/ui/pages/edit_group/edit_group_details_tab.dart';

/// Edit group's tabs, in order; the member editor's links go back to
/// [kEditGroupRealismTab].
const kEditGroupTabs = [
  Tab(icon: Icon(Icons.person_outline, size: 18), text: 'Details'),
  Tab(icon: Icon(Icons.chat_bubble_outline, size: 18), text: 'Dialogue'),
  Tab(icon: Icon(Icons.auto_stories_outlined, size: 18), text: 'Lore & Worlds'),
  Tab(icon: Icon(Icons.favorite_outline, size: 18), text: 'Realism & Dynamics'),
];
const kEditGroupRealismTab = 3;

/// Opens [member]'s editor from Edit group, on [group]'s settings for new
/// chats as the page holds them now ([defaultMemberJson], [baselineJson],
/// where it meets: [settingId], and [inheritCharacterLorebooks]). A start
/// the editor saves reaches the group's row and comes back through
/// [onStartSaved]. Returns true when the editor's "Realism & Dynamics" link
/// closed it, so the page shows that tab; a link the user backed out of
/// ("Keep editing") does not count, whatever closes the editor later.
Future<bool> editGroupMemberFromEditGroup(
  BuildContext context, {
  required GroupChat group,
  required CharacterCard member,
  required String memberId,
  required String defaultMemberJson,
  required String baselineJson,
  required String? settingId,
  required bool inheritCharacterLorebooks,
  required void Function(String defaultMemberJson, String baselineJson)
  onStartSaved,
}) async {
  var toRealism = false;
  // A group made before the id-keying fix filed seeds under the member's
  // origin; the editor reads and moves those.
  final legacy = await groupMemberLegacyKeys(
    liveDatabase(context),
    group.id,
    memberId,
  );
  if (!context.mounted) return false;
  String? settingName;
  try {
    final worlds = Provider.of<WorldRepository>(context, listen: false);
    settingName = settingId == null ? null : worlds.worldById(settingId)?.name;
  } on ProviderNotFoundException {
    settingName = null;
  }
  await editGroupMemberCard(
    context,
    member,
    memberId,
    groupName: group.name,
    memberGroup: memberGroupViewOfTemplate(
      context,
      group: group,
      memberId: memberId,
      memberExtensions: member.frontPorchExtensions,
      defaultMemberJson: defaultMemberJson,
      baselineJson: baselineJson,
      settingName: settingName,
      readsMemberLorebooks: inheritCharacterLorebooks,
      onStartSaved: onStartSaved,
      legacyIds: legacy,
      onOpenRealism: (editor) =>
          leaveCharacterEditor(editor, onLeave: () => toRealism = true),
    ),
  );
  return toRealism;
}
