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

part of '../home_page.dart';

/// PNG/JSON and BYAF import. Delete / edit / duplicate stay on
/// [_HomePageDialogs].
extension _HomePageDialogsImport on _HomePageState {
  Future<void> _importCharacter(BuildContext context) async {
    final result = await PickerPrefs.pickFiles(
      category: PickerPrefs.catImport,
      type: FileType.custom,
      allowedExtensions: ['png', 'json'],
      allowMultiple: true,
    );

    if (result == null || result.files.isEmpty) return;
    if (!context.mounted) return;

    final files = <File>[];
    for (final f in result.files) {
      final path = await PickerPrefs.localPathOrTemp(f);
      if (path != null) files.add(File(path));
    }

    if (files.isEmpty) return;

    // Single file: check if this is a Front Porch Group Card first (novel format)
    if (files.length == 1) {
      final file = files.first;
      try {
        final groupService = GroupCardService();
        final groupCard = await groupService.readGroupCard(file.path);

        if (groupCard != null) {
          // This is a Group Card PNG — do the special group import
          await _importGroupCard(context, file, groupCard);
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
    _runBulkImport(context, files);
  }

  Future<void> _importByaf(BuildContext context) async {
    final result = await PickerPrefs.pickFiles(
      category: PickerPrefs.catImport,
      type: FileType.custom,
      allowedExtensions: ['byaf'],
      allowMultiple: true,
    );

    if (result == null || result.files.isEmpty) return;
    final paths = <String>[];
    for (final f in result.files) {
      final path = await PickerPrefs.localPathOrTemp(f);
      if (path != null) paths.add(path);
    }
    if (paths.isEmpty || !context.mounted) return;

    // Multiple files → bulk import with a progress dialog (no per-file preview),
    // mirroring the bulk V2 PNG importer. A single file keeps the rich preview
    // dialog below.
    if (paths.length > 1) {
      await _runBulkByafImport(context, paths);
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
  Future<void> _runBulkByafImport(
    BuildContext context,
    List<String> paths,
  ) async {
    bool importChats = true;
    bool applySettings = true;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          backgroundColor: AppColors.surfaceOf(ctx),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(
              color: AppColors.porchHoneyOf(ctx).withValues(alpha: 0.5),
            ),
          ),
          title: Row(
            children: [
              Icon(Icons.library_add, color: AppColors.porchHoneyOf(ctx)),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Import ${paths.length} Backyard AI characters?',
                  style: TextStyle(color: AppColors.textPrimary(ctx)),
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Each .byaf will be imported as a character card. (No per-file '
                'preview is shown for batch imports.)',
                style: TextStyle(
                  color: AppColors.textSecondary(ctx),
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 8),
              CheckboxListTile(
                value: importChats,
                onChanged: (v) => setLocal(() => importChats = v ?? true),
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                title: Text(
                  'Also import chat history',
                  style: TextStyle(color: AppColors.textPrimary(ctx)),
                ),
              ),
              CheckboxListTile(
                value: applySettings,
                onChanged: (v) => setLocal(() => applySettings = v ?? true),
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                title: Text(
                  'Apply Backyard model settings',
                  style: TextStyle(color: AppColors.textPrimary(ctx)),
                ),
                subtitle: Text(
                  "Each import uses its archive's sampler values "
                  '(temperature, min-p, …) for the imported chat',
                  style: TextStyle(
                    color: AppColors.textSecondary(ctx),
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(
                'Cancel',
                style: TextStyle(color: AppColors.textTertiary(ctx)),
              ),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text('Import ${paths.length}'),
            ),
          ],
        ),
      ),
    );

    if (confirmed != true || !context.mounted) return;

    _runBulkProgressImport(
      context,
      title: 'Import Backyard AI',
      totalCount: paths.length,
      runImport: ({required onProgress, required isCancelled}) =>
          _importByafFiles(
            context,
            paths,
            importChats,
            applySettings: applySettings,
            onProgress: onProgress,
            isCancelled: isCancelled,
          ),
    );
  }

  /// Per-file BYAF import loop used by the bulk progress dialog. Mirrors the
  /// single-file `_importByaf` pipeline (parse → convert → embed V2 PNG →
  /// import → optional chat history) and reports progress per file.
  Future<void> _importByafFiles(
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
}
