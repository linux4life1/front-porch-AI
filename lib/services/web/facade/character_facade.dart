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

import 'package:path/path.dart' as p;

import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/models/character_card.dart';
import 'package:front_porch_ai/services/character_repository.dart';
import 'package:front_porch_ai/services/chat_service.dart';
import 'package:front_porch_ai/services/folder_service.dart';
import 'package:front_porch_ai/services/storage_service.dart';
import 'package:front_porch_ai/services/v2_card_service.dart';
import 'package:front_porch_ai/services/web/util/lorebook_json.dart';
import 'package:front_porch_ai/services/web/util/realism_extensions_json.dart';

/// Thin read adapter over the character store for the rewritten web server.
///
/// Reuses the exact AppDatabase/FolderService calls the legacy server used so
/// the JSON contract (and therefore parity) is preserved; the route layer only
/// shapes HTTP responses.
class CharacterFacade {
  CharacterFacade(
    this._db,
    this._storage,
    this._folders,
    this._chat,
    this._repo,
  );

  final AppDatabase _db;
  final StorageService _storage;
  final CharacterRepository? _repo;
  final FolderService? _folders;
  final ChatService? _chat;

  /// List characters with optional search/folder filtering and sort, matching
  /// the legacy `/api/characters` payload.
  ///
  /// [scope] mirrors the desktop `SearchScope`: `currentFolder` (default — the
  /// active folder only, root = unfoldered), `folderRecursive` (folder + its
  /// subfolders), or `allCharacters` (ignore folders entirely — a true global
  /// search). The folder restriction now applies for both browsing and
  /// searching, so a search inside a folder stays scoped, unlike the old
  /// always-global search.
  Future<List<Map<String, dynamic>>> list({
    String? search,
    String? folder,
    String sort = 'name',
    String scope = 'currentFolder',
  }) async {
    var characters = await _db.getAllCharacters();
    final msgCounts = await _db.getMessageCountsPerCharacter();
    final term = search?.toLowerCase();

    if (_folders != null && scope != 'allCharacters') {
      if (folder != null && folder.isNotEmpty) {
        final inFolder = scope == 'folderRecursive'
            ? _folders.getCharactersInFolderRecursive(folder).toSet()
            : _folders.getCharactersInFolder(folder).toSet();
        characters = characters
            .where(
              (c) =>
                  c.imagePath != null &&
                  inFolder.contains(p.basename(c.imagePath!)),
            )
            .toList();
      } else {
        final foldered = _folders.getUnfolderedCharacterPaths();
        characters = characters
            .where(
              (c) =>
                  c.imagePath == null ||
                  !foldered.contains(p.basename(c.imagePath!)),
            )
            .toList();
      }
    }

    if (term != null && term.isNotEmpty) {
      characters = characters.where((c) {
        if (c.name.toLowerCase().contains(term)) return true;
        return _jsonList(
          c.tags,
        ).any((t) => t.toString().toLowerCase().contains(term));
      }).toList();
    }

    switch (sort) {
      case 'recent':
        characters = characters.reversed.toList();
        break;
      case 'messages':
        characters.sort(
          (a, b) => (msgCounts[b.id] ?? 0).compareTo(msgCounts[a.id] ?? 0),
        );
        break;
      case 'importDate':
        // Newest import first, by the trailing epoch in the PNG basename
        // (`Name_<millis>.png`) — mirrors the desktop _extractImportEpoch.
        characters.sort((a, b) => _importEpoch(b).compareTo(_importEpoch(a)));
        break;
      case 'name':
      default:
        characters.sort(
          (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
        );
    }

    return characters
        .map(
          (c) => {
            'id': c.id,
            'name': c.name,
            'description': c.description,
            'scenario': c.scenario,
            'personality': c.personality,
            'tags': _jsonList(c.tags),
            'hasAvatar': c.imagePath != null && c.imagePath!.isNotEmpty,
            'folderId': c.folderId ?? '',
            'messageCount': msgCounts[c.id] ?? 0,
          },
        )
        .toList();
  }

  /// The character folder tree (id, name, parentId) so the web library can show
  /// folder navigation. Character membership is queried separately via
  /// `list(folder: id)`, which already routes through FolderService.
  List<Map<String, dynamic>> folders() {
    final svc = _folders;
    if (svc == null) return const [];
    return svc.folders
        .map(
          (f) => {
            'id': f.id,
            'name': f.name,
            if (f.parentId != null) 'parentId': f.parentId,
          },
        )
        .toList();
  }

  /// Edit an existing character's core text fields. Reuses the desktop save
  /// path (mutate the in-memory CharacterCard + CharacterRepository.update),
  /// which re-writes the V2 PNG card and the DB row. Returns false if the
  /// repository isn't wired or the character isn't found. Only keys present in
  /// [fields] are changed.
  Future<bool> update(String id, Map<String, dynamic> fields) async {
    final repo = _repo;
    if (repo == null) return false;
    final card = _cardByDbId(id);
    if (card == null) return false;

    String pick(String key, String current) => fields.containsKey(key)
        ? (fields[key]?.toString() ?? current)
        : current;
    card.name = pick('name', card.name);
    card.description = pick('description', card.description);
    card.personality = pick('personality', card.personality);
    card.scenario = pick('scenario', card.scenario);
    card.firstMessage = pick('firstMessage', card.firstMessage);
    card.mesExample = pick('mesExample', card.mesExample);
    card.systemPrompt = pick('systemPrompt', card.systemPrompt);
    card.postHistoryInstructions = pick(
      'postHistoryInstructions',
      card.postHistoryInstructions,
    );
    final tags = fields['tags'];
    if (tags is List) card.tags = tags.map((e) => e.toString()).toList();
    final greetings = fields['alternateGreetings'];
    if (greetings is List) {
      card.alternateGreetings = greetings
          .map((e) => e.toString())
          .where((g) => g.trim().isNotEmpty)
          .toList();
    }
    // Linked worlds (attach worlds/lorebooks to a character). Worlds are keyed
    // by name; only replace when present so a partial edit doesn't clear them.
    final worlds = fields['worldNames'];
    if (worlds is List) {
      card.worldNames = worlds
          .map((e) => e.toString())
          .where((w) => w.trim().isNotEmpty)
          .toList();
    }
    // Per-character lorebook editing: only replace when the key is present so a
    // partial edit doesn't wipe existing lore. An explicit empty list clears it.
    if (fields.containsKey('lorebook')) {
      card.lorebook = buildLorebookFromJson(fields['lorebook']);
    }
    // Round-trip the Realism Engine + Needs seeds through the shared helper using
    // the current extensions as the base, so editing realism never wipes needs
    // (or chat-appearance) state and vice-versa. Matches the desktop save path
    // which always rebuilds extensions; the realismEnabled flag only gates use.
    card.frontPorchExtensions = frontPorchFromFields(
      fields,
      base: card.frontPorchExtensions,
    );

    await repo.updateCharacter(card);
    return true;
  }

  /// The in-memory [CharacterCard] matching library [id] (its dbId), or null.
  /// Used by [update] and [detail] so both source realism/world state from the
  /// same place the desktop edits (the PNG-backed card, not the realism-less DB
  /// row).
  CharacterCard? _cardByDbId(String id) {
    final repo = _repo;
    if (repo == null) return null;
    for (final c in repo.characters) {
      if (c.dbId == id) return c;
    }
    return null;
  }

  /// Create a brand-new character from web wizard fields. Mirrors the desktop
  /// `create_character_page._saveCharacter`: build the card + Realism seeds, write
  /// a V2 PNG (embedding the extensions so the seeds survive — the DB has no
  /// realism columns) with a synthesized placeholder avatar, then add it via the
  /// same [CharacterRepository.addCharacter] path. Returns {id, name} or null.
  Future<Map<String, dynamic>?> create(Map<String, dynamic> fields) async {
    final repo = _repo;
    if (repo == null) return null;
    final name = fields['name']?.toString().trim() ?? '';
    if (name.isEmpty) return null;

    List<String> asStrList(dynamic v) =>
        v is List ? v.map((e) => e.toString()).toList() : const [];

    // Always build extensions (even when realism is off) so configured values
    // survive — matching the desktop comment. The flag only gates runtime use.
    // The shared helper round-trips every realism + needs + verifier field so
    // web-created cards get the same baselines as the desktop creator.
    final fpExt = frontPorchFromFields(fields);

    final card = CharacterCard(
      name: name,
      description: fields['description']?.toString() ?? '',
      personality: fields['personality']?.toString() ?? '',
      scenario: fields['scenario']?.toString() ?? '',
      firstMessage: fields['firstMessage']?.toString() ?? '',
      mesExample: fields['mesExample']?.toString() ?? '',
      systemPrompt: fields['systemPrompt']?.toString() ?? '',
      postHistoryInstructions:
          fields['postHistoryInstructions']?.toString() ?? '',
      alternateGreetings: asStrList(
        fields['alternateGreetings'],
      ).where((g) => g.trim().isNotEmpty).toList(),
      tags: asStrList(fields['tags']),
      lorebook: buildLorebookFromJson(fields['lorebook']),
      frontPorchExtensions: fpExt,
    );

    return persistNewCard(card);
  }

  /// Persist a freshly-built [card] via the canonical path: write a V2 PNG into
  /// the characters dir (synthesizing a placeholder avatar when none is set),
  /// insert it through [CharacterRepository], and return {id, name}. Shared by
  /// manual create and the AI chargen facade so there is a single save path.
  /// Returns null when there is no repository or on failure.
  Future<Map<String, dynamic>?> persistNewCard(
    CharacterCard card, {
    List<int>? portraitBytes,
  }) async {
    final repo = _repo;
    if (repo == null) return null;
    try {
      final charDir = _storage.charactersDir;
      if (!charDir.existsSync()) charDir.createSync(recursive: true);
      final base = (card.name.isEmpty ? 'character' : card.name)
          .replaceAll(RegExp(r'[^\w\s]'), '')
          .replaceAll(' ', '_');
      final safeName = base.replaceAll('_', '').isEmpty ? 'character' : base;
      card.imagePath = p.join(
        charDir.path,
        '${safeName}_${DateTime.now().millisecondsSinceEpoch}.png',
      );
      // A rendered portrait (e.g. AI chargen) becomes the card's base image;
      // otherwise sourceImagePath stays null → V2CardService synthesizes a
      // placeholder avatar.
      String? sourceImagePath;
      if (portraitBytes != null && portraitBytes.isNotEmpty) {
        sourceImagePath = p.join(
          Directory.systemTemp.path,
          'fpa_portrait_${DateTime.now().millisecondsSinceEpoch}.png',
        );
        await File(sourceImagePath).writeAsBytes(portraitBytes);
      }
      await V2CardService().saveCardAsPng(card, card.imagePath!, sourceImagePath);
      await repo.addCharacter(card);
      return {'id': card.dbId, 'name': card.name};
    } catch (_) {
      return null;
    }
  }

  /// Import a character card uploaded from the web (V2 PNG or .byaf). Writes the
  /// bytes to a temp file and reuses the desktop import path
  /// ([CharacterRepository.importCharacter]) so parsing/parity is identical.
  /// Returns the new character's {id, name}, or null on failure.
  Future<Map<String, dynamic>?> importBytes(
    List<int> bytes,
    String filename,
  ) async {
    final repo = _repo;
    if (repo == null) return null;
    final ext = p.extension(filename).isNotEmpty
        ? p.extension(filename)
        : '.png';
    final tmp = File(
      p.join(
        Directory.systemTemp.path,
        'fpa_import_${DateTime.now().microsecondsSinceEpoch}$ext',
      ),
    );
    try {
      await tmp.writeAsBytes(bytes, flush: true);
      final card = await repo.importCharacter(tmp);
      if (card == null) return null;
      return {'id': card.dbId, 'name': card.name};
    } catch (_) {
      return null;
    } finally {
      try {
        if (tmp.existsSync()) await tmp.delete();
      } catch (_) {}
    }
  }

  /// Resolve the on-disk avatar file for the active character's *current
  /// expression* (mood-driven portrait), or null if expressions aren't in use
  /// or no avatar matches. Reuses [ChatService.resolveExpressionAvatar] — a
  /// pure read that performs no reclassification, so Realism parity is intact.
  File? activeExpressionAvatarFile() {
    final chat = _chat;
    if (chat == null) return null;
    final activeChar = chat.activeCharacter;
    if (activeChar == null) return null;
    final avatar = chat.resolveExpressionAvatar(activeChar);
    if (avatar == null) return null;
    final safeName = activeChar.name
        .replaceAll(RegExp(r'[^\w\s\-]'), '')
        .replaceAll(' ', '_');
    final avatarsDir = p.join(_storage.charactersDir.path, safeName, 'avatars');
    final file = avatar.file(avatarsDir);
    return file.existsSync() ? file : null;
  }

  /// Resolve the on-disk avatar file for [id], or null if none.
  Future<File?> avatarFile(String id) async {
    try {
      final c = await _db.getCharacterById(id);
      if (c.imagePath == null || c.imagePath!.isEmpty) return null;
      final file = File(
        p.join(_storage.charactersDir.path, p.basename(c.imagePath!)),
      );
      return file.existsSync() ? file : null;
    } catch (_) {
      return null;
    }
  }

  /// Full character card detail, matching the legacy `/detail` payload
  /// (including session-scoped evolution state when a chat is active).
  Future<Map<String, dynamic>?> detail(String id) async {
    try {
      final c = await _db.getCharacterById(id);
      // Realism/Needs seeds live in the PNG-backed card (the DB row has no
      // realism columns), so source them from the in-memory card. Flattened via
      // the shared helper so the edit page's Realism/Needs form sections can
      // round-trip them losslessly.
      final ext = _cardByDbId(id)?.frontPorchExtensions;
      return {
        'id': c.id,
        'name': c.name,
        'description': c.description,
        'personality': c.personality,
        'scenario': c.scenario,
        'firstMessage': c.firstMessage,
        'mesExample': c.mesExample,
        'systemPrompt': c.systemPrompt,
        'postHistoryInstructions': c.postHistoryInstructions,
        'alternateGreetings': _jsonList(c.alternateGreetings),
        'tags': _jsonList(c.tags),
        'worldNames': _jsonList(c.worldNames),
        'lorebook': _normalizeLorebook(c.lorebook),
        'ttsVoice': c.ttsVoice,
        'imagePath': c.imagePath,
        'realism': ext != null ? frontPorchToJson(ext) : null,
        'evolvedPersonality': _chat?.getEffectivePersonality ?? '',
        'evolvedScenario': _chat?.getEffectiveScenario ?? '',
        'evolutionCount': _chat?.characterEvolutionCount ?? 0,
      };
    } catch (_) {
      return null;
    }
  }

  /// The trailing import epoch encoded in a character's PNG basename
  /// (`Name_<millisecondsSinceEpoch>.png`), or 0 when absent — used by the
  /// `importDate` sort. Mirrors the desktop `_extractImportEpoch`.
  int _importEpoch(Character c) {
    final imagePath = c.imagePath;
    if (imagePath == null || imagePath.isEmpty) return 0;
    final base = p.basenameWithoutExtension(imagePath);
    final i = base.lastIndexOf('_');
    if (i == -1) return 0;
    return int.tryParse(base.substring(i + 1)) ?? 0;
  }

  List<dynamic> _jsonList(String raw) {
    try {
      final v = jsonDecode(raw);
      return v is List ? v : const [];
    } catch (_) {
      return const [];
    }
  }

  /// Normalize the DB lorebook blob (keys array / comment) into the frontend
  /// shape (comma-joined key string / name), as the legacy detail handler did.
  Map<String, dynamic>? _normalizeLorebook(String? raw) {
    if (raw == null) return null;
    try {
      final parsed = jsonDecode(raw);
      if (parsed is! Map<String, dynamic> || parsed['entries'] is! List) {
        return parsed is Map<String, dynamic> ? parsed : null;
      }
      final entries = (parsed['entries'] as List).map((e) {
        if (e is! Map<String, dynamic>) return e;
        final keyStr = e['keys'] is List
            ? (e['keys'] as List).map((k) => k.toString()).join(', ')
            : (e['key']?.toString() ?? '');
        return {
          'name': e['comment']?.toString() ?? e['name']?.toString() ?? '',
          'key': keyStr,
          'content': e['content']?.toString() ?? '',
          'enabled': e['enabled'] ?? true,
          'constant': e['constant'] ?? false,
          'stickyDepth': e['sticky_depth'] ?? e['insertion_order'] ?? 1,
        };
      }).toList();
      return {'entries': entries};
    } catch (_) {
      return null;
    }
  }
}
