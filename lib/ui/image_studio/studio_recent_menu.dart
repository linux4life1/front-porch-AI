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

import 'package:front_porch_ai/services/image/image.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/services/storage/settings/image_gen_settings.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';
import 'package:front_porch_ai/ui/widgets/widgets.dart';
import 'package:front_porch_ai/utils/utils.dart';

/// The words for a keep choice, shared by the picker and its button.
String studioRecentChoiceLabel(int limit) => switch (limit) {
  kStudioRecentKeepAll => 'Keep all',
  kStudioRecentOff => 'Off',
  _ => 'Keep last $limit',
};

String _choiceDetail(int limit) => switch (limit) {
  kStudioRecentKeepAll => 'Keep all · nothing is trimmed',
  kStudioRecentOff => 'Off · only what I save',
  _ => 'Keep last $limit (about ${(limit * 1.5).round()} MB)',
};

enum _More { open, folder, appFolder, clear }

/// The Recent shelf's header controls: how many to keep, and a menu with the
/// folder and clearing.
class StudioRecentMenu extends StatelessWidget {
  const StudioRecentMenu({
    super.key,
    required this.store,
    required this.limit,
    required this.entries,
  });

  final StudioRecentStore? store;
  final int limit;
  final List<StudioRecentEntry> entries;

  Future<void> _setLimit(BuildContext context, int value) async {
    final storage = context.read<StorageService>();
    await storage.imageGenSettings.setStudioRecentLimit(value);
    await store?.applyLimit();
  }

  Future<void> _more(BuildContext context, _More action) async {
    final storage = context.read<StorageService>();
    switch (action) {
      case _More.open:
        final path = store?.folderPath;
        if (path != null) await _openFolder(path);
      case _More.folder:
        final picked = await GuardedPicker.getDirectoryPath(
          context,
          category: PickerPrefs.catDirectory,
          dialogTitle: 'Choose a folder for Recent pictures',
        );
        if (picked == null) return;
        await storage.imageGenSettings.setStudioRecentFolder(picked);
        store?.folderChanged();
      case _More.appFolder:
        await storage.imageGenSettings.setStudioRecentFolder('');
        store?.folderChanged();
      case _More.clear:
        if (!context.mounted || !await _confirmClear(context)) return;
        await store?.clearUnkept();
    }
  }

  Future<bool> _confirmClear(BuildContext context) async {
    final rolling = entries.where((e) => !e.kept).length;
    final answer = await showWarmDialog<bool>(
      context,
      title: 'Clear Recent pictures?',
      icon: Icons.delete_outline,
      destructive: true,
      content: Text(
        'This deletes $rolling unstarred '
        '${rolling == 1 ? 'picture' : 'pictures'}. Starred ones stay.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Clear'),
        ),
      ],
    );
    return answer == true;
  }

  /// Show the folder in the platform file manager.
  static Future<void> _openFolder(String path) async {
    try {
      await Directory(path).create(recursive: true);
      if (Platform.isWindows) {
        await Process.run('explorer', [path]);
      } else if (Platform.isMacOS) {
        await Process.run('open', [path]);
      } else {
        await Process.run('xdg-open', [path]);
      }
    } on Exception catch (e) {
      debugPrint('StudioRecentMenu: could not open $path: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final custom = context.select<StorageService, bool>(
      (s) => s.imageGenSettings.studioRecentFolder.isNotEmpty,
    );
    final style = TextStyle(
      color: AppColors.formAccentOf(context),
      fontSize: 12,
    );
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        PopupMenuButton<int>(
          key: const Key('studio-recent-limit'),
          tooltip: 'How many Recent pictures to keep',
          initialValue: limit,
          onSelected: (v) => _setLimit(context, v),
          itemBuilder: (_) => [
            for (final choice in kStudioRecentChoices)
              PopupMenuItem(value: choice, child: Text(_choiceDetail(choice))),
          ],
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            child: Text('${studioRecentChoiceLabel(limit)} ▾', style: style),
          ),
        ),
        PopupMenuButton<_More>(
          tooltip: 'More',
          icon: Icon(
            Icons.more_horiz,
            size: 18,
            color: AppColors.iconSecondary(context),
          ),
          onSelected: (a) => _more(context, a),
          itemBuilder: (_) => [
            const PopupMenuItem(value: _More.open, child: Text('Open folder')),
            const PopupMenuItem(
              value: _More.folder,
              child: Text('Choose folder…'),
            ),
            if (custom)
              const PopupMenuItem(
                value: _More.appFolder,
                child: Text('Use the app’s folder'),
              ),
            PopupMenuItem(
              value: _More.clear,
              enabled: entries.any((e) => !e.kept),
              child: const Text('Clear unstarred…'),
            ),
          ],
        ),
      ],
    );
  }
}
