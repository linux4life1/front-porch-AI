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
import 'package:front_porch_ai/ui/pages/edit_character_page.dart';
import 'package:front_porch_ai/ui/pages/edit_character_page/edit_character_page.dart'
    show GroupMemberMode;
import 'package:front_porch_ai/ui/widgets/porch_snack_bar.dart';

/// Edit one member's card in the character editor, in its member mode.
/// Saves to the group's member row only (never the source library
/// character): every column the editor shows, voice, greeting seeds and the
/// member's own Realism and Needs settings included. When the group is open
/// in the chat, its copy of the member is replaced too, so a later save from
/// the chat cannot put the old values back. [mode] says what it shows of the
/// group and where the group's values for the member are stored. Returns
/// the edited card, or null when the editor was backed out of.
Future<CharacterCard?> editGroupMemberCard(
  BuildContext context,
  CharacterCard member,
  String memberId, {
  required GroupMemberMode mode,
}) async {
  // The live database, not the startup snapshot `Provider<AppDatabase>`
  // holds: a backup restore closes that one.
  final database = liveDatabase(context);
  final chat = Provider.of<ChatService>(context, listen: false);
  final afterglowBefore = member.frontPorchExtensions?.afterglowEnabled ?? true;
  final edited = await Navigator.of(context).push<CharacterCard>(
    MaterialPageRoute(
      builder: (_) => EditCharacterPage(
        character: member,
        member: mode,
        allowAvatarChange: false,
        popWithCardOnSave: true,
        onSaveOverride: (card) async {
          final before = liveMemberAfterglow(
            chat,
            card..dbId = memberId,
            afterglowBefore,
          );
          await saveGroupMemberCard(database, card);
          if (isOpenGroupMember(chat, card)) {
            chat.refreshActiveCharacterCard(card);
            await settleMemberAfterglow(chat, card, before);
          }
        },
      ),
    ),
  );
  if (edited != null && context.mounted) {
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      porchSnackBar(context, '“${edited.name}” updated in this group.'),
    );
  }
  return edited;
}
