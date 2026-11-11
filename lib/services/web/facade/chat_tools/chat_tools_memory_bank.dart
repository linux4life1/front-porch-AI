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
import 'dart:typed_data';

import 'package:drift/drift.dart' as drift;
import 'package:path/path.dart' as p;

import 'package:front_porch_ai/database/database.dart' hide AvatarImage, World;
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/character_repository.dart';
import 'package:front_porch_ai/services/chat/group_memory.dart';
import 'package:front_porch_ai/services/web/facade/chat_tools/chat_tools_context.dart';
import 'package:front_porch_ai/ui/dialogs/data_bank/data_bank.dart';
import 'package:front_porch_ai/utils/utils.dart';

/// The PWA's twins of the desktop Memory leaf's Sources picker and Data Bank,
/// for the focused participant: a 1:1 host, or one group member by their
/// library identity ([memoryIdFor]). Every write lands at once in the same
/// store the desktop writes (`characters.memory_sources`, `data_bank_entries`).
/// A lite guest has no memory, as on the desktop: `available` is false.
class ChatToolsMemoryBank {
  ChatToolsMemoryBank(
    this._ctx, {
    AppDatabase? db,
    CharacterRepository? library,
  }) : _db = db,
       _library = library;

  final ChatToolsContext _ctx;
  final AppDatabase? _db;
  final CharacterRepository? _library;

  AppDatabase? get _store => _db ?? AppDatabase.current;
  bool get _inGroup => _ctx.chat.isGroupMode;

  ({CharacterCard card, String id})? _owner(String? participantId) {
    final who = _ctx.growthOwner(participantId);
    if (who == null || who.isLite) return null;
    final lib = _library?.characters ?? const <CharacterCard>[];
    return (card: who.card, id: memoryIdFor(who.card, lib, inGroup: _inGroup));
  }

  static const _unavailable = {'available': false};

  // ── Sources ───────────────────────────────────────────────────────────

  /// Who [participantId] can draw memories from, and who they do.
  Future<Map<String, dynamic>> sources(String? participantId) async {
    final owner = _owner(participantId);
    final repo = _library;
    if (owner == null || repo == null) return _unavailable;
    final libId = memoryLibraryDbIdFor(
      owner.card,
      repo.characters,
      inGroup: _inGroup,
    );
    final selected = libId == null
        ? <String>[]
        : await repo.getMemorySources(libId);
    return {
      'available': true,
      'ownerName': owner.card.name,
      'selected': selected,
      // Every other library character, in library order (other group members
      // included: only their windows in THIS chat are never read).
      'choices': [
        for (final c in repo.characters)
          if (c.stableGroupId != owner.id)
            {'id': c.stableGroupId, 'name': c.name},
      ],
    };
  }

  /// Include / drop one source for [participantId]. Null when there is no
  /// library row to write to.
  Future<Map<String, dynamic>?> setSource(
    String? participantId,
    String sourceId,
    bool selected,
  ) async {
    final owner = _owner(participantId);
    final repo = _library;
    if (owner == null || repo == null) return null;
    final libId = memoryLibraryDbIdFor(
      owner.card,
      repo.characters,
      inGroup: _inGroup,
    );
    if (libId == null) return null;
    final now = (await repo.getMemorySources(libId)).toSet();
    selected ? now.add(sourceId) : now.remove(sourceId);
    await repo.setMemorySources(libId, now.toList());
    return sources(participantId);
  }

  // ── Data Bank ─────────────────────────────────────────────────────────

  Future<Map<String, dynamic>> dataBank(
    String? participantId, {
    String? note,
  }) async {
    final owner = _owner(participantId);
    final db = _store;
    if (owner == null || db == null) return _unavailable;
    final rows = await db.getDataBankEntriesForCharacter(owner.id);
    bool embedded(DataBankEntry e) => e.embedding != null && e.dimensions > 0;
    return {
      'available': true,
      'ownerName': owner.card.name,
      'entries': [
        for (final e in rows)
          {
            'id': e.id,
            'title': e.title,
            'content': e.content,
            'embedded': embedded(e),
          },
      ],
      'embedded': rows.where(embedded).length,
      'unembedded': rows.where((e) => !embedded(e)).length,
      'note': ?note,
    };
  }

