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

import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/widgets/realism_form_section/realism_form_section.dart';

/// What a group member's editor shows of their group, and where it saves
/// the member's start. Built by the two ways in: the chat sidebar (the group
/// is open; [read] is the chat's own switches) and Edit group (its settings
/// for new chats).
class MemberGroupView {
  const MemberGroupView({
    required this.read,
    this.changes,
    this.linkLabel = 'Group Settings',
    this.onOpenRealism,
    this.onOpenChaos,
    this.onOpenNeeds,
    this.chaosWhere = 'set in Group Settings',
    this.loreWhere =
        'Group Settings → Lorebook & Worlds has "Inherit character lorebooks"',
    this.worldsWhere = 'Group Settings',
    this.start,
    this.startUpdates,
    this.noStartWhere = 'Edit group → Realism & Dynamics',
    this.saveStart,
    this.realismAllowed = true,
  });

  /// The group's switches now (read on every build).
  final GroupWideValues Function() read;

  /// Repaints the lines when the group's switches move (the open chat).
  final Listenable? changes;

  /// Where the links go ("Group Settings", "Realism & Dynamics").
  final String linkLabel;

  /// Opens where the group sets Realism, time, Chaos and Afterglow (from the
  /// editor's [BuildContext]); null shows the value without a link.
  final void Function(BuildContext context)? onOpenRealism;

  /// Opens where the group sets Needs; null shows it without a link.
  final void Function(BuildContext context)? onOpenNeeds;

  /// Opens where the open chat sets Chaos; null shows [chaosWhere] instead.
  /// A group's new chats have no such switch: their line says where their
  /// Chaos comes from.
  final void Function(BuildContext context)? onOpenChaos;
  final String chaosWhere;

  /// Where the member's way in sets the group's lorebook reading and its
  /// world, for the Lorebook and Worlds tabs' notes.
  final String loreWhere;
  final String worldsWhere;

  /// Where the member starts in new chats of the group, read from the
  /// persisted definition. Null when the group's new chats start without
  /// Realism (no member entries); [noStartWhere] then says where that is set.
  final GroupMemberStart? start;

  /// A fresh [start] after the persisted definition was read again (the
  /// editor's Group Settings link closed); the editor takes it unless the
  /// user has moved the start since.
  final ValueNotifier<GroupMemberStart?>? startUpdates;

  /// Releases [startUpdates]: the editor's opener calls it once the editor
  /// has closed.
  void dispose() => startUpdates?.dispose();

  /// Where the group's Realism for new chats is set, for the line shown in
  /// place of the start when there is none.
  final String noStartWhere;

  /// Saves a changed [start] to the group's seed for this member.
  final Future<void> Function(GroupMemberStart start)? saveStart;

  /// Porch Life lets the Realism Engine run (`realismSettings.realismAllowed`).
  /// False hides the member's Realism, Needs and Afterglow behind a note;
  /// their settings are kept.
  final bool realismAllowed;
}

/// The group's own lines for a member's Realism form, from [values].
MemberGroupRows memberGroupRows(
  BuildContext context,
  MemberGroupView view,
  GroupWideValues values, {
  required String memberName,
}) {
  // Each line says what it describes: opened from a chat, that chat's own
  // switches; from Edit group, how the group's new chats start.
  final scope = values.open ? 'in this chat' : "for this group's new chats";
  String on(bool v) => '${v ? 'On' : 'Off'} $scope';
  void Function()? link(void Function(BuildContext)? open) =>
      open == null ? null : () => open(context);
  final realismLink = link(view.onOpenRealism);
  return MemberGroupRows(
    header: Column(
      key: const Key('member-group-lines'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GroupWideLine(
          icon: Icons.psychology_alt_outlined,
          text: 'Realism Engine · ${on(values.realism)}',
          linkLabel: view.linkLabel,
          onOpen: realismLink,
        ),
        GroupWideLine(
          icon: Icons.schedule,
          text: values.open
              ? 'Time & Day · in this chat: ${values.timeLabel}'
              : "Time & Day · this group's new chats start at: "
                    '${values.timeLabel}',
          linkLabel: view.linkLabel,
          onOpen: realismLink,
        ),
      ],
    ),
    // A group's new chats take Chaos from Porch Life's default, else from
    // what the group was made with; no switch changes that afterwards.
    chaos: GroupWideLine(
      icon: Icons.casino,
      text: 'Chaos Mode · ${on(values.chaos)}',
      linkLabel: values.open && view.onOpenChaos != null
          ? 'Group Settings'
          : null,
      onOpen: values.open ? link(view.onOpenChaos) : null,
      where: values.open
          ? view.chaosWhere
          : values.chaosFromPorchLife
          ? "on because Porch Life's Chaos default is on"
          : 'the setting the group was made with',
    ),
    afterglow: GroupWideLine(
      icon: Icons.local_fire_department,
      text: 'Afterglow · ${on(values.afterglow)}',
      linkLabel: view.linkLabel,
      onOpen: realismLink,
    ),
    startNote: "Where $memberName starts in this group's new chats.",
    noStartNote:
        "This group's new chats start without Realism, so there's no start "
        'to set. Set in ${view.noStartWhere}.',
  );
}

/// The group's Needs line for a member's Needs form.
Widget memberGroupNeedsLine(
  BuildContext context,
  MemberGroupView view,
  GroupWideValues values,
) {
  // Porch Life off keeps the group's own Needs switch greyed: no link to it.
  final offInPorchLife = !values.open && values.needsOffInPorchLife;
  return GroupWideLine(
    icon: Icons.battery_std,
    text:
        'Needs · ${values.needs ? 'On' : 'Off'} '
        '${values.open ? 'in this chat' : "for this group's new chats"}',
    linkLabel: view.linkLabel,
    onOpen: view.onOpenNeeds == null || offInPorchLife
        ? null
        : () => view.onOpenNeeds!(context),
    where: offInPorchLife
        ? "Off in Porch Life, so no chat runs Needs. This group's choice for "
              'new chats is kept.'
        : null,
  );
}

/// What the editor says a group does with a member's own [greeting] seeds,
/// [lorebook], [worlds] and [scenario].
typedef MemberTabNotes = ({
  String greeting,
  String lorebook,
  String worlds,
  String scenario,
});

MemberTabNotes memberTabNotes(
  String typedName,
  GroupWideValues values,
  MemberGroupView view,
) {
  final name = typedName.trim().isEmpty ? 'This member' : typedName.trim();
  final setting = values.settingName;
  return (
    greeting: 'Used when this greeting opens a chat of this group.',
    lorebook:
        "$name's lorebook. The group reads it when ${view.loreWhere} on; "
        'it is ${values.readsMemberLorebooks ? 'on' : 'off'} for this group.',
    // A group turn reads the speaking member's own worlds' lore while the
    // group inherits character lorebooks (collectLoreEntryRefs); only the
    // Setting (place and weather) is the group's alone.
    worlds:
        '${setting == null ? 'This group has no Setting world yet' : 'This group meets in $setting'}: '
        "the group's world sets the place and weather, and is set in "
        '${view.worldsWhere}. While ${view.loreWhere} on, $name\'s own '
        'worlds add their lore when $name speaks; it is '
        '${values.readsMemberLorebooks ? 'on' : 'off'} for this group.',
    // The group scene is shared (the prompt's scenario block): the group's
    // own Scenario, or while it has none the first member's.
    scenario:
        'The group shares one scene: it uses its own Scenario, or, while it '
        "has none, its first member's.",
  );
}
