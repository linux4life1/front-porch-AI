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
import 'package:front_porch_ai/services/chat/chat.dart';

/// Editable draft for the create/edit World dialog. One instance per
/// dialog session; the sections mutate its fields inside the dialog's
/// StatefulBuilder setState. Every field keeps the world's value (or the
/// create-time default) until Save copies it back onto the [World].
class WorldEditDraft {
  WorldEditDraft(World? world)
    : nameController = TextEditingController(text: world?.name ?? ''),
      descController = TextEditingController(text: world?.description ?? ''),
      customBiomeJson = world?.biomeJson,
      injectDescription = world?.injectDescription ?? true,
      climateEnabled = world?.climateEnabled ?? true,
      coverImage = world?.coverImage,
      atmosphere = world?.atmosphere ?? WorldAtmosphere.breathable,
      gravity = world?.gravity ?? WorldGravity.earth,
      editingEntries = world != null
          ? world.lorebook.entries.map((e) => e.clone()).toList()
          : <LorebookEntry>[],
      // 'custom' sentinel = this world authors its own climate (biomeJson).
      selectedBiomeId = world?.biomeJson != null
          ? 'custom'
          : (world?.biomeId ?? Biome.temperate.id);

  final TextEditingController nameController;
  final TextEditingController descController;
  // Shown under the name field after a save with no name.
  String? nameError;
  // Climate default for chats that attach this place (Living Worlds).
  String? customBiomeJson;
  String? selectedBiomeId;
  bool injectDescription;
  bool climateEnabled;
  String? coverImage;
  // Place traits (standing facts; defaults are silent).
  WorldAtmosphere atmosphere;
  WorldGravity gravity;
  // Full clones -- the old 6-field copy stripped imported ST metadata
  // (secondary keys, probability, timers, ...) every time a world was
  // opened for editing and saved.
  final List<LorebookEntry> editingEntries;
}