  /// One Data Bank action: add / edit / delete / embed / import. Null for a
  /// bad request (unknown action, missing fields, or an entry that is not this
  /// character's).
  Future<Map<String, dynamic>?> dataBankAction(
    String? participantId,
    Map<String, dynamic> body,
  ) async {
    final owner = _owner(participantId);
    final db = _store;
    if (owner == null || db == null) return null;
    final title = body['title']?.toString().trim() ?? '';
    final content = body['content']?.toString().trim() ?? '';
    final id = body['id']?.toString();
    final own = await db.getDataBankEntriesForCharacter(owner.id);
    final target = own.where((e) => e.id == id).firstOrNull;
    switch (body['action']) {
      case 'add':
        if (title.isEmpty || content.isEmpty) return null;
        await db.insertDataBankEntry(
          DataBankEntriesCompanion(
            characterId: drift.Value(owner.id),
            title: drift.Value(title),
            content: drift.Value(content),
          ),
        );
      case 'edit':
        if (target == null || title.isEmpty || content.isEmpty) return null;
        // An edit drops the stale vector, as on the desktop.
        await db.updateDataBankEntry(
          DataBankEntriesCompanion(
            id: drift.Value(target.id),
            title: drift.Value(title),
            content: drift.Value(content),
            embedding: const drift.Value(null),
            dimensions: const drift.Value(0),
          ),
        );
      case 'delete':
        if (target == null) return null;
        await db.deleteDataBankEntry(target.id);
      case 'embed':
        return dataBank(participantId, note: await _embedAll(db, own));
      case 'import':
        final note = await _import(db, owner.id, body);
        if (note == null) return null;
        return dataBank(participantId, note: note);
      default:
        return null;
    }
    return dataBank(participantId);
  }

  /// Embeds the entries without a vector; a note when the engine is not up.
  Future<String?> _embedAll(AppDatabase db, List<DataBankEntry> rows) async {
    final engine = _ctx.chat.memoryService?.embeddingService;
    if (engine == null) return kEmbeddingUnavailable;
    if (!engine.isAvailable) await engine.checkAvailability();
    if (!engine.isAvailable) return kEmbeddingUnavailable;
    for (final e in rows.where(
      (e) => e.embedding == null || e.dimensions == 0,
    )) {
      final vector = await engine.embed(e.content);
      if (vector == null) continue;
      final bytes = Float32List.fromList(
        vector.map((d) => d.toDouble()).toList(),
      );
      await db.updateDataBankEntry(
        DataBankEntriesCompanion(
          id: drift.Value(e.id),
          embedding: drift.Value(Uint8List.view(bytes.buffer)),
          dimensions: drift.Value(vector.length),
        ),
      );
    }
    return null;
  }

  static const kEmbeddingUnavailable =
      'Embedding service not available. Start the ONNX server or enable an API source.';

  /// Imports a file's text as ~500-word entries, as the desktop does. Returns
  /// a note, or null when the file is unusable.
  Future<String?> _import(
    AppDatabase db,
    String ownerId,
    Map<String, dynamic> body,
  ) async {
    final name = body['fileName']?.toString() ?? '';
    final b64 = body['dataBase64']?.toString() ?? '';
    final ext = p.extension(name).toLowerCase().replaceAll('.', '');
    if (b64.isEmpty ||
        !(kDataBankTextExtensions.contains(ext) ||
            kDataBankPdfExtensions.contains(ext))) {
      return null;
    }
    final bytes = base64Decode(b64);
    String text;
    if (kDataBankPdfExtensions.contains(ext)) {
      final dir = Directory.systemTemp.createTempSync('fpai_databank_');
      try {
        final f = File(p.join(dir.path, 'upload.pdf'))..writeAsBytesSync(bytes);
        text = await extractDataBankPdfText(f.path);
      } finally {
        dir.deleteSync(recursive: true);
      }
    } else {
      text = utf8.decode(bytes, allowMalformed: true);
    }
    if (text.trim().isEmpty) return 'File contains no extractable text.';
    final chunks = chunkDataBankText(text, maxWords: 500);
    final base = p.basenameWithoutExtension(name);
    for (var i = 0; i < chunks.length; i++) {
      await db.insertDataBankEntry(
        DataBankEntriesCompanion(
          characterId: drift.Value(ownerId),
          title: drift.Value(
            chunks.length == 1 ? base : '$base (${i + 1}/${chunks.length})',
          ),
          content: drift.Value(chunks[i]),
        ),
      );
    }
    return 'Imported ${chunks.length} ${chunks.length == 1 ? 'entry' : 'entries'}.';
  }
}
