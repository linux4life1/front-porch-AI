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
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/services/v2_card_service.dart';

/// Handles one-time migration of existing JSON files & SharedPreferences
/// data into the Drift SQLite database.
class DataMigrationService {
  final AppDatabase _db;

  DataMigrationService(this._db);

  /// Returns true if migration has already been completed.
  static Future<bool> isMigrated() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('db_migration_complete') ?? false;
  }

  /// Mark migration as complete so it never runs again.
  static Future<void> _markComplete() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('db_migration_complete', true);
  }

  /// Run the full migration. Reports progress via [onProgress].
  /// Format: (step description, current, total)
  Future<void> migrate({
    void Function(String step, int current, int total)? onProgress,
  }) async {
    if (await isMigrated()) return;

    const totalSteps = 6;
    int step = 0;

    // 1. Migrate characters
    onProgress?.call('Importing characters...', ++step, totalSteps);
    await _migrateCharacters();

    // 2. Migrate chat sessions
    onProgress?.call('Importing chat history...', ++step, totalSteps);
    await _migrateChatSessions();

    // 3. Migrate group chats
    onProgress?.call('Importing group chats...', ++step, totalSteps);
    await _migrateGroupChats();

    // 4. Migrate worlds
    onProgress?.call('Importing worlds...', ++step, totalSteps);
    await _migrateWorlds();

    // 5. Migrate folders
    onProgress?.call('Importing folders...', ++step, totalSteps);
    await _migrateFolders();

    // 6. Migrate user personas
    onProgress?.call('Importing personas...', ++step, totalSteps);
    await _migratePersonas();

    await _markComplete();

    // Clean up old JSON files now that data lives in the DB
    onProgress?.call('Cleaning up old files...', totalSteps, totalSteps);
    await cleanupLegacyFiles();

    debugPrint('DB_MIGRATION: Migration complete!');
  }

  // ── Characters ────────────────────────────────────────────────────────

  Future<void> _migrateCharacters() async {
    final prefs = await SharedPreferences.getInstance();
    final rootPath = prefs.getString('root_path');
    final directory = await getApplicationDocumentsDirectory();
    final basePath = rootPath ?? directory.path;
    final charDir = Directory('$basePath/KoboldManager/Characters');
    if (!await charDir.exists()) return;

    final v2Service = V2CardService();

    await for (final entity in charDir.list()) {
      if (entity is! File || !entity.path.toLowerCase().endsWith('.png')) continue;

      try {
        final card = await v2Service.readCard(entity.path);
        if (card == null) continue;

        await _db.insertCharacter(CharactersCompanion(
          name: Value(card.name),
          description: Value(card.description),
          personality: Value(card.personality),
          scenario: Value(card.scenario),
          firstMessage: Value(card.firstMessage),
          mesExample: Value(card.mesExample),
          systemPrompt: Value(card.systemPrompt),
          postHistoryInstructions: Value(card.postHistoryInstructions),
          alternateGreetings: Value(jsonEncode(card.alternateGreetings)),
          tags: Value(jsonEncode(card.tags)),
          imagePath: Value(card.imagePath != null ? card.imagePath!.split(RegExp(r'[/\\]')).last : null),
          ttsVoice: Value(card.ttsVoice),
          lorebook: Value(card.lorebook != null ? jsonEncode(card.lorebook!.toJson()) : null),
          worldNames: Value(jsonEncode(card.worldNames)),
        ));
        debugPrint('DB_MIGRATION: Imported character: ${card.name}');
      } catch (e) {
        debugPrint('DB_MIGRATION: Failed to import character ${entity.path}: $e');
      }
    }
  }

  // ── Chat Sessions ─────────────────────────────────────────────────────

  Future<void> _migrateChatSessions() async {
    final prefs = await SharedPreferences.getInstance();
    final rootPath = prefs.getString('root_path');
    final docsDir = await getApplicationDocumentsDirectory();
    final chatsPath = rootPath != null
        ? '$rootPath/chats'
        : '${docsDir.path}/chats';

    final chatsDir = Directory(chatsPath);
    if (!await chatsDir.exists()) return;

    // Each subdirectory under chats/ is a character ID
    await for (final charDir in chatsDir.list()) {
      if (charDir is! Directory) continue;

      final charId = charDir.path.split(Platform.pathSeparator).last;

      // Skip the 'groups' subdirectory – that's handled separately
      if (charId == 'groups') continue;

      // Try to find the matching character in the DB by imagePath
      final character = await _db.getCharacterByImagePath(
        // The charId is the basename-without-extension of the PNG
        // We need to find a character whose imagePath ends with this
        charId,
      );

      // Look up character ID from the database (now String UUID)
      String? dbCharacterId;
      if (character != null) {
        dbCharacterId = character.id;
      } else {
        // Try a broader search — charId might be the filename without extension
        final allChars = await _db.getAllCharacters();
        for (final c in allChars) {
          if (c.imagePath != null) {
            final basename = c.imagePath!.split(Platform.pathSeparator).last;
            final nameNoExt = basename.replaceAll('.png', '').replaceAll('.PNG', '');
            if (nameNoExt == charId) {
              dbCharacterId = c.id;
              break;
            }
          }
        }
      }

      // Determine if this is a group chat directory
      String? groupId;
      if (charId.startsWith('group_')) {
        groupId = charId.replaceFirst('group_', '');
      }

      // Import each session file
      await for (final entity in charDir.list()) {
        if (entity is! File || !entity.path.endsWith('.json')) continue;

        try {
          final sessionId = entity.path
              .split(Platform.pathSeparator)
              .last
              .replaceAll('.json', '');

          final content = await entity.readAsString();
          final decoded = jsonDecode(content);

          List<dynamic> msgList;
          String authorNote = '';
          int authorNoteDepth = 4;
          String? sessionName;
          String? sessionDescription;
          String? parentSession;
          int? forkIndex;

          if (decoded is List) {
            msgList = decoded;
          } else if (decoded is Map) {
            msgList = decoded['messages'] ?? [];
            authorNote = decoded['author_note'] ?? '';
            authorNoteDepth = decoded['author_note_depth'] ?? 4;
            sessionName = decoded['session_name'];
            sessionDescription = decoded['session_description'];
            parentSession = decoded['parent_session'];
            forkIndex = decoded['fork_index'];
          } else {
            continue;
          }

          // Parse timestamp from session ID
          final timestamp = int.tryParse(sessionId) ?? 0;
          final createdAt = DateTime.fromMillisecondsSinceEpoch(timestamp);

          // Insert session
          await _db.insertSession(SessionsCompanion.insert(
            id: sessionId,
            characterId: Value(dbCharacterId),
            groupId: Value(groupId),
            name: Value(sessionName),
            description: Value(sessionDescription),
            authorNote: Value(authorNote),
            authorNoteDepth: Value(authorNoteDepth),
            parentSession: Value(parentSession),
            forkIndex: Value(forkIndex),
            createdAt: Value(createdAt),
            updatedAt: Value(createdAt),
          ));

          // Insert messages in batch
          final messageBatch = <MessagesCompanion>[];
          for (int i = 0; i < msgList.length; i++) {
            final m = msgList[i];
            final swipes = m['swipes'] as List<dynamic>?;
            final swipeDurations = m['swipe_durations'] as List<dynamic>?;

            messageBatch.add(MessagesCompanion(
              sessionId: Value(sessionId),
              position: Value(i),
              sender: Value(m['sender'] ?? ''),
              isUser: Value(m['is_user'] ?? false),
              characterId: Value(m['character_id']),
              swipes: Value(jsonEncode(swipes ?? [m['text'] ?? ''])),
              swipeIndex: Value(m['swipe_index'] ?? 0),
              swipeDurations: Value(jsonEncode(swipeDurations ?? [0])),
            ));
          }
          if (messageBatch.isNotEmpty) {
            await _db.insertMessages(messageBatch);
          }

          debugPrint('DB_MIGRATION: Imported session $sessionId with ${msgList.length} messages');
        } catch (e) {
          debugPrint('DB_MIGRATION: Failed to import session ${entity.path}: $e');
        }
      }
    }
  }

  // ── Group Chats ───────────────────────────────────────────────────────

  Future<void> _migrateGroupChats() async {
    final prefs = await SharedPreferences.getInstance();
    final rootPath = prefs.getString('root_path');
    final docsDir = await getApplicationDocumentsDirectory();
    final groupsPath = rootPath != null
        ? '$rootPath/chats/groups'
        : '${docsDir.path}/chats/groups';

    final groupsDir = Directory(groupsPath);
    if (!await groupsDir.exists()) return;

    await for (final entity in groupsDir.list()) {
      if (entity is! File || !entity.path.endsWith('.json')) continue;

      try {
        final json = jsonDecode(await entity.readAsString());
        await _db.insertGroup(GroupsCompanion.insert(
          id: json['id'] ?? '',
          name: json['name'] ?? 'Group Chat',
          characterIds: Value(jsonEncode(json['character_ids'] ?? [])),
          turnOrder: Value(json['turn_order'] ?? 'roundRobin'),
          autoAdvance: Value(json['auto_advance'] ?? false),
          directorMode: Value(json['director_mode'] ?? false),
          firstMessage: Value(json['first_message'] ?? ''),
          scenario: Value(json['scenario'] ?? ''),
          systemPrompt: Value(json['system_prompt'] ?? ''),
        ));
        debugPrint('DB_MIGRATION: Imported group: ${json['name']}');
      } catch (e) {
        debugPrint('DB_MIGRATION: Failed to import group ${entity.path}: $e');
      }
    }
  }

  // ── Worlds ────────────────────────────────────────────────────────────

  Future<void> _migrateWorlds() async {
    final prefs = await SharedPreferences.getInstance();
    final rootPath = prefs.getString('root_path');
    final docsDir = await getApplicationDocumentsDirectory();
    final worldsPath = rootPath != null
        ? '$rootPath/worlds'
        : '${docsDir.path}/worlds';

    final worldsDir = Directory(worldsPath);
    if (!await worldsDir.exists()) return;

    await for (final entity in worldsDir.list()) {
      if (entity is! File || !entity.path.toLowerCase().endsWith('.json')) continue;

      try {
        final json = jsonDecode(await entity.readAsString());
        await _db.insertWorld(WorldsCompanion(
          name: Value(json['name'] ?? 'New World'),
          description: Value(json['description'] ?? ''),
          lorebook: Value(json['lorebook'] != null ? jsonEncode(json['lorebook']) : null),
          linkedCharacterName: Value(json['linked_character_name']),
        ));
        debugPrint('DB_MIGRATION: Imported world: ${json['name']}');
      } catch (e) {
        debugPrint('DB_MIGRATION: Failed to import world ${entity.path}: $e');
      }
    }
  }

  // ── Folders ───────────────────────────────────────────────────────────

  Future<void> _migrateFolders() async {
    final prefs = await SharedPreferences.getInstance();
    final rootPath = prefs.getString('root_path');
    final directory = await getApplicationDocumentsDirectory();
    final basePath = rootPath ?? directory.path;
    final foldersFile = File('$basePath/KoboldManager/character_folders.json');
    if (!await foldersFile.exists()) return;

    try {
      final json = jsonDecode(await foldersFile.readAsString());
      final foldersList = json['folders'] as List? ?? [];

      // Map old string IDs to new UUID IDs
      final idMap = <String, String>{};

      // First pass: insert top-level folders (no parentId)
      for (final f in foldersList) {
        if (f['parentId'] != null) continue;
        final newId = await _db.insertFolder(FoldersCompanion(
          name: Value(f['name'] ?? ''),
        ));
        idMap[f['id']] = newId;
      }

      // Second pass: insert child folders
      for (final f in foldersList) {
        if (f['parentId'] == null) continue;
        final parentId = idMap[f['parentId']];
        final newId = await _db.insertFolder(FoldersCompanion(
          name: Value(f['name'] ?? ''),
          parentId: Value(parentId),
        ));
        idMap[f['id']] = newId;
      }

      // Now update characters with their folder assignments
      for (final f in foldersList) {
        final folderId = idMap[f['id']];
        if (folderId == null) continue;

        final charPaths = List<String>.from(f['characterPaths'] ?? []);
        for (final charPath in charPaths) {
          // Find the character in the DB by imagePath containing this filename
          final allChars = await _db.getAllCharacters();
          for (final c in allChars) {
            if (c.imagePath != null && c.imagePath!.endsWith(charPath)) {
              await _db.updateCharacter(CharactersCompanion(
                id: Value(c.id),
                name: Value(c.name),
                folderId: Value(folderId),
                updatedAt: Value(DateTime.now()),
              ));
              break;
            }
          }
        }
      }

      debugPrint('DB_MIGRATION: Imported ${foldersList.length} folders');
    } catch (e) {
      debugPrint('DB_MIGRATION: Failed to import folders: $e');
    }
  }

  // ── User Personas ─────────────────────────────────────────────────────

  Future<void> _migratePersonas() async {
    final prefs = await SharedPreferences.getInstance();
    final activeId = prefs.getString('active_persona_id') ?? '';
    final jsonList = prefs.getStringList('user_personas');

    if (jsonList == null || jsonList.isEmpty) {
      // Create default persona
      await _db.insertPersona(PersonasCompanion.insert(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        name: Value(prefs.getString('user_name') ?? 'User'),
        persona: Value(prefs.getString('user_persona') ?? ''),
        isActive: const Value(true),
      ));
      return;
    }

    for (final str in jsonList) {
      try {
        final json = jsonDecode(str);
        final id = json['id'] ?? DateTime.now().millisecondsSinceEpoch.toString();
        await _db.insertPersona(PersonasCompanion.insert(
          id: id,
          title: Value(json['title'] ?? ''),
          name: Value(json['name'] ?? 'User'),
          persona: Value(json['persona'] ?? ''),
          avatarPath: Value(json['avatar_path']),
          isActive: Value(id == activeId),
        ));
        debugPrint('DB_MIGRATION: Imported persona: ${json['name']}');
      } catch (e) {
        debugPrint('DB_MIGRATION: Failed to import persona: $e');
      }
    }
  }

  /// Delete legacy JSON files that are no longer needed after migration.
  /// Safe to call multiple times — skips files that don't exist.
  /// Preserves character PNGs (still needed for images).
  static Future<void> cleanupLegacyFiles() async {
    final prefs = await SharedPreferences.getInstance();
    final rootPath = prefs.getString('root_path');
    final docsDir = await getApplicationDocumentsDirectory();
    final basePath = rootPath ?? docsDir.path;

    int deleted = 0;

    // 1. Delete chat session JSONs: {root}/chats/{charId}/*.json
    final chatsDir = Directory('$basePath/chats');
    if (await chatsDir.exists()) {
      await for (final charDir in chatsDir.list()) {
        if (charDir is! Directory) continue;
        // Skip the 'groups' subdirectory — handled below
        if (charDir.path.endsWith('groups')) continue;
        await for (final entity in charDir.list()) {
          if (entity is File && entity.path.endsWith('.json')) {
            try {
              await entity.delete();
              deleted++;
            } catch (e) {
              debugPrint('Cleanup: failed to delete ${entity.path}: $e');
            }
          }
        }
        // Remove the character chat directory if now empty
        try {
          if (await charDir.list().isEmpty) {
            await charDir.delete();
          }
        } catch (_) {}
      }
    }

    // 2. Delete group chat JSONs: {root}/chats/groups/*.json
    final groupsDir = Directory('$basePath/chats/groups');
    if (await groupsDir.exists()) {
      await for (final entity in groupsDir.list()) {
        if (entity is File && entity.path.endsWith('.json')) {
          try {
            await entity.delete();
            deleted++;
          } catch (e) {
            debugPrint('Cleanup: failed to delete ${entity.path}: $e');
          }
        }
      }
      // Remove groups dir if now empty
      try {
        if (await groupsDir.list().isEmpty) {
          await groupsDir.delete();
        }
      } catch (_) {}
    }

    // 3. Delete world JSONs: {root}/worlds/*.json
    final worldsDir = Directory('$basePath/worlds');
    if (await worldsDir.exists()) {
      await for (final entity in worldsDir.list()) {
        if (entity is File && entity.path.endsWith('.json')) {
          try {
            await entity.delete();
            deleted++;
          } catch (e) {
            debugPrint('Cleanup: failed to delete ${entity.path}: $e');
          }
        }
      }
    }

    // 4. Delete character_folders.json
    final foldersFile = File('$basePath/KoboldManager/character_folders.json');
    if (await foldersFile.exists()) {
      try {
        await foldersFile.delete();
        deleted++;
      } catch (e) {
        debugPrint('Cleanup: failed to delete character_folders.json: $e');
      }
    }

    if (deleted > 0) {
      debugPrint('Cleanup: deleted $deleted legacy JSON file(s)');
    }
  }
}
