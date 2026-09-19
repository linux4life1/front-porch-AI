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

part of 'character_facade.dart';

extension CharacterFacadeByaf on CharacterFacade {
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
    if (repo == null) return null;
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
