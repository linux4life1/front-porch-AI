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

import 'package:front_porch_ai/models/character_card.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';

/// Modal character picker for the `/join` flow — choose an existing library
/// character to bring into the current 1:1 chat as a Scene Guest (Lite NPC).
///
/// Reuses the same searchable-list pattern as the group-chat member browser,
/// lifted into a reusable dialog. Presentational only: it is handed the already
/// filtered [characters] list (the caller excludes the host + anyone already in
/// the scene) and an [resolveImage] resolver for avatars. Returns the selected
/// [CharacterCard] via `Navigator.pop`, or null when cancelled.
class SceneGuestPickerDialog extends StatefulWidget {
  const SceneGuestPickerDialog({
    super.key,
    required this.characters,
    required this.resolveImage,
    this.initialFilter = '',
  });

  /// Candidates eligible to join (host + present guests already removed).
  final List<CharacterCard> characters;

  /// Resolves a character `imagePath` (basename or full path) to a [File].
  final File? Function(CharacterCard card) resolveImage;

  /// Pre-fills the search box (e.g. the text typed after `/join`).
  final String initialFilter;

  @override
  State<SceneGuestPickerDialog> createState() => _SceneGuestPickerDialogState();
}

class _SceneGuestPickerDialogState extends State<SceneGuestPickerDialog> {
  late final TextEditingController _search;

  @override
  void initState() {
    super.initState();
    _search = TextEditingController(text: widget.initialFilter)
      ..addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  List<CharacterCard> get _filtered {
    final q = _search.text.trim().toLowerCase();
    if (q.isEmpty) return widget.characters;
    return widget.characters
        .where((c) => c.name.toLowerCase().contains(q))
        .toList();
  }

  // Memoized per open dialog: _avatar runs per character row per rebuild,
  // and this dialog rebuilds on every search keystroke — N existsSync per
  // keypress is the io-lint bug class.
  final Map<String, ImageProvider?> _avatarCache = {};

  ImageProvider? _avatar(CharacterCard c) {
    return _avatarCache.putIfAbsent(c.name, () {
      final file = widget.resolveImage(c);
      return (file != null && file.existsSync()) // io-ok: memoized per dialog
          ? FileImage(file)
          : null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final accent = AppColors.relationshipAccent;
    final filtered = _filtered;
    return AlertDialog(
      backgroundColor: AppColors.backgroundOf(context),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(Icons.group_add, color: accent, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Invite a character',
              style: TextStyle(
                color: AppColors.textPrimary(context),
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 460,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _search,
              autofocus: true,
              style: TextStyle(color: AppColors.textPrimary(context)),
              decoration: InputDecoration(
                hintText: 'Search your characters…',
                prefixIcon: const Icon(Icons.search),
                filled: true,
                fillColor: AppColors.surfaceContainerOf(context),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 340,
              child: filtered.isEmpty
                  ? Center(
                      child: Text(
                        widget.characters.isEmpty
                            ? 'No other characters are available to join.'
                            : 'No characters match “${_search.text.trim()}”.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: AppColors.textTertiary(context),
                        ),
                      ),
                    )
                  : ListView.separated(
                      itemCount: filtered.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 6),
                      itemBuilder: (context, i) {
                        final c = filtered[i];
                        final image = _avatar(c);
                        final desc = c.description.trim();
                        return Material(
                          color: AppColors.cardOf(context),
                          borderRadius: BorderRadius.circular(10),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(10),
                            onTap: () => Navigator.of(context).pop(c),
                            child: Padding(
                              padding: const EdgeInsets.all(10),
                              child: Row(
                                children: [
                                  CircleAvatar(
                                    radius: 20,
                                    backgroundColor:
                                        AppColors.surfaceContainerOf(context),
                                    backgroundImage: image,
                                    child: image == null
                                        ? Icon(
                                            Icons.person,
                                            size: 20,
                                            color:
                                                AppColors.iconSecondary(context),
                                          )
                                        : null,
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          c.name,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            color:
                                                AppColors.textPrimary(context),
                                            fontWeight: FontWeight.w600,
                                            fontSize: 14,
                                          ),
                                        ),
                                        if (desc.isNotEmpty)
                                          Padding(
                                            padding:
                                                const EdgeInsets.only(top: 2),
                                            child: Text(
                                              desc,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: TextStyle(
                                                color: AppColors.textTertiary(
                                                  context,
                                                ),
                                                fontSize: 12,
                                              ),
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Icon(Icons.add, size: 18, color: accent),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(
            'Cancel',
            style: TextStyle(color: AppColors.textSecondary(context)),
          ),
        ),
      ],
    );
  }
}
