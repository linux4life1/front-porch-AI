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
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:drift/drift.dart';
import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/models/world.dart' as model;
import 'package:front_porch_ai/models/lorebook.dart';
import 'package:front_porch_ai/models/lorebook_codec.dart';
import 'package:front_porch_ai/models/lorebook_export.dart';
import 'package:front_porch_ai/services/character_repository.dart';
import 'package:front_porch_ai/services/group_chat_repository.dart';
import 'package:front_porch_ai/services/storage_service.dart';

class WorldRepository extends ChangeNotifier {
  final StorageService _storageService;
  AppDatabase _db;
  final List<model.World> _worlds = [];
  bool _isLoading = false;

  // Optional CharacterRepository reference for loading avatar paths
  CharacterRepository? _characterRepository;

  List<model.World> get worlds => List.unmodifiable(_worlds);
  bool get isLoading => _isLoading;

  WorldRepository(this._storageService, this._db) {
    loadWorlds();
  }

  /// Set the CharacterRepository reference for loading avatar paths.
  ///
  /// This method should be called after dependency injection to enable
  /// automatic avatar path resolution for linked worlds.
  ///
  /// [repo] - The CharacterRepository instance to use for character lookups.
  void setCharacterRepository(CharacterRepository repo) {
    _characterRepository = repo;
    // Reload worlds to populate avatar paths
    loadWorlds();
  }

  /// Update the database reference (e.g. after cloud sync replaces the DB file).
  void updateDatabase(AppDatabase db) {
    _db = db;
  }

  /// Resolve avatar paths for worlds linked to characters.
  ///
  /// This method looks up each world's linked character and copies the
  /// character's avatar path to the world. This enables UI elements to
  /// display the actual character avatar instead of a generic globe icon.
  ///
  /// Steps:
  /// 1. If CharacterRepository is not available, skip avatar resolution
  /// 2. For each world with linkedCharacterName:
  ///    a. Look up the character by name in memory (fast, no DB query)
  ///    b. If found, copy the character's imagePath to world.avatarPath
  ///    c. If not found in memory, skip (will try on next load)
  ///
  /// This approach is efficient because:
  /// - Memory lookup is O(1) vs database query
  /// - Works with the existing in-memory character list
  /// - No additional database queries needed
  void _resolveAvatarPaths(List<model.World> worlds) {
    // If character repository is not available, skip avatar resolution
    if (_characterRepository == null) return;

    for (final world in worlds) {
      // Only resolve avatar paths for worlds linked to characters
      if (world.linkedCharacterName != null) {
        // Look up character in memory (fast, no DB query needed)
        final character = _characterRepository!.characters
            .where((c) => c.name == world.linkedCharacterName)
            .firstOrNull;

        // If character found and has avatar path, copy it to world
        if (character != null && character.imagePath != null) {
          world.avatarPath = character.imagePath;
        }
      }
    }
  }

