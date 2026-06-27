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

import 'package:front_porch_ai/models/lorebook.dart';
import 'package:front_porch_ai/models/world.dart';
import 'package:front_porch_ai/services/character_repository.dart';
import 'package:front_porch_ai/services/world_repository.dart';
import 'package:front_porch_ai/services/web/util/lorebook_json.dart';

/// Thin adapter for world (shared lorebook) CRUD over [WorldRepository] — the
/// same `saveWorld`/`deleteWorld` the desktop uses. Worlds are keyed by name.
///
/// The optional [_characters] repository lets [list] resolve a linked world's
/// character to its database id so the web UI can reuse the existing
/// `/api/characters/<id>/avatar` route for the world's portrait — no new image
/// endpoint and no client-supplied paths (best security posture).
class WorldFacade {
  WorldFacade(this._worlds, [this._characters]);

  final WorldRepository _worlds;
  final CharacterRepository? _characters;

  List<Map<String, dynamic>> list() {
    // Build a single name→dbId index so the per-world map below is O(1) and we
    // avoid a nested scan per world.
    final idByName = <String, String>{};
    final repo = _characters;
    if (repo != null) {
      for (final c in repo.characters) {
        final id = c.dbId;
        if (id != null) idByName.putIfAbsent(c.name, () => id);
      }
    }
    return _worlds.worlds.map((w) {
      final linkedName = w.linkedCharacterName;
      return {
        'name': w.name,
        'description': w.description,
        'entryCount': w.lorebook.entries.length,
        'linkedCharacterName': linkedName,
        'linkedCharacterId': linkedName != null ? idByName[linkedName] : null,
      };
    }).toList();
  }

  Map<String, dynamic>? detail(String name) {
    for (final w in _worlds.worlds) {
      if (w.name == name) {
        return {
          'name': w.name,
          'description': w.description,
          'linkedCharacterName': w.linkedCharacterName,
          'entries': lorebookEntriesToJson(w.lorebook),
        };
      }
    }
    return null;
  }

  /// Create or update a world. `originalName` (when it differs from `name`)
  /// signals a rename — the old record is deleted first since worlds are keyed
  /// by name. Returns false on a blank name.
  Future<bool> save(Map<String, dynamic> f) async {
    final name = f['name']?.toString().trim() ?? '';
    if (name.isEmpty) return false;
    final original = f['originalName']?.toString();
    if (original != null && original.isNotEmpty && original != name) {
      for (final w in _worlds.worlds) {
        if (w.name == original) {
          await _worlds.deleteWorld(w);
          break;
        }
      }
    }
    await _worlds.saveWorld(
      World(
        name: name,
        description: f['description']?.toString() ?? '',
        lorebook: buildLorebookFromJson(f['entries']) ?? Lorebook(entries: []),
      ),
    );
    return true;
  }

  Future<bool> delete(String name) async {
    for (final w in _worlds.worlds) {
      if (w.name == name) {
        await _worlds.deleteWorld(w);
        return true;
      }
    }
    return false;
  }

  /// Import a world from an uploaded JSON body (SillyTavern / Chub.ai / Front
  /// Porch). Mirrors the desktop [WorldRepository.importWorld] structural check
  /// and reuses [World.fromJson] for tolerant cross-format normalization, but
  /// never touches the client filesystem — the body is the already-parsed,
  /// size-capped JSON object. Returns false on an invalid structure (→ 400) so
  /// a random JSON upload can't create a junk world.
  Future<bool> importWorld(Map<String, dynamic> json) async {
    // A valid lorebook file carries entries either at the top level (ST/Chub)
    // or under a `lorebook` wrapper (Front Porch). Reject anything else.
    if (json['entries'] == null && json['lorebook'] == null) return false;
    try {
      final world = World.fromJson(json);
      if (world.name.trim().isEmpty) return false;
      await _worlds.saveWorld(world);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Export the named world as a Front Porch world JSON map (the same shape the
  /// desktop writes via [WorldRepository.exportWorld]). The browser owns the
  /// actual file download. Returns null when no world matches (→ 404).
  Map<String, dynamic>? exportWorld(String name) {
    for (final w in _worlds.worlds) {
      if (w.name == name) return w.toJson();
    }
    return null;
  }
}
