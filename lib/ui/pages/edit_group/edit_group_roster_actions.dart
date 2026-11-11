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
import 'package:front_porch_ai/ui/theme/app_colors.dart';
import 'package:front_porch_ai/ui/widgets/widgets.dart';

/// Asks which library character joins the group, listing everyone not
/// already a member (by name). Null when the user backs out.
Future<CharacterCard?> pickMemberToAdd(
  BuildContext context, {
  required List<CharacterCard> library,
  required Set<String> memberNames,
}) {
  final taken = {for (final n in memberNames) n.trim().toLowerCase()};
  final candidates = [
    for (final c in library)
      if (!c.isLite && !taken.contains(c.name.trim().toLowerCase())) c,
  ]..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  return showWarmDialogOf<CharacterCard>(
    context,
    builder: (_) => _AddMemberDialog(candidates: candidates),
  );
}

class _AddMemberDialog extends StatefulWidget {
  const _AddMemberDialog({required this.candidates});

  final List<CharacterCard> candidates;

  @override
  State<_AddMemberDialog> createState() => _AddMemberDialogState();
}

class _AddMemberDialogState extends State<_AddMemberDialog> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final q = _query.trim().toLowerCase();
    final shown = [
      for (final c in widget.candidates)
        if (q.isEmpty || c.name.toLowerCase().contains(q)) c,
    ];
    return WarmDialog(
      title: 'Add a member',
      icon: Icons.person_add_alt_1_outlined,
      width: 380,
      content: SizedBox(
        height: 320,
        child: Column(
          children: [
            AppTextField(
              decoration: const InputDecoration(hintText: 'Search characters'),
              onChanged: (v) => setState(() => _query = v),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: shown.isEmpty
                  ? Center(
                      child: Text(
                        'No one left to add.',
                        style: TextStyle(
                          color: AppColors.textTertiary(context),
                        ),
                      ),
                    )
                  : ListView(
                      children: [
                        for (final c in shown)
                          ListTile(
                            dense: true,
                            title: Text(c.name),
                            onTap: () => Navigator.of(context).pop(c),
                          ),
                      ],
                    ),
            ),
          ],
        ),
      ),
      actions: [warmDialogCancel(context)],
    );
  }
}

/// Confirms taking [name] out of the group: it deletes their copy and what
/// the open chat holds of them, and cannot be undone.
Future<bool> confirmRemoveMember(BuildContext context, String name) async {
  final ok = await showWarmDialog<bool>(
    context,
    title: 'Remove $name?',
    icon: Icons.person_remove_outlined,
    destructive: true,
    content: Text(
      'This takes $name out of the group and deletes their copy, their '
      'feelings and memories in this chat, and their notes. It cannot be '
      'undone. If only one member is left, the group becomes a 1:1 chat with '
      'them.',
      style: TextStyle(color: AppColors.textSecondary(context)),
    ),
    actions: [
      warmDialogCancel(context, value: false),
      warmDialogConfirm(
        context,
        label: 'Remove',
        destructive: true,
        onPressed: () => Navigator.of(context).pop(true),
      ),
    ],
  );
  return ok ?? false;
}

/// Adds a library character to the group through the chat open on it (the
/// chat is what makes a member: their copy, their switches, the roster the
/// turn order walks). True when a member was added.
Future<bool> addMemberToOpenChat(
  BuildContext context,
  ChatService chat,
  GroupChatRepository repo,
  List<CharacterCard> current,
) async {
  final library = Provider.of<CharacterRepository>(context, listen: false);
  final picked = await pickMemberToAdd(
    context,
    library: library.characters,
    memberNames: {for (final c in current) c.name},
  );
  if (picked == null || !context.mounted) return false;
  final messenger = ScaffoldMessenger.of(context);
  final ok = await chat.addCharacterToGroup(picked, repo);
  messenger.showSnackBar(
    SnackBar(
      content: Text(
        ok
            ? '${picked.name} joined the group.'
            : "Couldn't add ${picked.name}. They may already be in the "
                  'group, or a reply is being written.',
      ),
    ),
  );
  return ok;
}

/// Removes [live] (the chat's copy of the member) from the group, after
/// asking. True when they were removed.
Future<bool> removeMemberFromOpenChat(
  BuildContext context,
  ChatService chat,
  GroupChatRepository repo,
  CharacterCard live,
) async {
  if (!await confirmRemoveMember(context, live.name) || !context.mounted) {
    return false;
  }
  final messenger = ScaffoldMessenger.of(context);
  final ok = await chat.removeCharacterFromGroup(live, repo);
  messenger.showSnackBar(
    SnackBar(
      content: Text(
        ok
            ? '${live.name} left the group.'
            : "Couldn't remove ${live.name} while a reply is being written.",
      ),
    ),
  );
  return ok;
}
