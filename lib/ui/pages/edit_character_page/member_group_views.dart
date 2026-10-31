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
import 'package:front_porch_ai/ui/pages/chat_page.session_dialogs.dart'
    show showGroupSettings;
import 'package:front_porch_ai/ui/pages/edit_character_page.dart'
    show leaveCharacterEditor;
import 'package:front_porch_ai/ui/pages/edit_character_page/member_group_view.dart';
import 'package:front_porch_ai/utils/utils.dart';

/// Group Settings' Realism and Needs tabs (see `GroupSettingsDialog`).
const kGroupSettingsRealismTab = 2;
const kGroupSettingsNeedsTab = 3;

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

WorldRepository? _worlds(BuildContext context) {
  try {
    return Provider.of<WorldRepository>(context, listen: false);
  } on ProviderNotFoundException {
    return null;
  }
}

/// The member editor's view of the group open in [chat]: the chat's own
/// switches, links to Group Settings, and [member]'s start in the group's
/// new chats. Opened from inside Group Settings ([showTab] is its tab
/// switch), a link closes the editor back to that dialog's tab instead of
/// opening a second one.
MemberGroupView memberGroupViewOfChat(
  BuildContext context,
  ChatService chat,
  CharacterCard member, {
  void Function(int tab)? showTab,
}) {
  final group = chat.activeGroup;
  final worlds = _worlds(context);
  final mid = groupMemberStoreId(member);
  final ext = member.frontPorchExtensions;
  // Group Settings saves through the group repository; without one (a
  // host that has none) the lines show their values with no link.
  var canOpen = true;
  try {
    Provider.of<GroupChatRepository>(context, listen: false);
  } on ProviderNotFoundException {
    canOpen = false;
  }
  final back = showTab;
  void Function(BuildContext)? open(int tab) => back != null
      ? (ctx) => leaveCharacterEditor(ctx, onLeave: () => back(tab))
      : !canOpen
      ? null
      : (ctx) => showGroupSettings(ctx, chat, initialTab: tab);
  final legacy = [member.stableGroupId];
  return MemberGroupView(
    read: () => groupWideValuesOfChat(chat, worlds: worlds),
    changes: chat,
    realismAllowed: _realismAllowed(context),
    onOpenRealism: open(kGroupSettingsRealismTab),
    onOpenChaos: open(kGroupSettingsRealismTab),
    onOpenNeeds: open(kGroupSettingsNeedsTab),
    start: group == null
        ? null
        : groupMemberStartIn(
            group.defaultMemberRealismState,
            mid,
            card: ext,
            legacyIds: legacy,
          ),
    saveStart: group == null
        ? null
        : (start) => saveGroupMemberStart(
            liveDatabase(context),
            groupId: group.id,
            mid: mid,
            start: start,
            card: ext,
            chat: chat,
            legacyIds: legacy,
          ),
  );
}

/// The member editor's view of a group's settings for new chats, from Edit
/// group: [defaultMemberJson] and [baselineJson] are the realism blobs the
/// page holds now. A saved start is written to the group's row at once (and
/// to the open chat's copy of the group); [onStartSaved] hands the page the
/// blobs with it, so its own Save keeps it. [onOpenRealism] goes back to the
/// page's Realism & Dynamics tab, where the group sets these; Chaos is not
/// there (it is Group Settings', in the group's chat), so its line says so.
/// [legacyIds] are keys an older group filed the member's seed under.
MemberGroupView memberGroupViewOfTemplate(
  BuildContext context, {
  required GroupChat group,
  required String memberId,
  required FrontPorchExtensions? memberExtensions,
  required String defaultMemberJson,
  required String baselineJson,
  String? settingName,
  bool? readsMemberLorebooks,
  void Function(String defaultMemberJson, String baselineJson)? onStartSaved,
  void Function(BuildContext context)? onOpenRealism,
  List<String> legacyIds = const [],
}) {
  final db = liveDatabase(context);
  final chat = Provider.of<ChatService>(context, listen: false);
  return MemberGroupView(
    read: () => groupWideValuesOfTemplate(
      defaultMemberJson: defaultMemberJson,
      baselineJson: baselineJson,
      chaos: group.chaosModeEnabled,
      settingName: settingName,
      readsMemberLorebooks:
          readsMemberLorebooks ?? group.inheritCharacterLorebooks,
    ),
    linkLabel: 'Realism & Dynamics',
    realismAllowed: _realismAllowed(context),
    onOpenRealism: onOpenRealism,
    onOpenNeeds: onOpenRealism,
    chaosWhere: "set in Group Settings, in the group's chat",
    loreWhere:
        'Edit group → Lore & Worlds has "Inherit character & world '
        'lorebooks"',
    worldsWhere: 'Edit group → Lore & Worlds',
    start: groupMemberStartIn(
      defaultMemberJson,
      memberId,
      card: memberExtensions,
      legacyIds: legacyIds,
    ),
    saveStart: (start) async {
      await saveGroupMemberStart(
        db,
        groupId: group.id,
        mid: memberId,
        start: start,
        card: memberExtensions,
        chat: chat,
        legacyIds: legacyIds,
      );
      final mine = withGroupMemberStart(
        defaultMemberJson: defaultMemberJson,
        baselineJson: baselineJson,
        mid: memberId,
        start: start,
        card: memberExtensions,
        legacyIds: legacyIds,
      );
      onStartSaved?.call(mine.defaultMemberJson, mine.baselineJson);
    },
  );
}
