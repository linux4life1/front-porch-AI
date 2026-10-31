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
    this.onOpenNeeds,
    this.start,
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

  /// Where the member starts in new chats of the group. Null when the
  /// group's new chats start without Realism (no member seeds).
  final GroupMemberStart? start;

  /// Saves a changed [start] to the group's seed for this member.
  final Future<void> Function(GroupMemberStart start)? saveStart;

  /// Porch Life lets the Realism Engine run. False hides the member's
  /// Realism, Needs and Afterglow behind a note; their settings are kept.
  /// No builder passes it yet: Porch Life's `realismDefault` only starts new
  /// chats with Realism on (off for most people) and never stops a group's
  /// Realism, so it cannot stand for "not allowed". The Realism permission
  /// (`realismSettings.realismAllowed`) is what the builders pass once it
  /// lands.
  final bool realismAllowed;
}

/// The group's own lines for a member's Realism form, from [values].
MemberGroupRows memberGroupRows(
  BuildContext context,
  MemberGroupView view,
  GroupWideValues values, {
  required String memberName,
}) {
  String on(bool v) => v ? 'On' : 'Off';
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
          text: 'Realism Engine · ${on(values.realism)} for this group',
          linkLabel: view.linkLabel,
          onOpen: realismLink,
        ),
        GroupWideLine(
          icon: Icons.schedule,
          text: 'Time & Day · shared by the group: ${values.timeLabel}',
          linkLabel: view.linkLabel,
          onOpen: realismLink,
        ),
      ],
    ),
    chaos: GroupWideLine(
      icon: Icons.casino,
      text: 'Chaos Mode · ${on(values.chaos)} for this group',
      linkLabel: view.linkLabel,
      onOpen: realismLink,
    ),
    afterglow: GroupWideLine(
      icon: Icons.local_fire_department,
      text: 'Afterglow · ${on(values.afterglow)} for this group',
      linkLabel: view.linkLabel,
      onOpen: realismLink,
    ),
    startNote: 'Where $memberName starts in new chats of this group.',
  );
}

/// The group's Needs line for a member's Needs form.
Widget memberGroupNeedsLine(
  BuildContext context,
  MemberGroupView view,
  GroupWideValues values,
) => GroupWideLine(
  icon: Icons.battery_std,
  text: 'Needs · ${values.needs ? 'On' : 'Off'} for this group',
  linkLabel: view.linkLabel,
  onOpen: view.onOpenNeeds == null ? null : () => view.onOpenNeeds!(context),
);

/// What the Dialogue, Lorebook and Worlds tabs say a group does with a
/// member's own [greeting] seeds, [lorebook] and [worlds].
typedef MemberTabNotes = ({String greeting, String lorebook, String worlds});

MemberTabNotes memberTabNotes(String typedName, GroupWideValues values) {
  final name = typedName.trim().isEmpty ? 'This member' : typedName.trim();
  final setting = values.settingName;
  return (
    greeting: 'Used when this greeting opens a chat of this group.',
    lorebook:
        "$name's lorebook. The group reads it when Group Settings → Lorebook "
        '& Worlds has "Inherit character lorebooks" on; it is '
        '${values.readsMemberLorebooks ? 'on' : 'off'} for this group.',
    worlds:
        '${setting == null ? 'This group has no Setting world yet.' : 'This group meets in $setting.'} '
        "A member's own worlds aren't used in a group; the group's world is "
        'set in Group Settings.',
  );
}
