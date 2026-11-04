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

// The draft→world copy the edit dialog runs after it has settled the
// name (rename or assign). One place owns which fields a save writes,
// so a new draft field cannot silently skip the save path.

import 'package:front_porch_ai/models/models.dart';

import 'world_ambience_section.dart';
import 'world_edit_draft.dart';

/// Copy every editable draft field onto [world]. The name is the
/// dialog's business (rename keeps stable UUIDs); everything the
/// sections bind lives here, in section order.
void applyDraftFields(World world, WorldEditDraft draft) {
  world.description = draft.descController.text.trim();
  world.climateEnabled = draft.climateEnabled;
  // Lorebook-only worlds leave climate fields untouched so a later
  // re-enable restores them.
  if (draft.climateEnabled) {
    // 'custom' ⇒ biomeJson carries the climate and biomeId clears; a
    // built-in clears any stale custom JSON (Biome.resolve prefers JSON).
    world.biomeId = draft.selectedBiomeId == 'custom'
        ? null
        : draft.selectedBiomeId;
    world.biomeJson = draft.selectedBiomeId == 'custom'
        ? draft.customBiomeJson
        : null;
    world.atmosphere = draft.atmosphere;
    world.gravity = draft.gravity;
  }
  world.injectDescription = draft.injectDescription;
  world.coverImage = draft.coverImage;
  world.parentWorldId = draft.parentWorldId;
  applyAmbience(draft, world);

  // Update lorebook entries
  world.lorebook.entries.clear();
  world.lorebook.entries.addAll(draft.editingEntries);
}
