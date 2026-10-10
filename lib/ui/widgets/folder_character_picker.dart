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
import 'package:path/path.dart' as path;

import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';
import 'package:front_porch_ai/ui/widgets/widgets.dart';

/// What a folder-aware pick surface shows at one (folder, query) position.
/// Computed by [buildFolderPickView] — the ONE set of folder-browsing rules
/// shared by every "pick from the library" surface (group-creation wizard,
/// Stoop share Pick step), so their behavior can't drift while their visual
/// treatments differ.
class FolderPickView {
  const FolderPickView({
    required this.folders,
    required this.folderCounts,
    required this.characters,
    required this.groups,
  });

  /// Navigable subfolders at this level — only those holding at least one
  /// eligible candidate anywhere below (a picker is for finding candidates,
  /// not managing empty folders). Empty while searching.
  final List<CharacterFolder> folders;

  /// folder id → eligible candidate count (characters + groups, recursive)
  /// for every folder in [folders].
  final Map<String, int> folderCounts;

  final List<CharacterCard> characters;
  final List<GroupChat> groups;
}

/// The home grid's folder rules, applied to a pick surface:
/// - Browsing ([query] empty): the characters/groups DIRECTLY at [folderId]
///   (null = unfoldered top level) + navigable subfolder tiles.
/// - Searching: folders hide and the query matches ALL eligible candidates
///   regardless of folder (name always; description/personality too when
///   [matchDescriptions]), so nothing nested is unfindable.
/// All lists come back name-sorted.
FolderPickView buildFolderPickView({
  required FolderService folderService,
  required List<CharacterCard> characters,
  List<GroupChat> groups = const [],
  required String? folderId,
  required String query,
  bool matchDescriptions = false,
}) {
  List<CharacterCard> visibleCharacters;
  List<GroupChat> visibleGroups;
  var folders = <CharacterFolder>[];
  final counts = <String, int>{};

  if (query.isNotEmpty) {
    visibleCharacters = characters
        .where(
          (c) =>
              c.name.toLowerCase().contains(query) ||
              (matchDescriptions &&
                  (c.description.toLowerCase().contains(query) ||
                      c.personality.toLowerCase().contains(query))),
        )
        .toList();
    visibleGroups = groups
        .where((g) => g.name.toLowerCase().contains(query))
        .toList();
  } else {
    visibleCharacters = characters
        .where(
          (c) =>
              (c.imagePath == null
                      ? null
                      : folderService.getFolderForCharacter(c.imagePath!))
                  ?.id ==
              folderId,
        )
        .toList();
    visibleGroups = groups
        .where((g) => folderService.getFolderForGroup(g.id)?.id == folderId)
        .toList();

    int eligibleIn(CharacterFolder f) {
      final filenames = folderService
          .getCharactersInFolderRecursive(f.id)
          .toSet();
      final groupIds = folderService.groupIdsInFolderRecursive(f.id).toSet();
      return characters
              .where(
                (c) =>
                    c.imagePath != null &&
                    filenames.contains(path.basename(c.imagePath!)),
              )
              .length +
          groups.where((g) => groupIds.contains(g.id)).length;
    }

    folders = folderService.getSubfolders(folderId).where((f) {
      final n = eligibleIn(f);
      if (n > 0) counts[f.id] = n;
      return n > 0;
    }).toList()..sort((a, b) => a.name.compareTo(b.name));
  }

  visibleCharacters.sort((a, b) => a.name.compareTo(b.name));
  visibleGroups.sort((a, b) => a.name.compareTo(b.name));
  return FolderPickView(
    folders: folders,
    folderCounts: counts,
    characters: visibleCharacters,
    groups: visibleGroups,
  );
}

/// The ONE folder-aware character browser for "pick characters" surfaces
/// (docs/design/folder-groups.md, related queued item). First consumer is the
/// group-chat creation wizard's Members step; the Scene Guest picker and the
/// Stoop share Pick step share the same flat-grid pattern and should adopt
/// this widget rather than growing their own folder logic.
///
/// Behavior mirrors the home grid's folder rules:
/// - Browsing (no query): subfolder tiles for navigation + the characters that
///   live DIRECTLY at the current level (top level = unfoldered). Folders with
///   no eligible characters anywhere below them are hidden — a picker is for
///   finding candidates, not managing empty folders.
/// - Searching: folder tiles hide and the query matches ALL eligible
///   characters regardless of folder (name/description/personality), so
///   nothing nested is ever unfindable.
///
/// Presentational + self-contained: the caller supplies the already-eligible
/// [characters] (e.g. minus current members) and gets taps back via
/// [onTapCharacter]. Folder membership is read live from [FolderService], so
/// the list shrinking as members are added needs no extra plumbing.
class FolderCharacterPicker extends StatefulWidget {
  const FolderCharacterPicker({
    super.key,
    required this.characters,
    required this.folderService,
    required this.onTapCharacter,
    this.searchHint = 'Search available characters...',
    this.emptyMessage = 'No more characters available.',
    this.trailingIcon = Icons.add,
    this.accent,
    this.resolveImage,
  });

  /// Eligible candidates only — the caller excludes anyone already picked.
  final List<CharacterCard> characters;

  final FolderService folderService;
  final void Function(CharacterCard character) onTapCharacter;
  final String searchHint;
  final String emptyMessage;

