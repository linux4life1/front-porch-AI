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

import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/utils/utils.dart';

/// Per-card chat activity for the library grid's chips and the
/// 'recent' / 'messages' sorts.
typedef HomeLibraryActivity = ({
  Map<String, DateTime> lastActivity,
  Map<String, int> messageCounts,
});

/// Query the DB to build last activity time and message count per character.
///
/// Keys in the output maps are always the stableGroupId (image basename or sanitized name)
/// so they match what the grid and sort logic use via CharacterCard.stableGroupId.
///
/// We correlate via each library card's dbId because 1:1 sessions currently store the
/// integer dbId in sessions.character_id (post group overhaul). Group sessions (with
/// groupId set, character_id often null) do not contribute here — this is by design
/// for the decoupled model (group activity lives with the private group members).
Future<HomeLibraryActivity> loadHomeLibraryActivity(
  AppDatabase db,
  CharacterRepository charRepo,
) async {
  // Get counts and activity from DB (keys are whatever was stored in sessions.character_id,
  // currently the dbId for 1:1 sessions).
  final msgCounts = await db.getMessageCountsPerCharacter();
  final lastActivity = await db.getLastActivityPerCharacter();

  // Output maps MUST be keyed by stableGroupId (the value used for all lookups
  // in the grid for chips + 'recent'/'messages' sorting).
  final newMsgCount = <String, int>{};
  final newCache = <String, DateTime>{};

  for (final card in charRepo.characters) {
    final stableId = card.stableGroupId;
    if (card.dbId != null) {
      final dbKey = card.dbId!; // matches what is stored in sessions for 1:1
      if (msgCounts.containsKey(dbKey)) {
        newMsgCount[stableId] = msgCounts[dbKey]!;
      }
      if (lastActivity.containsKey(dbKey)) {
        newCache[stableId] = lastActivity[dbKey]!;
      }
    }
  }
  return (lastActivity: newCache, messageCounts: newMsgCount);
}

/// The file to show as [c]'s library card cover: the ★ starred gallery
/// avatar when set (same star-aware resolution the web library and card
/// exports already use — the gallery dialog promises "★ sets the default +
/// card cover"), else the portrait.
File resolveHomeCardImage(BuildContext context, CharacterCard c) {
  final repo = Provider.of<CharacterRepository>(context, listen: false);
  final cover = repo.coverImageFileFor(c);
  if (cover != null) return cover;
  final storage = Provider.of<StorageService>(context, listen: false);
  return storage.resolveCharacterImage(c.imagePath ?? '');
}
