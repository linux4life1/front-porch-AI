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
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:front_porch_ai/services/image/image.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/services/storage/settings/image_gen_settings.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';

import 'studio_recent_menu.dart';
import 'studio_recent_thumb.dart';

/// Image Studio's Recent shelf: every Create and Edit result, kept on disk
/// so closing the Studio or restarting the app loses nothing. The phone's
/// Studio shows the same pictures ([StudioRecentStore.of]).
class StudioRecentShelf extends StatefulWidget {
  const StudioRecentShelf({
    super.key,
    required this.onRestore,
    this.onEditPicture,
    this.selectedName,
  });

  /// Bring a picture and its prompt back into the workspace.
  final void Function(StudioRecentEntry entry, Uint8List bytes) onRestore;

  /// Use a picture as the one to edit; null hides that menu item.
  final ValueChanged<Uint8List>? onEditPicture;

  /// The picture the workspace shows now, outlined on the shelf.
  final String? selectedName;

  @override
  State<StudioRecentShelf> createState() => _StudioRecentShelfState();
}

class _StudioRecentShelfState extends State<StudioRecentShelf> {
  StudioRecentStore? _store;
  List<StudioRecentEntry> _entries = const [];
  int _reads = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final store = StudioRecentStore.of(context.read<StorageService>());
    if (identical(store, _store)) return;
    _store?.removeListener(_reload);
    _store = store..addListener(_reload);
    _reload();
  }

  @override
  void dispose() {
    _store?.removeListener(_reload);
    super.dispose();
  }

  Future<void> _reload() async {
    final read = ++_reads;
    final store = _store;
    if (store == null) return;
    try {
      final entries = await store.list();
      if (mounted && read == _reads) setState(() => _entries = entries);
    } on FileSystemException catch (e) {
      debugPrint('StudioRecentShelf: could not read the shelf: $e');
    }
  }

  void _say(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<Uint8List?> _bytes(StudioRecentEntry entry) async {
    try {
      return await File(entry.path).readAsBytes();
    } on FileSystemException catch (e) {
      debugPrint('StudioRecentShelf: ${entry.name} is unreadable: $e');
      _say('That picture is gone.');
      await _reload();
      return null;
    }
  }

  Future<void> _act(StudioRecentEntry entry, StudioRecentAction action) async {
    final store = _store;
    if (store == null) return;
    try {
      switch (action) {
        case StudioRecentAction.restore:
          final bytes = await _bytes(entry);
          if (bytes != null && mounted) widget.onRestore(entry, bytes);
        case StudioRecentAction.edit:
          final bytes = await _bytes(entry);
          if (bytes != null && mounted) widget.onEditPicture?.call(bytes);
        case StudioRecentAction.keep:
          await store.setKept(entry.name, !entry.kept);
        case StudioRecentAction.delete:
          await store.delete(entry.name);
      }
    } on FileSystemException catch (e) {
      debugPrint('StudioRecentShelf: ${action.name} failed: $e');
      _say('Could not change that picture: ${e.message}');
    }
  }

  @override
  Widget build(BuildContext context) {
    final limit = context.select<StorageService, int>(
      (s) => s.imageGenSettings.studioRecentLimit,
    );
    final off = limit == kStudioRecentOff;
    final shown = off ? _entries.where((e) => e.kept).toList() : _entries;
    final secondary = AppColors.textSecondary(context);
    final hint = TextStyle(
      color: AppColors.textTertiary(context),
      fontSize: 11,
    );
    final now = DateTime.now();
    final folder = _store?.folderPath;
    return Column(
      key: const Key('studio-recent-shelf'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                _title(limit),
                style: TextStyle(
                  color: secondary,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            StudioRecentMenu(store: _store, limit: limit, entries: _entries),
          ],
        ),
        const SizedBox(height: 6),
        if (shown.isEmpty)
          Text(
            off
                ? 'Recent is off. Pictures stay only when you save them.'
                : 'Pictures you make land here and stay after you close '
                      'the Studio.',
            style: hint,
          )
        else ...[
          SizedBox(
            height: 78,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: shown.length,
              separatorBuilder: (first, second) => const SizedBox(width: 8),
              itemBuilder: (context, i) => StudioRecentThumb(
                entry: shown[i],
                now: now,
                selected: shown[i].name == widget.selectedName,
                canEdit: widget.onEditPicture != null,
                onAction: (action) => _act(shown[i], action),
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Tap a picture to bring it back. Right-click or long-press for '
            'more. Starred pictures are never trimmed.'
            '${folder == null ? '' : ' Kept in $folder.'}',
            style: hint,
          ),
        ],
      ],
    );
  }

  String _title(int limit) {
    final kept = _entries.where((e) => e.kept).length;
    final rolling = _entries.length - kept;
    final starred = kept == 0 ? '' : ' · $kept starred';
    if (limit == kStudioRecentOff) return 'Recent · off$starred';
    if (limit == kStudioRecentKeepAll) return 'Recent · $rolling$starred';
    return 'Recent · $rolling of $limit$starred';
  }
}
