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

/// Character/group export and group card import/extract.
///
/// Split out of the _HomePageState god file as a private extension
/// (part of the same library, so it keeps full access to page state).
extension _HomePageTransfer on _HomePageState {

  Future<void> _exportCharacter(BuildContext context, character) async {
    String? outputFile = await PickerPrefs.saveFile(
      category: PickerPrefs.catExport,
      dialogTitle: 'Export Character Card',
      fileName: '${character.name}.png',
      type: FileType.custom,
      allowedExtensions: ['png'],
    );

    if (outputFile != null) {
      if (!outputFile.endsWith('.png')) {
        outputFile += '.png';
      }

      try {
        final v2Service = V2CardService();
        // Bake the ★ starred avatar (a look/expression) as the card cover when
        // set; else the library portrait.
        final cover = Provider.of<CharacterRepository>(
          context,
          listen: false,
        ).coverImageFileFor(character);
        await v2Service.saveCardAsPng(
          character,
          outputFile,
          cover?.path ?? character.imagePath,
        );

        if (context.mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('Exported to $outputFile')));
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('Export failed: $e')));
        }
      }
    }
  }

  /// Export a character as a standalone Character Card V2 `.json` file.
  /// This is the same JSON embedded in exported PNGs and what the importer
  /// accepts, just without the avatar image.
  Future<void> _exportCharacterJson(BuildContext context, character) async {
    final safeName = character.name.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
    String? outputFile = await PickerPrefs.saveFile(
      category: PickerPrefs.catExport,
      dialogTitle: 'Export Character Card (JSON)',
      fileName: '$safeName.json',
      type: FileType.custom,
      allowedExtensions: ['json'],
    );

    if (outputFile == null) return;
    if (!outputFile.toLowerCase().endsWith('.json')) {
      outputFile += '.json';
    }

    try {
      await V2CardService().saveCardAsJson(character, outputFile);
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Exported to $outputFile')));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Export failed: $e')));
      }
    }
  }

  /// Import a Group Card PNG (the novel Front Porch format).
  /// Creates all member characters (with full collision handling) + the group.
  Future<void> _importGroupCard(
    BuildContext context,
    File file,
    GroupCard groupCard,
  ) async {
    final groups = Provider.of<GroupChatRepository>(context, listen: false);
    final storage = Provider.of<StorageService>(context, listen: false);
    final db = Provider.of<AppDatabase>(context, listen: false);
    final result = await GroupCardImporter(
      groups,
      storage,
      db,
    ).importCard(groupCard);
    if (!context.mounted) return;
    if (!result.created) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Group import failed — no members could be created.'),
        ),
      );
      return;
    }
    final msg = result.failCount > 0
        ? 'Partially imported group "${result.groupName}": ${result.successCount} member(s) succeeded, ${result.failCount} failed. The group shell was created with the successful members only (their data + private avatars are fully usable; use "Separate to my library" to extract any as solo characters).'
        : 'Imported group "${result.groupName}" with ${result.successCount} members!';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: result.failCount > 0
            ? AppColors.porchAmberOf(context)
            : AppColors.surfaceContainerOf(context),
      ),
    );
  }

  Future<void> _extractCharactersFromGroup(GroupChat group) async {
    final charRepo = Provider.of<CharacterRepository>(context, listen: false);

    // Real members from decoupled table + private avatars (extends this existing method; "Separate to my library" now functional).
    final groupRepo = Provider.of<GroupChatRepository>(context, listen: false);
    final storage = Provider.of<StorageService>(context, listen: false);
    final members = await groupRepo.getMembersForGroup(group.id);

    if (members.isEmpty) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No characters found in this group.')),
        );
      }
      return;
    }

    int extracted = 0;
    for (final m in members) {
      try {
        final resolvedPath = m.avatarFilename != null
            ? path.join(
                storage.groupsDir.path,
                group.id,
                'avatars',
                m.avatarFilename!,
              )
            : null;
        if (resolvedPath == null || !await File(resolvedPath).exists()) {
          continue;
        }
        final card = m.toCharacterCard(resolvedImagePath: resolvedPath);
        await charRepo.duplicateCharacter(
          card,
        ); // library copy is the intended "Separate to my library" action
        extracted++;
      } catch (e) {
        debugPrint('Failed to extract ${m.name}: $e');
      }
    }

    if (context.mounted) {
      final msg = extracted == 1
          ? 'Extracted 1 character as an individual.'
          : 'Extracted $extracted characters as individuals.';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(msg),
          backgroundColor: AppColors.surfaceContainerOf(context),
        ),
      );
    }
  }

  /// Export a group as a single self-contained PNG "Group Card".
  /// This is a Front Porch novel format (fpa_group chunk) that bundles every
  /// member character (full data + lorebooks + extensions) plus group settings.
  ///
  /// Zero-compromise fidelity: every member is always included, even if the
  /// private avatar file is missing on disk. For those, a full V2 PNG with
  /// placeholder image + embedded metadata is synthesized on the fly so the
  /// recipient can import the complete group and later "Separate to my library"
  /// any or all members as independent characters.
  Future<void> _exportGroup(GroupChat group) async {
    final context = this.context; // capture from StatefulWidget

    final groupRepo = Provider.of<GroupChatRepository>(context, listen: false);
    final storage = Provider.of<StorageService>(context, listen: false);
    final db = Provider.of<AppDatabase>(context, listen: false);

    final members = await groupRepo.getMembersForGroup(group.id);

    if (members.isEmpty) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Cannot export empty group')),
        );
      }
      return;
    }

    final safeName = group.name.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
    String? outputFile = await PickerPrefs.saveFile(
      category: PickerPrefs.catExport,
      dialogTitle: 'Export Group Card',
      fileName: '$safeName.group.png',
      type: FileType.custom,
      allowedExtensions: ['png'],
    );

    if (outputFile != null) {
      if (!outputFile.endsWith('.png')) {
        outputFile += '.png';
      }

      try {
        // Fidelity logic (member avatar embedding, objectives snapshot,
        // stable-id remap, GroupCard assembly) lives in the shared
        // GroupCardExporter so the desktop and web export paths can't diverge.
        await GroupCardExporter(
          groupRepo,
          storage,
          db,
          Provider.of<WorldRepository>(context, listen: false),
        ).exportToFile(group, outputFile);

        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Group card exported to $outputFile')),
          );
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('Group export failed: $e')));
        }
      }
    }
  }

}
