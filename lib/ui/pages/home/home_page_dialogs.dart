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

/// Folder + delete confirmation dialogs and the move-to-folder flow.
///
/// Split out of the _HomePageState god file as a private extension
/// (part of the same library, so it keeps full access to page state).
extension _HomePageDialogs on _HomePageState {
  void _confirmDeleteCharacter(BuildContext context, CharacterCard character) {
    showWarmDialog(
      context,
      title: 'Delete Character',
      icon: Icons.warning_amber_rounded,
      destructive: true,
      content: WarmDialogText(
        'Are you sure you want to delete "${character.name}"?\n\nThis will '
        'permanently remove the character card and its image file. This action '
        'cannot be undone.',
      ),
      actions: [
        warmDialogCancel(context),
        warmDialogConfirm(
          context,
          label: 'Delete',
          destructive: true,
          onPressed: () async {
            Navigator.of(context).pop();
            final repo = Provider.of<CharacterRepository>(
              context,
              listen: false,
            );
            final worldRepo = Provider.of<WorldRepository>(
              context,
              listen: false,
            );
            final storageService = Provider.of<StorageService>(
              context,
              listen: false,
            );
            await repo.deleteCharacter(
              character,
              worldRepo: worldRepo,
              chatsDir: storageService.chatsDir,
            );
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('${character.name} has been deleted.')),
              );
            }
          },
        ),
      ],
    );
  }

  /// Mass delete for the select-mode bar: resolve the selection ids (the
  /// imagePath-basename scheme _toggleSelect writes) back to cards, then run
  /// the shared severe-confirm purge.
  Future<void> _massDeleteSelected(Set<String> ids) async {
    final repo = Provider.of<CharacterRepository>(context, listen: false);
    final cards = repo.characters.where((c) {
      final id = c.imagePath != null
          ? path.basenameWithoutExtension(c.imagePath!)
          : c.name.replaceAll(RegExp(r'[^\w\s]'), '').replaceAll(' ', '_');
      return ids.contains(id);
    }).toList();
    if (cards.isEmpty) return;

    await _runMassDelete(
      cards,
      title: 'Delete ${cards.length} Characters?',
      message:
          'This will PERMANENTLY delete ${cards.length} '
          'character${cards.length == 1 ? '' : 's'} — their cards, image '
          'files, chat histories, and any linked worlds. There is no undo '
          'and no recycle bin.',
      afterDelete: () async => _cancelSelection(),
    );
  }

  /// The ONE severe-delete pipeline shared by mass select and
  /// delete-folder-with-characters: typed-DELETE gate → progress dialog →
  /// CharacterRepository.deleteCharacters → optional follow-up → snackbar.
  Future<void> _runMassDelete(
    List<CharacterCard> cards, {
    required String title,
    required String message,
    Future<void> Function()? afterDelete,
  }) async {
    final confirmed = await showTypeDeleteDialog(
      context,
      title: title,
      message: message,
    );
    if (!confirmed || !mounted) return;

    final repo = Provider.of<CharacterRepository>(context, listen: false);
    final worldRepo = Provider.of<WorldRepository>(context, listen: false);
    final storage = Provider.of<StorageService>(context, listen: false);

    final progress = ValueNotifier<int>(0);
    // Non-dismissible counter while a 100+ card purge grinds through file IO.
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surfaceOf(ctx),
        content: ValueListenableBuilder<int>(
          valueListenable: progress,
          builder: (ctx, done, _) => Row(
            children: [
              const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2.5),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  'Deleting… $done of ${cards.length}',
                  style: TextStyle(color: AppColors.textPrimary(ctx)),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    var deleted = 0;
    try {
      deleted = await repo.deleteCharacters(
        cards,
        worldRepo: worldRepo,
        chatsDir: storage.chatsDir,
        onProgress: (done, _) => progress.value = done,
      );
      await afterDelete?.call();
    } finally {
      if (mounted) Navigator.of(context, rootNavigator: true).pop();
      progress.dispose();
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Deleted $deleted character${deleted == 1 ? '' : 's'}.',
          ),
        ),
      );
    }
  }

  Future<void> _editCharacter(
    BuildContext context,
    CharacterCard character,
  ) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => EditCharacterPage(character: character),
      ),
    );
    // No loadCharacters() needed here — updateCharacter() already updates the
    // in-memory list and calls notifyListeners(). Calling loadCharacters() was
    // re-reading outdated in-memory extensions from the cache and overwriting
    // the freshly-saved values.
  }

  Future<void> _duplicateCharacter(
    BuildContext context,
    CharacterCard character,
  ) async {
    try {
      await Provider.of<CharacterRepository>(
        context,
        listen: false,
      ).duplicateCharacter(character);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Character duplicated successfully.')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to duplicate: $e')));
      }
    }
  }

  Future<void> _importCharacter(BuildContext context) async {
    final result = await PickerPrefs.pickFiles(
      category: PickerPrefs.catImport,
      type: FileType.custom,
      allowedExtensions: ['png', 'json'],
      allowMultiple: true,
    );

    if (result == null || result.files.isEmpty) return;
    if (!context.mounted) return;

    final files = result.files
        .where((f) => f.path != null)
        .map((f) => File(f.path!))
        .toList();

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

        // Normal character card
        final repo = Provider.of<CharacterRepository>(context, listen: false);
        final card = await repo.importCharacter(file);
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
    final paths = result.files
        .where((f) => f.path != null)
        .map((f) => f.path!)
        .toList();
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

    try {
      // Parse the .byaf archive
      final preview = await byafService.parseByaf(filePath);

      if (!context.mounted) return;

      // Show preview dialog
      final result2 = await showDialog<ByafImportResult>(
        context: context,
        builder: (context) => ByafImportDialog(preview: preview),
      );

      if (result2 == null || !result2.confirmed || !context.mounted) return;

      // Convert to CharacterCard
      final card = byafService.toCharacterCard(preview);

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
      await v2Service.saveCardAsPng(card, pngPath, preview.extractedImagePath);

      // Import via CharacterRepository (reads PNG metadata + inserts into DB)
      final repo = Provider.of<CharacterRepository>(context, listen: false);
      final importedCard = await repo.importCharacter(File(pngPath));

      // Create the imported session: chat history and/or Backyard sampler
      // settings, per the dialog toggles.
      if (importedCard != null) {
        final genSettings = result2.applySettings
            ? byafService.toGenerationSettings(preview)
            : null;
        final db = await AppDatabase.instance();
        await byafService.importSession(
          db,
          preview,
          importedCard,
          includeMessages: result2.importChatHistory,
          genSettings: genSettings,
        );
      }

      if (context.mounted && importedCard != null) {
        final chatNote =
            result2.importChatHistory && preview.messages.isNotEmpty
            ? ' with ${preview.messages.length} chat messages'
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
      try {
        final preview = await byafService.parseByaf(paths[i]);
        final card = byafService.toCharacterCard(preview);
        final pngPath = await byafService.saveCharacterPng(
          card,
          charactersDirPath: storage.charactersDir.path,
        );
        await v2Service.saveCardAsPng(
          card,
          pngPath,
          preview.extractedImagePath,
        );
        final imported = await repo.importCharacter(File(pngPath));
        if (imported != null) {
          final genSettings = applySettings
              ? byafService.toGenerationSettings(preview)
              : null;
          final db = await AppDatabase.instance();
          await byafService.importSession(
            db,
            preview,
            imported,
            includeMessages: importChats,
            genSettings: genSettings,
          );
        }
        onProgress(
          i + 1,
          paths.length,
          imported?.name ?? name,
          imported == null ? 'Import returned no character' : null,
        );
      } catch (e) {
        onProgress(i + 1, paths.length, name, '$e');
      }
    }
  }
}
