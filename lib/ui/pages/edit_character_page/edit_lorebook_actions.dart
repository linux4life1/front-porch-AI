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

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/dialogs/dialogs.dart';
import 'package:front_porch_ai/ui/pages/edit_character_page/edit_character_lore_io.dart';
import 'package:front_porch_ai/ui/widgets/widgets.dart';
import 'package:front_porch_ai/utils/utils.dart';

/// The Lorebook tab's actions over one list of entries: add, edit, remove,
/// Import file, Export file and From character. One implementation for the
/// character editor and the group editor, so the two tabs cannot drift.
class EditorLorebookActions {
  EditorLorebookActions({
    required this.context,
    required this.mounted,
    required this.entries,
    required this.changed,
    required this.bookName,
    this.excludeCharacterName,
  });

  final BuildContext Function() context;
  final bool Function() mounted;

  /// The list the editor holds; the actions edit it in place.
  final List<LorebookEntry> Function() entries;

  /// Repaints the editor after the list changed.
  final VoidCallback changed;

  /// The name an export file is named for (the character or the group).
  final String Function() bookName;

  /// "From character" leaves this character out of its list.
  final String? excludeCharacterName;

  void snack(String message) {
    ScaffoldMessenger.of(
      context(),
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> add() async {
    final result = await showLorebookEntryDialog(context: context());
    if (result != null) {
      entries().add(result);
      changed();
    }
  }

  void remove(int index) {
    entries().removeAt(index);
    changed();
  }

  Future<void> edit(int index) async {
    final result = await showLorebookEntryDialog(
      context: context(),
      existing: entries()[index],
      showEnabled: true,
    );
    if (result != null) {
      entries()[index] = result;
      changed();
    }
  }

  Future<void> importFromCharacter() async {
    final repo = Provider.of<CharacterRepository>(context(), listen: false);
    final found = await showImportCharacterLoreDialog(
      context: context(),
      characters: repo.characters,
      excludeCharacterName: excludeCharacterName,
    );
    if (found == null || found.isEmpty) return;
    entries().addAll(found);
    changed();
    if (mounted()) snack('Added ${found.length} entries from character.');
  }

  Future<void> importFile() async {
    final result = await GuardedPicker.pickFiles(
      context(),
      category: PickerPrefs.catImport,
      type: FileType.custom,
      allowedExtensions: ['json'],
    );
    if (result == null || result.files.isEmpty) return;

    try {
      final lorebook = parseLorebookImport(
        await result.files.single.readAsBytes(),
      );

      if (lorebook.entries.isEmpty) {
        if (mounted()) snack('No entries found in file.');
        return;
      }

      entries().addAll(lorebook.entries);
      changed();

      if (mounted()) snack('Imported ${lorebook.entries.length} entries.');
    } on FormatException catch (e) {
      if (mounted()) snack('Invalid file format: ${e.message}');
    } on Exception catch (_) {
      if (mounted()) snack('Import failed. Please try again.');
    }
  }

  /// World-info JSON, the same shape Import file already accepts.
  Future<void> exportFile() async {
    if (entries().isEmpty) {
      if (!mounted()) return;
      snack('No lorebook entries to export.');
      return;
    }

    final selected = await showLorebookExportPicker(
      context: context(),
      entries: entries(),
    );
    if (selected == null || selected.isEmpty || !mounted()) return;

    final name = bookName().trim();
    final bytes = encodeLorebookExport(selected, name);

    try {
      final path = await GuardedPicker.saveFile(
        context(),
        category: PickerPrefs.catExport,
        dialogTitle: 'Export lorebook',
        fileName: lorebookExportFileName(name),
        type: FileType.custom,
        allowedExtensions: const ['json'],
        bytes: bytes,
      );
      if (path == null || !mounted()) return;
      final n = selected.length;
      snack('Exported $n ${n == 1 ? 'entry' : 'entries'}.');
    } catch (e) {
      if (!mounted()) return;
      snack('Export failed: $e');
    }
  }
}