  Future<void> loadWorlds() async {
    _isLoading = true;
    notifyListeners();

    try {
      await _storageService.initialized;
      final dbWorlds = await _db.getAllWorlds();
      _worlds.clear();

      for (final w in dbWorlds) {
        Lorebook lorebook;
        if (w.lorebook != null) {
          try {
            lorebook = Lorebook.fromJson(jsonDecode(w.lorebook!));
          } catch (_) {
            lorebook = Lorebook(entries: []);
          }
        } else {
          lorebook = Lorebook(entries: []);
        }

        _worlds.add(
          model.World(
            name: w.name,
            description: w.description,
            lorebook: lorebook,
            linkedCharacterName: w.linkedCharacterName,
          ),
        );
      }

      // Resolve avatar paths for linked worlds
      _resolveAvatarPaths(_worlds);
    } catch (e) {
      print('Error loading worlds: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Rename a world AND follow every reference to it. Characters attach
  /// worlds by name (worldNames) and groups by worldIds — before this,
  /// renaming silently orphaned all of them, and the old save path even
  /// inserted a duplicate row under the new name (lookup-by-new-name missed
  /// the existing row). Updates the existing row BY ID and rewrites the
  /// referencing characters/groups atomically from the caller's view.
  /// Throws [StateError] on a name collision.
  Future<void> renameWorld(
    model.World world,
    String newName, {
    GroupChatRepository? groupRepo,
  }) async {
    final trimmed = newName.trim();
    final oldName = world.name;
    if (trimmed.isEmpty || trimmed == oldName) return;
    if (await _db.getWorldByName(trimmed) != null) {
      throw StateError('A world named "$trimmed" already exists.');
    }

    final existing = await _db.getWorldByName(oldName);
    if (existing != null) {
      await _db.updateWorld(
        WorldsCompanion(
          id: Value(existing.id),
          name: Value(trimmed),
          description: Value(existing.description),
          lorebook: Value(existing.lorebook),
          linkedCharacterName: Value(existing.linkedCharacterName),
        ),
      );
    }
    world.name = trimmed;

    // Follow character attachments (persisted via the normal update path so
    // the PNG-embedded card data stays consistent too).
    final charRepo = _characterRepository;
    if (charRepo != null) {
      for (final c in List.of(charRepo.characters)) {
        if (c.worldNames.contains(oldName)) {
          c.worldNames = [
            for (final n in c.worldNames) n == oldName ? trimmed : n,
          ];
          await charRepo.updateCharacter(c);
        }
      }
    }

    // Follow group attachments.
    if (groupRepo != null) {
      for (final g in List.of(groupRepo.groups)) {
        if (g.worldIds.contains(oldName)) {
          g.worldIds = [
            for (final n in g.worldIds) n == oldName ? trimmed : n,
          ];
          await groupRepo.save(g);
        }
      }
    }

    notifyListeners();
  }

  Future<void> saveWorld(model.World world) async {
    // Check if exists
    final existing = await _db.getWorldByName(world.name);

    if (existing != null) {
      await _db.updateWorld(
        WorldsCompanion(
          id: Value(existing.id),
          name: Value(world.name),
          description: Value(world.description),
          lorebook: Value(jsonEncode(world.lorebook.toJson())),
          linkedCharacterName: Value(world.linkedCharacterName),
        ),
      );
    } else {
      await _db.insertWorld(
        WorldsCompanion(
          name: Value(world.name),
          description: Value(world.description),
          lorebook: Value(jsonEncode(world.lorebook.toJson())),
          linkedCharacterName: Value(world.linkedCharacterName),
        ),
      );
    }

    // Refresh list
    final index = _worlds.indexWhere((w) => w.name == world.name);
    if (index != -1) {
      _worlds[index] = world;
    } else {
      _worlds.add(world);
    }

    // If this is a linked world, try to resolve avatar path
    if (world.linkedCharacterName != null) {
      _resolveAvatarPaths([world]);
    }

    notifyListeners();
  }

  Future<void> deleteWorld(model.World world) async {
    final existing = await _db.getWorldByName(world.name);
    if (existing != null) {
      await _db.deleteWorldById(existing.id);
    }
    _worlds.remove(world);
    notifyListeners();
  }

  Future<void> importWorld(File file) async {
    try {
      final content = await file.readAsString();
      final Map<String, dynamic> json =
          jsonDecode(content) as Map<String, dynamic>;

      // Validate basic structure. Foreign formats (NovelAI, AgnAI, RisuAI,
      // V3 lorebooks) carry their own markers instead of an `entries` key.
      if (json['entries'] == null &&
          json['lorebook'] == null &&
          detectLorebookFormat(json) == LorebookFormat.fpaiOrSt) {
        throw FormatException(
          'Invalid lorebook file: missing "entries" or "lorebook" field. '
          'Supported formats: SillyTavern, Chub.ai, NovelAI, AgnAI, RisuAI, '
          'Front Porch.',
        );
      }

      final world = model.World.fromJson(json);

      // Validate that we got entries
      if (world.lorebook.entries.isEmpty) {
        print(
          'Warning: Imported world "${world.name}" has no lorebook entries. '
          'The file may be in an unsupported format or empty.',
        );
      }

      await saveWorld(world);
    } on FormatException {
      rethrow;
    } on Exception catch (e) {
      throw FormatException('Failed to import lorebook: $e');
    }
  }

  /// Write the world as a native SillyTavern world info file so exports drop
  /// straight into ST/Chub (and re-import into any FPAI version) with all
  /// entry metadata intact.
  Future<void> exportWorld(model.World world, String outputPath) async {
    final file = File(outputPath);
    await file.writeAsString(jsonEncode(encodeStWorldInfo(
      world.lorebook,
      name: world.name,
      description: world.description,
    )));
  }
}

// Extension to safely get the first element of a list or null if empty
extension NullableListExtensions<T> on List<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
