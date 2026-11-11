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
import 'package:front_porch_ai/ui/widgets/widgets.dart';

/// The cast buttons of Edit group, through the chat that has the group open
/// ([ChatService] owns the roster, its per-member state and the chat's
/// reset). [onDone] reads the roster again.

/// "+ Add a character": pick from the library; the member joins as a full
/// member with a copy of the card.
Future<void> castAddMember(
  BuildContext context,
  ChatService chat, {
  required Future<void> Function() onDone,
}) async {
  final repo = Provider.of<CharacterRepository>(context, listen: false);
  final folders = Provider.of<FolderService>(context, listen: false);
  final groupRepo = Provider.of<GroupChatRepository>(context, listen: false);
  final inGroup = {for (final c in chat.groupCharacters) c.name};
  final picked = await showWarmDialog<CharacterCard>(
    context,
    title: 'Add a character',
    icon: Icons.person_add_alt,
    width: 420,
    content: SizedBox(
      width: 380,
      height: 380,
      child: Builder(
        builder: (ctx) => FolderCharacterPicker(
          characters: [
            for (final c in repo.characters)
              if (!inGroup.contains(c.name)) c,
          ],
          folderService: folders,
          onTapCharacter: (c) => Navigator.of(ctx).pop(c),
        ),
      ),
    ),
    actions: [warmDialogCancel(context)],
  );
  if (picked == null) return;
  final ok = await chat.addCharacterToGroup(picked, groupRepo);
  if (context.mounted && !ok) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text("Couldn't add them right now. Try again in a moment."),
      ),
    );
  }
  await onDone();
}

/// "Remove…": asks first, then removes the member and everything the group
/// kept for them.
Future<void> castRemoveMember(
  BuildContext context,
  ChatService chat,
  CharacterCard member, {
  required Future<void> Function() onDone,
}) async {
  final groupRepo = Provider.of<GroupChatRepository>(context, listen: false);
  final go = await showWarmDialog<bool>(
    context,
    title: 'Remove ${member.name}?',
    icon: Icons.person_remove_outlined,
    destructive: true,
    content: WarmDialogText(
      '${member.name} leaves this group, and what the group kept for them '
      "(their copy, notes and memories here) goes with them. Their library "
      'character is not touched.',
    ),
    actions: [
      warmDialogCancel(context, value: false),
      warmDialogConfirm(
        context,
        label: 'Remove',
        onPressed: () => Navigator.of(context).pop(true),
      ),
    ],
  );
  if (go != true) return;
  await chat.removeCharacterFromGroup(member, groupRepo);
  await onDone();
}

/// "Bring back a removed member": undoes the last /exit while its offer is
/// open.
Future<void> castBringBack(
  BuildContext context,
  ChatService chat, {
  required Future<void> Function() onDone,
}) async {
  if (chat.exitUndoOfferName == null) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('No one has left this chat to bring back.')),
    );
    return;
  }
  await chat.undoLastExit();
  await onDone();
}
