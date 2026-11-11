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

import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';
import 'package:front_porch_ai/ui/widgets/widgets.dart';

/// One member in the group editor's Details tab: their name with Edit (their
/// card) and Remove (only while a chat is open on the group, which is what
/// carries the removal out), the group-only system prompt that applies to
/// them, and, with a chat open, their Author's Note for that chat.
class EditGroupMemberBox extends StatelessWidget {
  const EditGroupMemberBox({
    super.key,
    required this.member,
    required this.promptController,
    required this.onEdit,
    this.onRemove,
    this.note,
  });

  final CharacterCard member;
  final TextEditingController promptController;
  final VoidCallback onEdit;

  /// Null when no chat is open on the group (removal needs the chat).
  final VoidCallback? onRemove;

  /// [EditGroupMemberNote], or null when no chat is open on the group.
  final Widget? note;

  @override
  Widget build(BuildContext context) {
    final small = OutlinedButton.styleFrom(
      foregroundColor: AppColors.textSecondary(context),
      side: BorderSide(color: AppColors.borderOf(context)),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      minimumSize: const Size(0, 32),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      textStyle: const TextStyle(fontSize: 12),
    );
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerOf(context),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: AppColors.borderOf(context).withValues(alpha: 0.4),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            runSpacing: 6,
            children: [
              Text(
                member.name,
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary(context),
                ),
              ),
              Wrap(
                spacing: 8,
                children: [
                  OutlinedButton.icon(
                    onPressed: onEdit,
                    icon: const Icon(Icons.edit_outlined, size: 15),
                    label: const Text('Edit'),
                    style: small,
                  ),
                  if (onRemove != null)
                    OutlinedButton.icon(
                      onPressed: onRemove,
                      icon: const Icon(Icons.person_remove_outlined, size: 15),
                      label: const Text('Remove'),
                      style: small.copyWith(
                        foregroundColor: WidgetStatePropertyAll(
                          AppColors.bondNegOf(context),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 6),
          AppTextField(
            controller: promptController,
            maxLines: 2,
            decoration: const InputDecoration(
              hintText:
                  'Extra instructions only for this character in this group',
            ),
          ),
          if (note != null) ...[const SizedBox(height: 10), note!],
        ],
      ),
    );
  }
}

/// A member's Author's Note for the open chat and how strongly it is
/// injected (1 to 10). It lives in the chat, not the group's definition, so
/// it applies as it is typed, as it did in Group Settings, and only exists
/// while a chat is open on the group.
class EditGroupMemberNote extends StatefulWidget {
  const EditGroupMemberNote({
    super.key,
    required this.chat,
    required this.member,
  });

  final ChatService chat;

  /// The chat's own copy of the member.
  final CharacterCard member;

  @override
  State<EditGroupMemberNote> createState() => _EditGroupMemberNoteState();
}

class _EditGroupMemberNoteState extends State<EditGroupMemberNote> {
  late final TextEditingController _note = TextEditingController(
    text: widget.chat.getAuthorNoteForGroupCharacter(widget.member),
  );
  late int _strength = widget.chat.getAuthorNoteStrengthForGroupCharacter(
    widget.member,
  );

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  void _write() => widget.chat.setAuthorNoteForGroupCharacter(
    widget.member,
    _note.text,
    strength: _strength,
  );

  @override
  Widget build(BuildContext context) {
    final accent = AppColors.emotionAccentOf(context);
    return Column(
      key: ValueKey('member-note-${widget.member.dbId}'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          "Author's note · this chat",
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: AppColors.textSecondary(context),
          ),
        ),
        const SizedBox(height: 4),
        AppTextField(
          controller: _note,
          maxLines: 3,
          minLines: 1,
          decoration: InputDecoration(
            hintText:
                "Injected only when ${widget.member.name} speaks, in this chat",
          ),
          onChanged: (_) => _write(),
        ),
        Row(
          children: [
            Text(
              'Strength',
              style: TextStyle(
                fontSize: 11,
                color: AppColors.textSecondary(context),
              ),
            ),
            Expanded(
              child: Slider(
                value: _strength.toDouble(),
                min: 1,
                max: 10,
                divisions: 9,
                activeColor: accent,
                inactiveColor: AppColors.borderOf(context),
                onChanged: (v) {
                  setState(() => _strength = v.round());
                  _write();
                },
              ),
            ),
            SizedBox(
              width: 22,
              child: Text(
                '$_strength',
                textAlign: TextAlign.right,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: accent,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
