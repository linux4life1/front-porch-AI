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

import 'package:front_porch_ai/services/group_member_values.dart';
import 'package:front_porch_ai/ui/pages/edit_character_page/edit_character_form_kit.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';
import 'package:front_porch_ai/ui/widgets/relationship_scale.dart';

/// The tooltips of the greyed-out pieces in a member's editor.
const kTimeDayLockedTooltip = 'Time & Day is set per group, not per character.';
const kWorldsLockedTooltip = 'Worlds are set per group, not per character.';
const kChaosLockedTooltip = 'Chaos Mode is set per group for now.';

/// Member mode of the character editor: the editor is opened on a member's
/// own copy in [groupName]. It only adds the notice and the "In the group"
/// section and greys out Time & Day, Worlds and Chaos Mode; every other
/// piece is the 1:1 editor's.
class GroupMemberMode {
  const GroupMemberMode({
    required this.groupName,
    required this.memberId,
    required this.others,
    required this.scene,
    required this.values,
    required this.saveValues,
    this.realismAllowed = true,
  });

  final String groupName;
  final String memberId;
  final List<GroupMemberRef> others;
  final GroupSceneTime scene;

  /// The group's values for this member as the editor opens.
  final GroupMemberValues values;

  /// Stores moved [GroupMemberValues] on the group (never on the library).
  final Future<void> Function(GroupMemberValues values) saveValues;

  /// Porch Life lets the Realism Engine run; false hides the member's
  /// Realism, Needs and Afterglow behind a note.
  final bool realismAllowed;
}

/// A full-width notice at the top of the Details tab: accent border, people
/// icon, a bold line and a body. The member editor says whose copy this is;
/// the 1:1 editor says a character is also in groups.
class GroupCopyNotice extends StatelessWidget {
  const GroupCopyNotice({
    super.key,
    required this.body,
    this.title,
    this.noticeKey,
  });

  final String? title;
  final String body;
  final Key? noticeKey;

  @override
  Widget build(BuildContext context) {
    final accent = AppColors.formAccentOf(context);
    return Container(
      key: noticeKey,
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: accent.withValues(alpha: 0.6)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.people_outline, size: 20, color: accent),
          const SizedBox(width: 10),
          Expanded(
            child: Text.rich(
              TextSpan(
                children: [
                  if (title != null)
                    TextSpan(
                      text: '$title\n',
                      style: TextStyle(
                        color: AppColors.textPrimary(context),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  TextSpan(text: body),
                ],
              ),
              style: TextStyle(
                color: AppColors.textSecondary(context),
                fontSize: 13,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A1: the member editor's notice.
Widget groupMemberNotice(String member, String group) => GroupCopyNotice(
  noticeKey: const Key('group-member-notice'),
  title: "You're editing $member in $group only.",
  body:
      'This group keeps its own copy of $member. Changes here don\'t affect '
      "your solo chats with $member, and edits to $member's own card don't "
      'reach this group.',
);

/// "The Porch Trio and Book Club", as a sentence lists [names].
String joinGroupNames(List<String> names) => switch (names.length) {
  0 => '',
  1 => names.first,
  2 => '${names[0]} and ${names[1]}',
  _ => '${names.sublist(0, names.length - 1).join(', ')} and ${names.last}',
};

/// C: the 1:1 editor's line when [character] is in [groups]; nothing when
/// it is in none.
Widget characterInGroupsNote(String character, List<String> groups) =>
    groups.isEmpty
    ? const SizedBox.shrink()
    : GroupCopyNotice(
        noticeKey: const Key('character-in-groups-note'),
        body:
            '$character is also in ${joinGroupNames(groups)}. Groups keep '
            "their own copy; changes here don't reach them.",
      );

/// A4: "In the group", the group-only section at the end of the Details tab,
/// built from the 1:1 section widgets.
class GroupMemberSection extends StatefulWidget {
  const GroupMemberSection({
    super.key,
    required this.mode,
    required this.memberName,
    required this.values,
    required this.onChanged,
  });

  final GroupMemberMode mode;
  final String memberName;
  final GroupMemberValues values;
  final ValueChanged<GroupMemberValues> onChanged;

  @override
  State<GroupMemberSection> createState() => _GroupMemberSectionState();
}

class _GroupMemberSectionState extends State<GroupMemberSection> {
  late final _prompt = TextEditingController(text: widget.values.systemPrompt);
  late final _note = TextEditingController(text: widget.values.note);

  @override
  void dispose() {
    _prompt.dispose();
    _note.dispose();
    super.dispose();
  }

  GroupMemberValues get _v => widget.values;

  void _emit(GroupMemberValues next) => widget.onChanged(next);

  @override
  Widget build(BuildContext context) {
    final kit = EditCharacterFormKit(context);
    final name = widget.memberName;
    final accent = AppColors.formAccentOf(context);
    final helper = TextStyle(
      color: AppColors.textTertiary(context),
      fontSize: 11,
    );
    return kit.sectionCard(
      icon: Icons.people_outline,
      title: 'In ${widget.mode.groupName}',
      color: accent,
      children: [
        TextField(
          key: const Key('group-member-system-prompt'),
          controller: _prompt,
          style: TextStyle(color: AppColors.textPrimary(context), fontSize: 14),
          decoration: kit.inputDecoration('System prompt in this group'),
          onChanged: (t) => _emit(_v.copyWith(systemPrompt: t)),
        ),
        const SizedBox(height: 6),
        Text(
          'Blank uses the System Prompt under Advanced Prompts.',
          style: helper,
        ),
        const SizedBox(height: 16),
        kit.fieldLabel("Author's note when $name speaks"),
        const SizedBox(height: 8),
        TextField(
          key: const Key('group-member-note'),
          controller: _note,
          style: TextStyle(color: AppColors.textPrimary(context), fontSize: 14),
          decoration: kit.inputDecoration("Author's note when $name speaks"),
          onChanged: (t) => _emit(_v.copyWith(note: t)),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Text('Strength · ${_v.strength}', style: helper),
            Expanded(
              child: Slider(
                key: const Key('group-member-strength'),
                value: _v.strength.toDouble(),
                min: 1,
                max: 10,
                divisions: 9,
                onChanged: (x) => _emit(_v.copyWith(strength: x.round())),
              ),
            ),
          ],
        ),
        if (widget.mode.others.isNotEmpty) ...[
          const SizedBox(height: 16),
          kit.fieldLabel('How $name starts out feeling about the others'),
          const SizedBox(height: 8),
          for (final other in widget.mode.others)
            _feeling(context, other, helper),
          Text(
            'New chats only. Same values the Edit group page shows for $name.',
            style: helper,
          ),
        ],
      ],
    );
  }

  Widget _feeling(
    BuildContext context,
    GroupMemberRef other,
    TextStyle helper,
  ) {
    final score = _v.feelings[other.id] ?? 0;
    return Row(
      children: [
        SizedBox(
          width: 150,
          child: Text(
            'Toward ${other.name} · ${relationshipTierName(score)}',
            style: helper,
          ),
        ),
        Expanded(
          child: Slider(
            key: Key('group-member-feeling-${other.id}'),
            value: score.toDouble().clamp(-300, 300),
            min: -300,
            max: 300,
            divisions: 120,
            onChanged: (x) => _emit(
              _v.copyWith(feelings: {..._v.feelings, other.id: x.round()}),
            ),
          ),
        ),
      ],
    );
  }
}
