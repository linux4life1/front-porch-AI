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

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/services/services.dart';

/// Per-file BYAF import loop used by the bulk progress dialog. Mirrors the
/// single-file BYAF pipeline (parse → convert → embed V2 PNG →
/// import → optional chat history) and reports progress per file.
Future<void> importHomeByafFiles(
  BuildContext context,
  List<String> paths,
  bool importChats, {
  bool applySettings = false,
  required void Function(int current, int total, String name, String? error)
  onProgress,
  required bool Function() isCancelled,
}) async {
  final byafService = ByafService();
  final v2Service = V2CardService();
  final repo = Provider.of<CharacterRepository>(context, listen: false);
  final storage = Provider.of<StorageService>(context, listen: false);

  for (int i = 0; i < paths.length; i++) {
    if (isCancelled()) break;
    final name = paths[i].split(Platform.pathSeparator).last;
    ByafImportPreview? preview;
    try {
      final parsed = await byafService.parseByaf(paths[i]);
      preview = parsed;
      final card = byafService.toCharacterCard(parsed);
      final pngPath = await byafService.saveCharacterPng(
        card,
        charactersDirPath: storage.charactersDir.path,
      );
      await v2Service.saveCardAsPng(card, pngPath, parsed.extractedImagePath);
      // Bulk never offers Replace (always a fresh insert unless stableId
      // matches). In-place persist already clears looks on that match.
      final imported = await repo.importCharacter(File(pngPath));
      if (imported != null) {
        await applyByafGalleryLooks(
          repo: repo,
          imported: imported,
          galleryImagePaths: parsed.galleryImagePaths,
          importGalleryImages: true,
        );
        final genSettings = applySettings
            ? byafService.toGenerationSettings(parsed)
            : null;
        final db = await AppDatabase.instance();
        await byafService.importSession(
          db,
          parsed,
          imported,
          includeMessages: importChats,
          genSettings: genSettings,
        );
      } else {
        deleteByafTempImages(parsed.galleryImagePaths);
      }
      onProgress(
        i + 1,
        paths.length,
        imported?.name ?? name,
        imported == null ? 'Import returned no character' : null,
      );
    } catch (e) {
      if (preview != null) {
        deleteByafTempImages(preview.galleryImagePaths);
      }
      onProgress(i + 1, paths.length, name, '$e');
    }
  }
}
