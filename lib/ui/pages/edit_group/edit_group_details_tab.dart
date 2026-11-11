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
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/pages/edit_character_page.dart';
import 'package:front_porch_ai/ui/pages/edit_group/edit_group_member_box.dart';
import 'package:front_porch_ai/ui/pages/edit_group/edit_group_turn_taking.dart';
import 'package:front_porch_ai/ui/pages/edit_character_page/edit_character_page.dart'
    show MemberGroupView;
import 'package:front_porch_ai/ui/theme/app_colors.dart';
import 'package:front_porch_ai/ui/widgets/widgets.dart';

/// Edit one member's card in the reused single-character editor, in its
/// member mode for [groupName]. Saves to the group's member row only (never
/// the source library character): every column the editor shows, voice,
/// greeting seeds and the member's own Realism and Needs settings included.
/// When the group is open in the chat, its copy of the member is replaced
/// too, so a later save from the chat cannot put the old values back.
/// [memberGroup] is what it shows of the group (its lines and the member's
/// start). Returns the edited card, or null when the editor was backed out
/// of.
Future<CharacterCard?> editGroupMemberCard(
  BuildContext context,
  CharacterCard member,
  String memberId, {
  required String groupName,
  MemberGroupView? memberGroup,
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
        memberOfGroup: groupName,
        memberGroup: memberGroup,
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

/// Details tab of the group editor, in the order the web page has them:
/// identity (name, system prompt, scenario), turn-taking (order,
/// auto-advance, start in Director) and members (each with Edit, their
/// group-only prompt and, with a chat open on the group, Remove and their
/// Author's Note for it, then Add member).
class EditGroupDetailsTab extends StatelessWidget {
  const EditGroupDetailsTab({
    super.key,
    required this.nameController,
    required this.systemPromptController,
    required this.scenarioController,
    required this.members,
    required this.charPromptControllers,
    required this.onEditMember,
    required this.turnOrder,
    required this.autoAdvance,
    required this.directorMode,
    required this.onTurnOrderChanged,
    required this.onAutoAdvanceChanged,
    required this.onDirectorModeChanged,
    this.openChat,
    this.onRemoveMember,
    this.onAddMember,
  });

  final TextEditingController nameController;
  final TextEditingController systemPromptController;
  final TextEditingController scenarioController;
  final List<CharacterCard> members;

  /// Per-member prompt overrides keyed by member id.
  final Map<String, TextEditingController> charPromptControllers;
  final void Function(CharacterCard member, String memberId) onEditMember;
  final TurnOrder turnOrder;
  final bool autoAdvance;
  final bool directorMode;
  final ValueChanged<TurnOrder> onTurnOrderChanged;
  final ValueChanged<bool> onAutoAdvanceChanged;
  final ValueChanged<bool> onDirectorModeChanged;

  /// The chat open on this group, or null. Removing and adding members and
  /// the members' Author's Notes need it.
  final ChatService? openChat;
  final void Function(CharacterCard member)? onRemoveMember;
  final VoidCallback? onAddMember;

  static String memberKey(CharacterCard c) =>
      c.dbId ??
      (c.imagePath != null ? p.basenameWithoutExtension(c.imagePath!) : c.name);

  Widget _heading(BuildContext context, String text, {IconData? icon}) => Row(
    children: [
      if (icon != null) ...[
        Icon(icon, color: AppColors.porchAmberOf(context), size: 20),
        const SizedBox(width: 8),
      ],
      Text(
        text,
        style: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          color: AppColors.porchAmberOf(context),
        ),
      ),
    ],
  );

  BoxDecoration _card(BuildContext context) => BoxDecoration(
    color: AppColors.cardOf(context),
    borderRadius: BorderRadius.circular(12),
    border: Border.all(color: AppColors.borderOf(context)),
  );

  Widget _label(BuildContext context, String text) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Text(
      text,
      style: TextStyle(
        fontSize: 15,
        fontWeight: FontWeight.w600,
        color: AppColors.textPrimary(context),
      ),
    ),
  );

  CharacterCard? _liveOf(CharacterCard c) {
    final chat = openChat;
    if (chat == null) return null;
    for (final live in chat.groupCharacters) {
      if (live.dbId != null && live.dbId == c.dbId) return live;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final chat = openChat;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _label(context, 'Group Name'),
          AppTextField(
            controller: nameController,
            decoration: const InputDecoration(hintText: 'My Group'),
          ),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: _card(context),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _heading(
                  context,
                  'Personality & World',
                  icon: Icons.psychology_outlined,
                ),
                const SizedBox(height: 8),
                Text(
                  'Group-level equivalents to character personality live in the system prompt and scenario.',
                  style: TextStyle(
                    fontSize: 13,
                    color: AppColors.textSecondary(context),
                    fontStyle: FontStyle.italic,
                  ),
                ),
                const SizedBox(height: 16),
                _label(context, 'Group System Prompt'),
                AppTextField(
                  controller: systemPromptController,
                  maxLines: 6,
                  decoration: const InputDecoration(
                    hintText: 'Blank uses the Group system prompt in Settings',
                  ),
                ),
                const SizedBox(height: 16),
                _label(context, 'Scenario (optional)'),
                AppTextField(
                  controller: scenarioController,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    hintText: 'The group is...',
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: _card(context),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _heading(context, 'Turn Taking', icon: Icons.swap_horiz),
                const SizedBox(height: 12),
                EditGroupTurnTaking(
                  turnOrder: turnOrder,
                  autoAdvance: autoAdvance,
                  directorMode: directorMode,
                  onTurnOrderChanged: onTurnOrderChanged,
                  onAutoAdvanceChanged: onAutoAdvanceChanged,
                  onDirectorModeChanged: onDirectorModeChanged,
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: _card(context),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _heading(context, 'Members', icon: Icons.people_alt_outlined),
                const SizedBox(height: 8),
                Text(
                  chat == null
                      ? 'Prompts here apply to this group. Open a chat with it to add or remove members and write their Author\'s Notes.'
                      : 'Prompts apply to this group and to the chat you have open. Author\'s Notes are for that chat only.',
                  style: TextStyle(
                    fontSize: 13,
                    color: AppColors.textSecondary(context),
                  ),
                ),
                const SizedBox(height: 12),
                if (members.isEmpty)
                  Text(
                    'No members in this group.',
                    style: TextStyle(color: AppColors.textTertiary(context)),
                  )
                else
                  for (final c in members)
                    Builder(
                      builder: (context) {
                        final id = memberKey(c);
                        final live = _liveOf(c);
                        return EditGroupMemberBox(
                          member: c,
                          promptController:
                              charPromptControllers[id] ??
                              TextEditingController(),
                          onEdit: () => onEditMember(c, id),
                          onRemove: live == null || onRemoveMember == null
                              ? null
                              : () => onRemoveMember!(live),
                          note: live == null
                              ? null
                              : EditGroupMemberNote(chat: chat!, member: live),
                        );
                      },
                    ),
                if (onAddMember != null) ...[
                  const SizedBox(height: 4),
                  OutlinedButton.icon(
                    onPressed: onAddMember,
                    icon: const Icon(Icons.person_add_alt_1_outlined, size: 18),
                    label: const Text('Add member'),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