  /// Icon on each character tile (an add/plus by default).
  final IconData trailingIcon;

  /// Accent for the trailing icon; defaults to the warm-porch amber.
  final Color? accent;

  /// Optional avatar resolver for callers whose `imagePath`s are basenames.
  /// Defaults to using the card's `imagePath` as an absolute path (the same
  /// thing the group wizard's old browser did).
  final File Function(CharacterCard card)? resolveImage;

  @override
  State<FolderCharacterPicker> createState() => _FolderCharacterPickerState();
}

class _FolderCharacterPickerState extends State<FolderCharacterPicker> {
  final _searchController = TextEditingController();
  String _query = '';
  String? _folderId; // null = top level
  final List<String> _folderStack = [];

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      setState(() => _query = _searchController.text.trim().toLowerCase());
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _enterFolder(CharacterFolder folder) {
    setState(() {
      if (_folderId != null) _folderStack.add(_folderId!);
      _folderId = folder.id;
    });
  }

  void _navigateBack() {
    setState(() {
      _folderId = _folderStack.isNotEmpty ? _folderStack.removeLast() : null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final accent = widget.accent ?? AppColors.porchAmberOf(context);
    final browsing = _query.isEmpty;
    final view = buildFolderPickView(
      folderService: widget.folderService,
      characters: widget.characters,
      folderId: _folderId,
      query: _query,
      matchDescriptions: true,
    );
    final folders = view.folders;
    final characters = view.characters;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _searchController,
          decoration: InputDecoration(
            hintText: widget.searchHint,
            prefixIcon: const Icon(Icons.search),
            filled: true,
            fillColor: AppColors.surfaceContainerOf(context),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide.none,
            ),
          ),
        ),
        if (browsing && _folderId != null) ...[
          const SizedBox(height: 8),
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back),
                iconSize: 18,
                visualDensity: VisualDensity.compact,
                tooltip: 'Back',
                onPressed: _navigateBack,
              ),
              const SizedBox(width: 4),
              Icon(Icons.folder, size: 16, color: accent),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  widget.folderService.getFolderPath(_folderId!),
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary(context),
                  ),
                ),
              ),
            ],
          ),
        ],
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final folder in folders)
              _FolderTile(
                folder: folder,
                count: view.folderCounts[folder.id] ?? 0,
                accent: accent,
                onTap: () => _enterFolder(folder),
              ),
            for (final c in characters)
              _CharacterTile(
                character: c,
                trailingIcon: widget.trailingIcon,
                accent: accent,
                resolveImage: widget.resolveImage,
                onTap: () => widget.onTapCharacter(c),
              ),
          ],
        ),
        if (folders.isEmpty && characters.isEmpty)
          Padding(
            padding: const EdgeInsets.all(12),
            child: Text(
              _query.isNotEmpty
                  ? 'No characters match "${_searchController.text.trim()}".'
                  : widget.emptyMessage,
              style: TextStyle(color: AppColors.textTertiary(context)),
            ),
          ),
      ],
    );
  }
}

/// A subfolder navigation tile — same footprint as the character tiles so the
/// two mix naturally in one Wrap.
class _FolderTile extends StatelessWidget {
  const _FolderTile({
    required this.folder,
    required this.count,
    required this.accent,
    required this.onTap,
  });

  final CharacterFolder folder;
  final int count;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        width: 140,
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: AppColors.cardOf(context),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: accent.withValues(alpha: 0.45)),
        ),
        child: Row(
          children: [
            Icon(Icons.folder, size: 22, color: accent),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                folder.name,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 13),
              ),
            ),
            Text(
              '$count',
              style: TextStyle(
                fontSize: 12,
                color: AppColors.textTertiary(context),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CharacterTile extends StatelessWidget {
  const _CharacterTile({
    required this.character,
    required this.trailingIcon,
    required this.accent,
    required this.onTap,
    this.resolveImage,
  });

  final CharacterCard character;
  final IconData trailingIcon;
  final Color accent;
  final VoidCallback onTap;
  final File Function(CharacterCard card)? resolveImage;

  @override
  Widget build(BuildContext context) {
    final imageFile = character.imagePath == null
        ? null
        : (resolveImage?.call(character) ?? File(character.imagePath!));
    return InkWell(
      onTap: onTap,
      child: Container(
        width: 140,
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: AppColors.cardOf(context),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.borderOf(context)),
        ),
        child: Row(
          children: [
            // A character made without a portrait shows the person icon, not
            // its flat coloured card picture.
            RealPortrait(
              file: imageFile,
              portrait: (_, file) => CircleAvatar(
                radius: 18,
                backgroundImage: FileImage(file),
                // A card whose portrait file went missing still renders
                // (blank circle) instead of surfacing a decode exception.
                onBackgroundImageError: (_, _) {},
              ),
              // The Home card's no-portrait look.
              noPortrait: (_) => CircleAvatar(
                radius: 18,
                backgroundColor: AppColors.surfaceContainerOf(context),
                child: Icon(
                  Icons.person,
                  size: 16,
                  color: AppColors.iconSecondary(context),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                character.name,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 13),
              ),
            ),
            Icon(trailingIcon, size: 18, color: accent),
          ],
        ),
      ),
    );
  }
}
