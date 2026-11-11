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

import 'package:front_porch_ai/database/database.dart' show GroupMemberRow;
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/widgets/widgets.dart';

/// The cast buttons of Edit group. They change the group's member rows
/// ([GroupRosterEditor]) whether or not the group's chat is open; when it is
/// open the chat's own roster does the work, so the running chat follows.
/// [onDone] reads the roster again.
class EditGroupCast {
  EditGroupCast({
    required this.context,
    required this.group,
    required this.chat,
    required this.onDone,
  });

  final BuildContext Function() context;
  final GroupChat group;
  final ChatService chat;
  final Future<void> Function() onDone;

  bool get _open => chat.activeGroup?.id == group.id;

  GroupRosterEditor get editor => GroupRosterEditor(
    db: liveDatabase(context()),
    groupsDir: Provider.of<StorageService>(context(), listen: false).groupsDir,
  );

  void _say(String text) {
    if (!context().mounted) return;
    ScaffoldMessenger.of(context()).showSnackBar(SnackBar(content: Text(text)));
  }

  /// "+ Add a character": pick from the library; the member joins as a full
  /// member with a copy of the card.
  Future<void> add() async {
    final c = context();
    final repo = Provider.of<CharacterRepository>(c, listen: false);
    final folders = Provider.of<FolderService>(c, listen: false);
    final groupRepo = Provider.of<GroupChatRepository>(c, listen: false);
    final inGroup = {
      for (final m in await groupRepo.getMembersForGroup(group.id)) m.name,
    };
    if (!c.mounted) return;
    final picked = await showWarmDialog<CharacterCard>(
      c,
      title: 'Add a character',
      icon: Icons.person_add_alt,
      width: 420,
      content: SizedBox(
        width: 380,
        height: 380,
        child: Builder(
          builder: (ctx) => FolderCharacterPicker(
            characters: [
              for (final x in repo.characters)
                if (!inGroup.contains(x.name)) x,
            ],
            folderService: folders,
            onTapCharacter: (x) => Navigator.of(ctx).pop(x),
          ),
        ),
      ),
      actions: [warmDialogCancel(c)],
    );
    if (picked == null) return;
    if (_open) {
      if (!await chat.addCharacterToGroup(picked, groupRepo)) {
        _say("Couldn't add them right now. Try again in a moment.");
      }
    } else {
      await editor.add(characters: repo, groupId: group.id, character: picked);
    }
    await onDone();
  }

  /// "Remove…": asks first, then removes the member and what the group kept
  /// for them. A group keeps at least two members.
  Future<void> remove(CharacterCard member) async {
    final c = context();
    final mid = member.dbId;
    if (mid == null) return;
    final go = await showWarmDialog<bool>(
      c,
      title: 'Remove ${member.name}?',
      icon: Icons.person_remove_outlined,
      destructive: true,
      content: WarmDialogText(
        '${member.name} leaves this group, and what the group kept for them '
        '(their copy and notes) goes with them. You can bring their copy '
        'back here. Their library character is not touched.',
      ),
      actions: [
        warmDialogCancel(c, value: false),
        warmDialogConfirm(
          c,
          label: 'Remove',
          onPressed: () => Navigator.of(c).pop(true),
        ),
      ],
    );
    if (go != true) return;
    final ed = editor;
    if (await ed.count(group.id) <= GroupRosterEditor.minMembers) {
      _say('A group needs at least two members.');
      return;
    }
    if (_open) {
      final row = await ed.rowOf(group.id, mid);
      if (row != null) await ed.keepCopy(group.id, row);
      if (!context().mounted) return;
      await chat.removeCharacterFromGroup(
        member,
        Provider.of<GroupChatRepository>(context(), listen: false),
      );
    } else {
      await ed.remove(group.id, mid);
    }
    await onDone();
  }

  /// "Bring back a removed member": the kept copies of this group, newest
  /// pick first.
  Future<void> bringBack() async {
    final ed = editor;
    final kept = await ed.removedMembers(group.id);
    if (kept.isEmpty || !context().mounted) return;
    final c = context();
    final GroupMemberRow? pick = kept.length == 1
        ? kept.single
        : await showWarmDialog<GroupMemberRow>(
            c,
            title: 'Bring back a removed member',
            icon: Icons.person_add_alt,
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final r in kept)
                  ListTile(
                    title: Text(r.name),
                    onTap: () => Navigator.of(c).pop(r),
                  ),
              ],
            ),
            actions: [warmDialogCancel(c)],
          );
    if (pick == null) return;
    if (_open) {
      // The chat re-adds their copy; the kept one is then spent.
      if (!context().mounted) return;
      final member = GroupMember.fromRow(
        pick,
      ).toCharacterCard(resolvedImagePath: '');
      await chat.addCharacterToGroup(
        member,
        Provider.of<GroupChatRepository>(context(), listen: false),
      );
      await ed.discardKept(group.id, pick);
    } else {
      await ed.bringBack(group.id, pick);
    }
    await onDone();
  }
}
