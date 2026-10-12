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
import 'package:front_porch_ai/ui/dialogs/dialogs.dart';
import 'package:front_porch_ai/ui/pages/home/home_actions/home_actions.dart';
import 'package:front_porch_ai/ui/pages/home/library_import_picks.dart';

/// PNG/JSON, group-card and BYAF import into the library, from the pickers
/// or a desktop drop. [context] is the library view that started it.
class HomeCardImport {
  HomeCardImport(this.context) : _bulk = HomeBulkImport(context);

  final BuildContext context;
  final HomeBulkImport _bulk;

  Future<void> pickCards() async {
    final files = await pickLibraryCards(context);
    if (files == null || !context.mounted) return;
    await importFiles(files);
  }

  /// PNG/JSON/group-card import after the picker (or a desktop drop) already
  /// resolved local files. Single file keeps the collision + tag dialogs;
  /// several files use the existing bulk progress path.
  Future<void> importFiles(List<File> files) async {
    if (files.isEmpty) return;

    // Single file: check if this is a Front Porch Group Card first (novel format)
    if (files.length == 1) {
      final file = files.first;
      try {
        final groupService = GroupCardService();
        final groupCard = await groupService.readGroupCard(file.path);

        if (groupCard != null) {
          // This is a Group Card PNG — do the special group import
          await importHomeGroupCard(context, file, groupCard);
          return;
        }

        // Normal character card — single-file: offer Keep both / Replace when
        // the display name already exists and stableId does not match.
        final repo = Provider.of<CharacterRepository>(context, listen: false);
        final card = await importCharacterWithNameCollision(
          context,
          repo,
          file,
        );
        if (context.mounted && card != null) {
          // Show tag dialog
          final tags = await TagDialog.show(context, card);
          if (tags != null && context.mounted) {
            card.tags = List.from(tags);
            await repo.updateCharacter(card);
          }
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Character imported successfully!')),
            );
          }
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('Import failed: $e')));
        }
      }
      return;
    }

    // Multiple files: use bulk import with progress dialog
    await _bulk.importCards(files);
  }

  Future<void> pickByaf() async {
    final paths = await pickLibraryByafFiles(context);
    if (paths == null || !context.mounted) return;
    await importByafPaths(paths);
  }

  /// BYAF import after the picker (or a desktop drop) already resolved paths.
  Future<void> importByafPaths(List<String> paths) async {
    if (paths.isEmpty) return;

    // Multiple files → bulk import with a progress dialog (no per-file preview),
    // mirroring the bulk V2 PNG importer. A single file keeps the rich preview
    // dialog below.
    if (paths.length > 1) {
      await _runBulkByafImport(paths);
      return;
    }

    final filePath = paths.first;
    final byafService = ByafService();
    ByafImportPreview? preview;

    try {
      // Parse the .byaf archive
      final parsed = await byafService.parseByaf(filePath);
      preview = parsed;

      if (!context.mounted) {
        deleteByafTempImages(parsed.galleryImagePaths);
        return;
      }

      // Show preview dialog
      final result2 = await showDialog<ByafImportResult>(
        context: context,
        builder: (context) => ByafImportDialog(preview: parsed),
      );

      if (result2 == null || !result2.confirmed || !context.mounted) {
        deleteByafTempImages(parsed.galleryImagePaths);
        return;
      }

      // Convert to CharacterCard
      final card = byafService.toCharacterCard(parsed);

      // Save as PNG (with image if available)
      final storageService = Provider.of<StorageService>(
        context,
        listen: false,
      );
      final pngPath = await byafService.saveCharacterPng(
        card,
        charactersDirPath: storageService.charactersDir.path,
      );

      // Now use V2CardService to embed character data into the PNG
      final v2Service = V2CardService();
      await v2Service.saveCardAsPng(card, pngPath, parsed.extractedImagePath);

      // Import via CharacterRepository (reads PNG metadata + inserts into DB).
      // Single-file BYAF: same name-collision prompt as V2 PNG import.
      final repo = Provider.of<CharacterRepository>(context, listen: false);
      final priorIds = {
        for (final c in repo.charactersWithName(card.name)) c.dbId,
      };
      final stableHit = repo.findByStableId(
        card.frontPorchExtensions?.stableId,
      );
      if (stableHit?.dbId != null) priorIds.add(stableHit!.dbId);
      final importedCard = await importCharacterWithNameCollision(
        context,
        repo,
        File(pngPath),
      );

      // Create the imported session: chat history and/or Backyard sampler
      // settings, per the dialog toggles.
      if (importedCard != null) {
        await applyByafGalleryLooks(
          repo: repo,
          imported: importedCard,
          galleryImagePaths: parsed.galleryImagePaths,
          importGalleryImages: result2.importGalleryImages,
          replaceExistingLooks: priorIds.contains(importedCard.dbId),
        );
        final genSettings = result2.applySettings
            ? byafService.toGenerationSettings(parsed)
            : null;
        final db = await AppDatabase.instance();
        await byafService.importSession(
          db,
          parsed,
          importedCard,
          includeMessages: result2.importChatHistory,
          genSettings: genSettings,
        );
      } else {
        deleteByafTempImages(parsed.galleryImagePaths);
      }

      if (context.mounted && importedCard != null) {
        final chatNote = result2.importChatHistory && parsed.messages.isNotEmpty
            ? ' with ${parsed.messages.length} chat messages'
            : '';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Imported "${importedCard.name}" from Backyard AI$chatNote!',
            ),
          ),
        );
      }
    } catch (e) {
      if (preview != null) deleteByafTempImages(preview.galleryImagePaths);
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to import .byaf: $e')));
      }
    }
  }

  /// Mass BYAF import: confirm once (with a chat-history choice for the whole
  /// batch), then drive the shared bulk-progress dialog over the files.
  Future<void> _runBulkByafImport(List<String> paths) async {
    final choice = await showHomeBulkByafConfirm(context, paths);

    if (choice == null || !context.mounted) return;
    final (:importChats, :applySettings) = choice;

    await _bulk.runWithProgress(
      title: 'Import Backyard AI',
      totalCount: paths.length,
      runImport: ({required onProgress, required isCancelled}) =>
          importHomeByafFiles(
            context,
            paths,
            importChats,
            applySettings: applySettings,
            onProgress: onProgress,
            isCancelled: isCancelled,
          ),
    );
  }
}

/// The library grid's Import menu.
void runHomeImportMenu(BuildContext context, String source) {
  switch (source) {
    case 'cards':
      HomeCardImport(context).pickCards();
      break;
    case 'folder':
      HomeBulkImport(context).importFolder();
      break;
    case 'byaf':
      HomeCardImport(context).pickByaf();
      break;
    case 'porch':
      importHomePorchFiles(context);
      break;
  }
}
