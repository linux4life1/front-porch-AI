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

/// `.porch` / `.porchpack` files (issue #348): export from the multi-select
/// bar, import from the Import menu.
extension _HomePagePorch on _HomePageState {
  /// One character saves as a `.porch`; two or more as one `.porchpack`.
  /// Groups are not part of this yet.
  Future<void> _exportSelectedPorch(Set<String> selectedIds) async {
    final repo = Provider.of<CharacterRepository>(context, listen: false);
    final cards = [
      for (final c in repo.characters)
        if (selectedIds.contains(c.stableGroupId)) c,
    ];
    final groupsLeftOut = _selection.groupIds.isNotEmpty;
    if (cards.isEmpty) {
      await _porchMessage(
        'Nothing to export',
        'Pick at least one character. Groups can’t be exported to a .porch '
            'file yet.',
      );
      return;
    }
    final exporter = PorchExporter(
      repo: repo,
      chat: Provider.of<ChatService>(context, listen: false),
      storage: Provider.of<StorageService>(context, listen: false),
    );
    final out = await _withPorchProgress(
      'Exporting characters',
      'The export didn’t finish. Try again; if it keeps failing, export '
          'fewer characters at a time.',
      (progress) => exporter.exportCards(cards, onProgress: progress),
    );
    if (out == null || !mounted) return;
    final ext = out.fileName.endsWith('.$kPorchPackExtension')
        ? kPorchPackExtension
        : kPorchExtension;
    // A save window that fails explains itself (GuardedPicker) and returns
    // null like a cancel.
    final saved = await GuardedPicker.saveFile(
      context,
      category: PickerPrefs.catExport,
      bytes: out.bytes,
      dialogTitle: 'Save characters',
      fileName: out.fileName,
      type: FileType.custom,
      allowedExtensions: [ext],
    );
    if (saved == null || !mounted) return;
    _cancelSelection();
    final n = cards.length;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Saved $n character${n == 1 ? '' : 's'} to '
          '${path.basename(saved)}.'
          '${groupsLeftOut ? ' Groups were left out.' : ''}',
        ),
      ),
    );
  }

  /// The Import menu's `.porch` entry: the picker shows only `.porch` and
  /// `.porchpack`, and the importer refuses anything else by name.
  Future<void> _importPorchFiles() async {
    final picked = await GuardedPicker.pickFiles(
      context,
      category: PickerPrefs.catImport,
      dialogTitle: 'Import Front Porch characters',
      type: FileType.custom,
      allowedExtensions: const [kPorchExtension, kPorchPackExtension],
      allowMultiple: true,
    );
    if (picked == null || picked.files.isEmpty || !mounted) return;
    await _importPorch([
      for (final f in picked.files) (name: f.name, read: f.readAsBytes),
    ]);
  }

  /// Dropped `.porch` / `.porchpack` files: the same importer and summary
  /// as the Import menu.
  Future<void> _importPorchPaths(List<String> paths) => _importPorch([
    for (final p in paths)
      (name: path.basename(p), read: () => File(p).readAsBytes()),
  ]);

  Future<void> _importPorch(
    List<({String name, Future<Uint8List> Function() read})> files,
  ) async {
    final importer = PorchImporter(
      repo: Provider.of<CharacterRepository>(context, listen: false),
      chat: Provider.of<ChatService>(context, listen: false),
    );
    final report = await _withPorchProgress(
      'Importing characters',
      'The import didn’t finish. Try again; if it keeps failing, import '
          'fewer files at a time.',
      (progress) async => importer.importFiles([
        for (final f in files) (name: f.name, bytes: await f.read()),
      ], onProgress: progress),
    );
    if (report == null || !mounted) return;
    await _porchMessage(
      report.imported.isEmpty ? 'Nothing new imported' : 'Characters imported',
      report.message,
    );
  }

  /// Runs [work] under a progress dialog. A refusal or failure closes it and
  /// says what happened in plain words; returns null then.
  Future<T?> _withPorchProgress<T>(
    String title,
    String failedWords,
    Future<T> Function(void Function(int done, int total, String name)) work,
  ) async {
    final status = ValueNotifier<String>('Starting…');
    final fraction = ValueNotifier<double?>(null);
    final dialog = showWarmDialog<void>(
      context,
      title: title,
      icon: Icons.inventory_2_outlined,
      accent: AppColors.porchHoneyOf(context),
      barrierDismissible: false,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ValueListenableBuilder<double?>(
            valueListenable: fraction,
            builder: (ctx, v, _) => LinearProgressIndicator(
              value: v,
              color: AppColors.porchHoneyOf(ctx),
              backgroundColor: AppColors.surfaceContainerOf(ctx),
            ),
          ),
          const SizedBox(height: 12),
          ValueListenableBuilder<String>(
            valueListenable: status,
            builder: (_, s, _) => WarmDialogText(s),
          ),
        ],
      ),
    );
    T? result;
    String? failure;
    try {
      result = await work((done, total, name) {
        fraction.value = total == 0 ? null : done / total;
        status.value = name.isEmpty
            ? 'Finishing…'
            : '$name (${done + 1} of $total)';
      });
    } on PorchRefused catch (e) {
      failure = e.message;
    } catch (e) {
      debugPrint('[porch] $title failed: $e');
      failure = failedWords;
    }
    if (mounted) {
      Navigator.of(context).pop();
      await dialog;
    }
    status.dispose();
    fraction.dispose();
    if (failure != null && mounted) {
      await _porchMessage('$title stopped', failure);
    }
    return result;
  }

  Future<void> _porchMessage(String title, String message) {
    return showWarmDialog<void>(
      context,
      title: title,
      icon: Icons.inventory_2_outlined,
      accent: AppColors.porchHoneyOf(context),
      width: 400,
      content: WarmDialogText(message),
      actions: [warmDialogCancel(context, label: 'OK')],
    );
  }
}
