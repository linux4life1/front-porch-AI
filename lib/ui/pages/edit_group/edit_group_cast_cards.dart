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
import 'package:front_porch_ai/ui/pages/create_group_chat_page/group_cast_steps.dart'
    show groupMemberAvatar;
import 'package:front_porch_ai/ui/pages/edit_character_page/edit_character_form_kit.dart';
import 'package:front_porch_ai/ui/pages/edit_group/edit_group_draft.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';
import 'package:front_porch_ai/ui/widgets/greyed_out.dart';
import 'package:front_porch_ai/ui/widgets/widgets.dart';

/// Said on the cast buttons while this group is not the one open in the chat:
/// the roster is changed through the open chat.
const kCastNeedsOpenChatTooltip =
    "Open this group's chat to change who is in it.";

/// What the cast buttons do; a null callback greys its button out.
class CastActions {
  const CastActions({this.onAdd, this.onRemove, this.onBringBack});

  final VoidCallback? onAdd;
  final void Function(CharacterCard member)? onRemove;
  final VoidCallback? onBringBack;
}

/// Details 1: Identity. The group name, and the cast: a row per member with
/// "Edit Ana's card" and "Remove…", then "+ Add a character" and "Bring back
/// a removed member".
class EditGroupIdentityCard extends StatelessWidget {
  const EditGroupIdentityCard({
    super.key,
    required this.draft,
    required this.members,
    required this.onEditMember,
    required this.cast,
    required this.onChanged,
  });

  final EditGroupDraft draft;
  final List<CharacterCard> members;
  final void Function(CharacterCard member) onEditMember;
  final CastActions cast;
  final VoidCallback onChanged;

  Widget _button(
    BuildContext context, {
    required String label,
    required VoidCallback? onPressed,
    bool accent = false,
    bool danger = false,
  }) {
    final color = danger
        ? AppColors.negativeAccentOf(context)
        : accent
        ? AppColors.formAccentOf(context)
        : AppColors.textSecondary(context);
    final button = OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        foregroundColor: color,
        side: BorderSide(color: color.withValues(alpha: 0.5)),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        minimumSize: const Size(0, 32),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
      ),
      child: Text(label),
    );
    return onPressed == null
        ? GreyedOut(tooltip: kCastNeedsOpenChatTooltip, child: button)
        : button;
  }

  @override
  Widget build(BuildContext context) {
    final kit = EditCharacterFormKit(context);
    return kit.sectionCard(
      icon: Icons.badge_outlined,
      title: 'Identity',
      color: AppColors.formAccentOf(context),
      children: [
        kit.styledField(controller: draft.name, label: 'Group name'),
        const SizedBox(height: 16),
        kit.fieldLabel('Cast'),
        const SizedBox(height: 8),
        if (members.isEmpty)
          Text(
            'No members in this group.',
            style: TextStyle(color: AppColors.textTertiary(context)),
          ),
        for (final m in members)
          Container(
            key: Key('cast-row-${m.dbId}'),
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppColors.surfaceContainerOf(context),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                groupMemberAvatar(context, m, radius: 16),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    m.name,
                    style: TextStyle(
                      color: AppColors.textPrimary(context),
                      fontWeight: FontWeight.w600,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                _button(
                  context,
                  label: "Edit ${m.name}'s card",
                  accent: true,
                  onPressed: () => onEditMember(m),
                ),
                const SizedBox(width: 8),
                _button(
                  context,
                  label: 'Remove…',
                  danger: true,
                  onPressed: cast.onRemove == null
                      ? null
                      : () => cast.onRemove!(m),
                ),
              ],
            ),
          ),
        const SizedBox(height: 4),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _button(
              context,
              label: '+ Add a character',
              accent: true,
              onPressed: cast.onAdd,
            ),
            _button(
              context,
              label: 'Bring back a removed member',
              onPressed: cast.onBringBack,
            ),
          ],
        ),
      ],
    );
  }
}

/// Details 2: Turns (group-only): turn order, auto-advance and whether the
/// group starts in Director Mode.
class EditGroupTurnsCard extends StatelessWidget {
  const EditGroupTurnsCard({
    super.key,
    required this.draft,
    required this.onChanged,
  });

  final EditGroupDraft draft;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final kit = EditCharacterFormKit(context);
    return kit.sectionCard(
      icon: Icons.swap_horiz,
      title: 'Turns',
      color: AppColors.porchAmberOf(context),
      children: [
        kit.fieldLabel('Turn order'),
        const SizedBox(height: 8),
        SegmentedButton<TurnOrder>(
          key: const Key('group-turn-order'),
          showSelectedIcon: false,
          segments: [
            for (final t in TurnOrder.values)
              ButtonSegment(value: t, label: Text(t.label)),
          ],
          selected: {draft.turnOrder},
          onSelectionChanged: (s) {
            draft.turnOrder = s.first;
            onChanged();
          },
        ),
        const SizedBox(height: 12),
        SwitchListTile(
          key: const Key('group-auto-advance'),
          contentPadding: EdgeInsets.zero,
          title: const Text('Auto-advance'),
          subtitle: const Text(
            'After a character finishes responding, automatically prompt the '
            'next speaker. Works with both turn orders and Director Mode.',
          ),
          value: draft.autoAdvance,
          onChanged: (v) {
            draft.autoAdvance = v;
            onChanged();
          },
        ),
        SwitchListTile(
          key: const Key('group-director-mode'),
          contentPadding: EdgeInsets.zero,
          title: const Text('Start this group in Director Mode'),
          subtitle: const Text(
            'New chats open with you directing the scene instead of taking '
            'part in it.',
          ),
          value: draft.directorMode,
          onChanged: (v) {
            draft.directorMode = v;
            onChanged();
          },
        ),
      ],
    );
  }
}

/// Details 3: Voice. One line and no control: each member speaks in the
/// voice set in their card.
class EditGroupVoiceCard extends StatelessWidget {
  const EditGroupVoiceCard({super.key, required this.members});

  final List<CharacterCard> members;

  @override
  Widget build(BuildContext context) {
    final kit = EditCharacterFormKit(context);
    final voices = members
        .map(
          (m) =>
              '${m.name} · ${(m.ttsVoice ?? '').isEmpty ? 'Global voice' : m.ttsVoice}',
        )
        .join(', ');
    return kit.sectionCard(
      icon: Icons.record_voice_over_outlined,
      title: 'Voice',
      color: AppColors.porchAmberOf(context),
      children: [
        Text(
          'Each member speaks in their own text-to-speech voice, set in their '
          'card: $voices',
          key: const Key('group-voice-line'),
          style: TextStyle(
            color: AppColors.textSecondary(context),
            fontSize: 13,
          ),
        ),
      ],
    );
  }
}
