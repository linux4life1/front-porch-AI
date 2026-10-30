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
import 'package:front_porch_ai/services/world_repository.dart';
import 'package:front_porch_ai/services/world_store/world_store.dart';

/// Where [card]'s new 1:1 chats meet, for the web picker: the Setting (a
/// world, or a place inside one), the lore-only worlds, and, for an unsplit
/// card linking several worlds, how many (the two-roles banner).
Map<String, dynamic> characterWorldsJson(
  CharacterCard? card,
  WorldRepository? worlds,
) {
  final choice = card == null || worlds == null
      ? const GroupWorldChoice()
      : characterWorldChoiceIn(card, worlds);
  return {
    'settingId': choice.settingId,
    'loreIds': choice.loreIds,
    'legacyWorldCount': card != null && characterNeedsWorldSplitNotice(card)
        ? card.worldNames.length
        : 0,
  };
}

/// Apply a posted `{settingId, loreIds}` to [card] with the desktop
/// editor's rule: a choice equal to what the card holds today leaves an
/// unsplit card's stored worlds alone; any change writes the split. Ids the
/// library does not know are dropped. Anything else in [raw] is ignored.
void applyCharacterWorlds(
  CharacterCard card,
  Object? raw,
  WorldRepository? worlds,
) {
  if (raw is! Map || worlds == null) return;
  bool known(Object? id) => id is String && worlds.worldById(id) != null;
  final setting = raw['settingId'];
  final lore = raw['loreIds'];
  final chosen = GroupWorldChoice(
    settingId: known(setting) ? setting as String : null,
    loreIds: [
      if (lore is List)
        for (final id in lore)
          if (known(id) && id != setting) id as String,
    ],
  );
  final saved = groupWorldFieldsToSave(
    storedWorldIds: card.worldNames,
    storedLoreWorldIds: card.loreWorldNames,
    chosen: chosen,
    asLoaded: characterWorldChoiceIn(card, worlds),
  );
  card.worldNames = saved.worldIds;
  card.loreWorldNames = saved.loreWorldIds;
}
