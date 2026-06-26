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
import 'package:front_porch_ai/services/world_repository.dart';
import 'package:front_porch_ai/services/web/util/lorebook_json.dart';

/// Thin adapter for world (shared lorebook) CRUD over [WorldRepository] — the
/// same `saveWorld`/`deleteWorld` the desktop uses. Worlds are keyed by name.
class WorldFacade {
  WorldFacade(this._worlds);

  final WorldRepository _worlds;

  List<Map<String, dynamic>> list() => _worlds.worlds
      .map((w) => {
            'name': w.name,
            'description': w.description,
            'entryCount': w.lorebook.entries.length,
            'linkedCharacterName': w.linkedCharacterName,
          })
      .toList();

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
    await _worlds.saveWorld(World(
      name: name,
      description: f['description']?.toString() ?? '',
      lorebook: buildLorebookFromJson(f['entries']) ?? Lorebook(entries: []),
    ));
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
}
