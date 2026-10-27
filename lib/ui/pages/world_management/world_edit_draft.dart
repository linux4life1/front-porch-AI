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

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/chat/chat.dart';
import 'package:front_porch_ai/services/world_store/world_store.dart';

/// Editable draft for the create/edit World dialog. One instance per
/// dialog session; the sections mutate its fields inside the dialog's
/// StatefulBuilder setState. Every field keeps the world's value (or the
/// create-time default) until Save copies it back onto the [World].
class WorldEditDraft {
  WorldEditDraft(World? world, {this.startingPlaceId})
    : nameController = TextEditingController(text: world?.name ?? ''),
      descController = TextEditingController(text: world?.description ?? ''),
      customBiomeJson = world?.biomeJson,
      injectDescription = world?.injectDescription ?? true,
      climateEnabled = world?.climateEnabled ?? true,
      coverImage = world?.coverImage,
      parentWorldId = world?.parentWorldId,
      startParentWorldId = world?.parentWorldId,
      atmosphere = world?.atmosphere ?? WorldAtmosphere.breathable,
      gravity = world?.gravity ?? WorldGravity.earth,
      editingEntries = world != null
          ? world.lorebook.entries.map((e) => e.clone()).toList()
          : <LorebookEntry>[],
      // 'custom' sentinel = this world authors its own climate (biomeJson).
      selectedBiomeId = world?.biomeJson != null
          ? 'custom'
          : (world?.biomeId ?? Biome.temperate.id) {
    _start = _fingerprint();
  }

  late String _start;

  /// Re-anchor "unchanged" to the draft as it now stands — the Create-with-
  /// a-preset-parent path uses this so a dialog nobody edited does not
  /// trigger the unsaved-changes guard for the preset itself.
  void resetCleanBaseline() => _start = _fingerprint();

  /// Everything Save copies back, so Close can tell whether anything changed.
  String _fingerprint() => jsonEncode([
    nameController.text,
    descController.text,
    customBiomeJson,
    selectedBiomeId,
    injectDescription,
    climateEnabled,
    coverImage,
    parentWorldId,
    startingPlaceId,
    startNameController.text,
    startDescController.text,
    atmosphere.name,
    gravity.name,
    [for (final e in editingEntries) e.toJson()],
  ]);

  bool get isDirty => _fingerprint() != _start;

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
  // Locations slice 3: the parent this place sits inside (null = root).
  // 'Inherit from <parent>' in the climate section is simply
  // climateEnabled=false — slice 2's chain walk finds the author; 'Own
  // climate' is climateEnabled=true. One flag, no second source of truth.
  String? parentWorldId;
  // Set only when this dialog session actually reparents — the "what
  // changes for live chats" note is about the change being made, not a
  // fact the world has always had.
  late final String? startParentWorldId;
  bool get willReparent => parentWorldId != startParentWorldId;
  // Shown under the picker when saveWorld refuses the parent (cycle,
  // unknown, or a re-run race).
  String? parentError;
  // Where chats in this world start (top-level worlds only): a place
  // already inside it, '' for "a new place" named below, or null when none
  // is picked yet. A new world always names a new place.
  String? startingPlaceId;
  final TextEditingController startNameController = TextEditingController();
  final TextEditingController startDescController = TextEditingController();
  // Shown under the starting-place picker or name when Save is refused;
  // [revealStart] asks the section to scroll itself into view once.
  String? startError;
  bool revealStart = false;

  /// The starting place as the author has chosen it so far, or null.
  StartingPlaceChoice? get startingChoice {
    final id = startingPlaceId;
    if (id != null && id.isNotEmpty) return StartAtExistingPlace(id);
    final name = startNameController.text.trim();
    return name.isEmpty
        ? null
        : StartAtNewPlace(name, description: startDescController.text);
  }

  // Place traits (standing facts; defaults are silent).
  WorldAtmosphere atmosphere;
  WorldGravity gravity;
  // Full clones -- the old 6-field copy stripped imported ST metadata
  // (secondary keys, probability, timers, ...) every time a world was
  // opened for editing and saved.
  final List<LorebookEntry> editingEntries;
}
