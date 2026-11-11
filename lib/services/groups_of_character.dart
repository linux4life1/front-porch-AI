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

import 'package:flutter/foundation.dart';

import 'package:front_porch_ai/database/database.dart'
    show AppDatabase, AppDatabaseGroupQueries;
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/utils/utils.dart';

/// The names of the groups [character] (a library character) is a member of,
/// by the origin each member's copy records, in the order the groups list.
/// A failed read is logged and reads as none: the 1:1 editor then shows no
/// line, as it would for a character in no group.
Future<List<String>> groupNamesOfCharacter(
  AppDatabase db,
  CharacterCard character,
) async {
  final stable = character.stableGroupId;
  final dbId = character.dbId;
  final names = <String>[];
  try {
    for (final group in await db.getAllGroups()) {
      final members = await db.getGroupMembers(group.id);
      final inIt = members.any((row) {
        final m = GroupMember.fromRow(row);
        return (dbId != null && m.originLibraryDbId == dbId) ||
            m.originStableId == stable;
      });
      if (inIt) names.add(group.name);
    }
  } catch (e) {
    debugPrint('[EditCharacter] could not read the character\'s groups: $e');
    return const [];
  }
  return names;
}
