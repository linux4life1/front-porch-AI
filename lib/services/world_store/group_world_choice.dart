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

import 'package:front_porch_ai/models/group_chat.dart';
import 'package:front_porch_ai/models/world.dart';
import 'package:front_porch_ai/services/world_chain.dart';

/// Where a group's new chats meet: one Setting and any lore-only worlds.
///
/// [settingId] is a top-level world (new chats start at its starred place)
/// or a place inside one (they start there); null is no world at all.
/// [loreIds] add their lorebooks as Lore slots and never the weather.
class GroupWorldChoice {
  const GroupWorldChoice({this.settingId, this.loreIds = const []});

  final String? settingId;
  final List<String> loreIds;

  /// The group fields this choice writes. Writing `loreWorldIds` (even
  /// empty) marks the group as split, so new chats seed Setting and Lore
  /// apart instead of letting climate pick.
  ({List<String> worldIds, List<String> loreWorldIds}) get fields => (
    worldIds: [?settingId],
    loreWorldIds: [
      for (final id in loreIds)
        if (id != settingId) id,
    ],
  );

  @override
  bool operator ==(Object other) {
    if (other is! GroupWorldChoice ||
        other.settingId != settingId ||
        other.loreIds.length != loreIds.length) {
      return false;
    }
    for (var i = 0; i < loreIds.length; i++) {
      if (other.loreIds[i] != loreIds[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(settingId, Object.hashAll(loreIds));
}

/// What [group]'s new chats get today, as a choice an editor can show.
///
/// A split group reads its own fields. An unsplit one (loreWorldIds null)
/// is read the way the flat seed treats it: each ref takes its starred
/// place, the first that starts at a place or has a climate becomes the
/// Setting, and the rest are Lore. Saving that choice unchanged therefore
/// seeds the same slots the group seeded before.
GroupWorldChoice groupWorldChoiceOf(
  GroupChat group, {
  required World? Function(String idOrName) resolve,
  required World? Function(String id) lookup,
  required World? Function(String id) climateAuthorFor,
}) {
  final lore = group.loreWorldIds;
  if (lore != null) {
    final setting = group.worldIds.isEmpty
        ? null
        : resolve(group.worldIds.first)?.id;
    return GroupWorldChoice(
      settingId: setting,
      loreIds: [
        for (final ref in lore)
          if (resolve(ref)?.id case final id? when id != setting) id,
      ],
    );
  }
  String? setting;
  final rest = <String>[];
  final seen = <String>{};
  for (final ref in group.worldIds) {
    final w = resolve(ref);
    if (w == null) continue;
    final start = startingPlaceOf(w, lookup);
    final startsInside = topWorldOf(start, lookup).id != start.id;
    final slot = startsInside ? start.id : w.id;
    if (!seen.add(slot)) continue;
    if (setting == null && (startsInside || climateAuthorFor(slot) != null)) {
      setting = w.id;
    } else {
      rest.add(w.id);
    }
  }
  return GroupWorldChoice(settingId: setting, loreIds: rest);
}

/// An unsplit group that links more than one world: its editor explains
/// that worlds now have two roles, with today's split already filled in.
bool groupNeedsWorldSplitNotice(GroupChat group) =>
    group.loreWorldIds == null && group.worldIds.length > 1;
