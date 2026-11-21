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

import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/group_member_start_overlay.dart';
import 'package:front_porch_ai/utils/utils.dart';

/// Another member of the group, for "how Ana starts out feeling about" them.
class GroupMemberRef {
  const GroupMemberRef(this.id, this.name);
  final String id;
  final String name;
}

/// The shared scene a group sets for everyone (Edit group → Realism
/// Engine), shown read-only in a member's greyed Time & Day.
class GroupSceneTime {
  const GroupSceneTime({
    this.timeOfDay = 'morning',
    this.dayCount = 1,
    this.storyStartDate,
    this.storyStartTime,
  });
  final String timeOfDay;
  final int dayCount;
  final String? storyStartDate;
  final String? storyStartTime;
}

/// The values the group stores for a member that the character editor also
/// shows in "In the group": the system prompt for this group, the Author's
/// Note with its Strength, and how they start out feeling about each other
/// member (score by that member's id). The same values Edit group shows.
class GroupMemberValues {
  const GroupMemberValues({
    this.systemPrompt = '',
    this.note = '',
    this.strength = 4,
    this.feelings = const {},
  });

  final String systemPrompt;
  final String note;
  final int strength;
  final Map<String, int> feelings;

  GroupMemberValues copyWith({
    String? systemPrompt,
    String? note,
    int? strength,
    Map<String, int>? feelings,
  }) => GroupMemberValues(
    systemPrompt: systemPrompt ?? this.systemPrompt,
    note: note ?? this.note,
    strength: strength ?? this.strength,
    feelings: feelings ?? this.feelings,
  );

  @override
  bool operator ==(Object other) =>
      other is GroupMemberValues &&
      other.systemPrompt == systemPrompt &&
      other.note == note &&
      other.strength == strength &&
      other.feelings.length == feelings.length &&
      other.feelings.entries.every((e) => feelings[e.key] == e.value);

  @override
  int get hashCode => Object.hash(
    systemPrompt,
    note,
    strength,
    Object.hashAllUnordered(feelings.entries.map((e) => (e.key, e.value))),
  );
}

/// The shared scene [group] starts new chats in, for a member's greyed
/// Time & Day: its time of day and day number, and its story start.
GroupSceneTime groupSceneOf(GroupChat group) {
  final seed = parseGroupTimeSeedOf(group);
  return seed == null
      ? const GroupSceneTime()
      : GroupSceneTime(
          timeOfDay: seed.timeOfDay,
          dayCount: seed.dayCount,
          storyStartDate: seed.storyStartDate,
          storyStartTime: seed.storyStartTime,
        );
}

/// What [group] stores for member [mid] that the member's editor shows in
/// its "In the group" section and Edit group shows too: one store, read by
/// both. Feelings the starting-feelings key holds win; a member's own
/// `relationships` map in an older seed fills the rest.
GroupMemberValues groupMemberValuesOf(GroupChat group, String mid) {
  final note = group.characterAuthorNotes[mid];
  final stored = parseGroupRealismSeeds(group.defaultMemberRealismState)[mid];
  final legacy = stored?['relationships'];
  return GroupMemberValues(
    systemPrompt: group.characterSystemPrompts[mid] ?? '',
    note: note?.note ?? '',
    strength: note?.strength ?? 4,
    feelings: {
      if (legacy is Map)
        for (final e in legacy.entries)
          if (e.value is num) '${e.key}': (e.value as num).toInt(),
      ...?startingFeelingsIn(group.defaultMemberRealismState)[mid],
    },
  );
}

/// Lays [values] for member [mid] onto [group]: the system prompt for this
/// group, the Author's Note and Strength, and every feeling that moved. A
/// blank prompt or note is dropped, as Edit group's Save drops it. Nothing
/// else on the group changes.
void applyGroupMemberValues(
  GroupChat group,
  String mid,
  GroupMemberValues values,
) {
  final prompt = values.systemPrompt.trim();
  if (prompt.isEmpty) {
    group.characterSystemPrompts.remove(mid);
  } else {
    group.characterSystemPrompts[mid] = prompt;
  }
  final note = values.note.trim();
  if (note.isEmpty) {
    group.characterAuthorNotes.remove(mid);
  } else {
    group.characterAuthorNotes[mid] = MemberAuthorNote(
      note,
      values.strength.clamp(1, 10),
    );
  }
  final before = groupMemberValuesOf(group, mid).feelings;
  for (final e in values.feelings.entries) {
    if (before[e.key] == e.value) continue;
    group.defaultMemberRealismState = withStartingFeeling(
      group.defaultMemberRealismState,
      from: mid,
      to: e.key,
      score: e.value,
    );
  }
}
