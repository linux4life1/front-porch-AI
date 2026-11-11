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
import 'package:front_porch_ai/ui/pages/edit_character_page/group_member_mode.dart';
import 'package:front_porch_ai/utils/utils.dart';

/// Porch Life's Realism permission as the editor opens (allowed without a
/// StorageService above, as in widget goldens).
bool _realismAllowed(BuildContext context) {
  try {
    return Provider.of<StorageService>(
      context,
      listen: false,
    ).realismSettings.realismAllowed;
  } on ProviderNotFoundException {
    return true;
  }
}

/// Member mode of the editor for [member] of [group]: the group's name and
/// scene, the other members of [cast], and the group's values for them. The
/// values are stored by [saveValues].
GroupMemberMode groupMemberModeOf(
  BuildContext context, {
  required GroupChat group,
  required CharacterCard member,
  required Iterable<CharacterCard> cast,
  required Future<void> Function(GroupMemberValues values) saveValues,
}) {
  final mid = groupMemberStoreId(member);
  return GroupMemberMode(
    groupName: group.name,
    memberId: mid,
    others: [
      for (final c in cast)
        if (groupMemberStoreId(c) != mid)
          GroupMemberRef(groupMemberStoreId(c), c.name),
    ],
    scene: groupSceneOf(group),
    values: groupMemberValuesOf(group, mid),
    saveValues: saveValues,
    realismAllowed: _realismAllowed(context),
  );
}

/// Member mode for [member] opened from the chat sidebar: the open group's
/// values are stored on its row (the chat's own per-member settings are not
/// touched; they are this chat's, these are the new-chat defaults).
GroupMemberMode? groupMemberModeOfChat(
  BuildContext context,
  ChatService chat,
  CharacterCard member,
) {
  final group = chat.activeGroup;
  if (group == null) return null;
  final repo = Provider.of<GroupChatRepository>(context, listen: false);
  final mid = groupMemberStoreId(member);
  return groupMemberModeOf(
    context,
    group: group,
    member: member,
    cast: chat.groupCharacters,
    saveValues: (values) async {
      applyGroupMemberValues(group, mid, values);
      await repo.save(group);
    },
  );
}
