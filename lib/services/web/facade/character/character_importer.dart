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

import 'dart:io';

import 'package:path/path.dart' as p;

import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/services.dart';

/// Imports an uploaded character card (V2 PNG, JSON or .byaf) through the
/// desktop import path, with the web's name-collision policy.
class CharacterImporter {
  CharacterImporter(this._repo, this._storage, this._db);

  final CharacterRepository _repo;
  final StorageService _storage;
  final AppDatabase _db;

  /// See [CharacterFacade.importBytes].
  Future<Map<String, dynamic>?> importBytes(
    List<int> bytes,
    String filename, {
    String collision = 'keepBoth',
    String? replaceId,
  }) async {
    final repo = _repo;
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

      if (filename.toLowerCase().endsWith('.byaf')) {
        return await _importByafFile(
          tmp,
          filename,
          collision: collision,
          replaceId: replaceId,
        );
      }

      // Peek identity for collision policy (same rules as desktop single-import).
      CharacterCard? peeked;
      try {
        final isJson = tmp.path.toLowerCase().endsWith('.json');
        final v2 = V2CardService();
        peeked = isJson
            ? await v2.readCardFromJsonFile(tmp.path)
            : await v2.readCard(tmp.path);
      } catch (_) {
        peeked = null;
      }
      final name = peeked?.name ?? p.basenameWithoutExtension(filename);
      final stableId = peeked?.frontPorchExtensions?.stableId;
      final stableMatch = repo.findByStableId(stableId);

      if (stableMatch == null) {
        final existing = repo.charactersWithName(name);
        if (existing.isNotEmpty) {
          if (collision == 'ask') {
            return {
              'status': 'name_collision',
              'name': name,
              'existing': [
                for (final c in existing) {'id': c.dbId, 'name': c.name},
              ],
            };
          }
          if (collision == 'replace') {
            CharacterCard? target;
            if (replaceId != null && replaceId.isNotEmpty) {
              for (final c in existing) {
                if (c.dbId == replaceId) {
                  target = c;
                  break;
                }
              }
            }
            target ??= existing.first;
            final card = await repo.importCharacter(
              tmp,
              forceReplaceTarget: target,
            );
            if (card == null) return null;
            return {'id': card.dbId, 'name': card.name, 'replaced': true};
          }
          // keepBoth: fall through to plain import (insert)
        }
      }

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

  /// Parse a `.byaf` upload with [ByafService], persist as a V2 PNG, then
  /// attach extra archive images as gallery looks. Matches desktop defaults:
  /// gallery on, chat history on, Backyard sampler settings on.
  Future<Map<String, dynamic>?> _importByafFile(
    File tmp,
    String filename, {
    required String collision,
    String? replaceId,
  }) async {
    final repo = _repo;
    final byaf = ByafService();
    ByafImportPreview? preview;
    try {
      preview = await byaf.parseByaf(tmp.path);
      final peeked = byaf.toCharacterCard(preview);
      final name = peeked.name.isNotEmpty
          ? peeked.name
          : p.basenameWithoutExtension(filename);
      final stableId = peeked.frontPorchExtensions?.stableId;
      final stableMatch = repo.findByStableId(stableId);
      CharacterCard? forceReplace;

      if (stableMatch == null) {
        final existing = repo.charactersWithName(name);
        if (existing.isNotEmpty) {
          if (collision == 'ask') {
            deleteByafTempImages(preview.galleryImagePaths);
            return {
              'status': 'name_collision',
              'name': name,
              'existing': [
                for (final c in existing) {'id': c.dbId, 'name': c.name},
              ],
            };
          }
          if (collision == 'replace') {
            CharacterCard? target;
            if (replaceId != null && replaceId.isNotEmpty) {
              for (final c in existing) {
                if (c.dbId == replaceId) {
                  target = c;
                  break;
                }
              }
            }
            target ??= existing.first;
            forceReplace = target;
          }
        }
      }

      final pngPath = await byaf.saveCharacterPng(
        peeked,
        charactersDirPath: _storage.charactersDir.path,
      );
      await V2CardService().saveCardAsPng(
        peeked,
        pngPath,
        preview.extractedImagePath,
      );
      final imported = await repo.importCharacter(
        File(pngPath),
        forceReplaceTarget: forceReplace,
      );
      if (imported == null) {
        deleteByafTempImages(preview.galleryImagePaths);
        return null;
      }
      final looksImported = await applyByafGalleryLooks(
        repo: repo,
        imported: imported,
        galleryImagePaths: preview.galleryImagePaths,
        importGalleryImages: true,
        replaceExistingLooks: forceReplace != null || stableMatch != null,
      );
      await byaf.importSession(
        _db,
        preview,
        imported,
        includeMessages: true,
        genSettings: byaf.toGenerationSettings(preview),
      );
      return {
        'id': imported.dbId,
        'name': imported.name,
        if (forceReplace != null) 'replaced': true,
        'looksImported': looksImported,
      };
    } catch (_) {
      if (preview != null) deleteByafTempImages(preview.galleryImagePaths);
      return null;
    }
  }
}
