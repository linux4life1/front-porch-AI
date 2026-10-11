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

import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/pages/repository/stoop_glass.dart';
import 'package:front_porch_ai/ui/pages/repository/stoop_world_share.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';
import 'package:front_porch_ai/ui/widgets/widgets.dart';

/// The Stoop upload wizard's Pick step, extracted from the (over-cap)
/// stoop_upload_page god file and made folder-aware in the same move: the
/// character/group grids follow the home grid's folder hierarchy via the
/// shared [buildFolderPickView] rules (browse = current level + navigable
/// folder tiles with candidate counts; search = flat across every folder),
/// rendered in The Stoop's own visual language. Places aren't foldered, so
/// the Places section shows only at the top level (or while searching).
class StoopPickStep extends StatefulWidget {
  const StoopPickStep({
    super.key,
    required this.selectedCard,
    required this.selectedGroup,
    required this.selectedWorldId,
    required this.onSelectCard,
    required this.onSelectGroup,
    required this.onSelectWorld,
  });

  final CharacterCard? selectedCard;
  final GroupChat? selectedGroup;
  final String? selectedWorldId;
  final void Function(CharacterCard card) onSelectCard;
  final void Function(GroupChat group) onSelectGroup;
  final void Function(World world) onSelectWorld;

  @override
  State<StoopPickStep> createState() => _StoopPickStepState();
}

class _StoopPickStepState extends State<StoopPickStep> {
  final _search = TextEditingController();
  String _query = '';
  String? _folderId; // null = top level
  final List<String> _folderStack = [];

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final folderService = context.watch<FolderService>();
    // Only cards with an avatar image (and any group) can be shared.
    final allCards = context
        .read<CharacterRepository>()
        .characters
        .where((c) => c.imagePath != null && c.imagePath!.isNotEmpty)
        .toList();
    final allGroups = context.read<GroupChatRepository>().groups;
    final hasWorlds = context.read<WorldRepository>().placeWorlds.isNotEmpty;
    if (allCards.isEmpty && allGroups.isEmpty && !hasWorlds) {
      return _centeredHint(
        Icons.person_off_outlined,
        'Nothing to share yet',
        'Characters need an avatar image, and groups need members, before they '
            'can be shared.',
      );
    }

    final view = buildFolderPickView(
      folderService: folderService,
      characters: allCards,
      groups: allGroups,
      folderId: _folderId,
      query: _query,
    );
    final browsing = _query.isEmpty;
    const grid = SliverGridDelegateWithMaxCrossAxisExtent(
      maxCrossAxisExtent: 150,
      childAspectRatio: 0.78,
      crossAxisSpacing: 12,
      mainAxisSpacing: 12,
    );
    return ListView(
      key: const ValueKey('pick'),
      padding: const EdgeInsets.all(16),
      children: [
        _searchField(),
        if (browsing && _folderId != null) _breadcrumb(folderService),
        const SizedBox(height: 14),
        if (!browsing && view.characters.isEmpty && view.groups.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 40),
            child: Center(
              child: Text(
                'No characters or groups match “${_search.text.trim()}”.',
                textAlign: TextAlign.center,
                style: TextStyle(color: stoopMute(context)),
              ),
            ),
          ),
        // Folders first (navigation), then groups — the marquee thing to
        // share — then characters, then places.
        if (view.folders.isNotEmpty) ...[
          _label('Folders'),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: grid,
            itemCount: view.folders.length,
            itemBuilder: (context, i) => _folderTile(
              view.folders[i],
              view.folderCounts[view.folders[i].id] ?? 0,
            ),
          ),
          const SizedBox(height: 16),
        ],
        if (view.groups.isNotEmpty) ...[
          _label('Groups'),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: grid,
            itemCount: view.groups.length,
            itemBuilder: (context, i) => _groupTile(view.groups[i]),
          ),
        ],
        if (view.characters.isNotEmpty) ...[
          if (view.groups.isNotEmpty) const SizedBox(height: 16),
          _label('Characters'),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: grid,
            itemCount: view.characters.length,
            itemBuilder: (context, i) => _cardTile(view.characters[i]),
          ),
        ],
        // Places aren't foldered — the section belongs to the top level (and
        // stays reachable through search, which escapes any folder).
        if (_folderId == null || !browsing) ...[
          if (view.characters.isNotEmpty || view.groups.isNotEmpty)
            const SizedBox(height: 16),
          StoopWorldsPickSection(
            query: _query,
            selectedWorldId: widget.selectedWorldId,
            onSelect: widget.onSelectWorld,
          ),
        ],
      ],
    );
  }

  // Name filter — mirrors the browse view's search field.
  Widget _searchField() {
    return TextField(
      controller: _search,
      onChanged: (v) => setState(() => _query = v.trim().toLowerCase()),
      style: TextStyle(color: stoopCream(context)),
      decoration: stoopInput(
        context,
        'Search your characters and groups',
        prefixIcon: Icon(Icons.search, color: stoopMute(context)),
        suffixIcon: _query.isEmpty
            ? null
            : IconButton(
                icon: Icon(Icons.close, color: stoopMute(context)),
                onPressed: () {
                  _search.clear();
                  setState(() => _query = '');
                },
              ),
      ),
    );
  }

  Widget _breadcrumb(FolderService folderService) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        children: [
          IconButton(
            icon: Icon(Icons.arrow_back, color: stoopCream(context)),
            iconSize: 18,
            visualDensity: VisualDensity.compact,
            tooltip: 'Back',
            onPressed: () => setState(() {
              _folderId = _folderStack.isNotEmpty
                  ? _folderStack.removeLast()
                  : null;
            }),
          ),
          const SizedBox(width: 4),
          const Icon(Icons.folder, size: 16, color: AppColors.stoopAmberDeep),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              folderService.getFolderPath(_folderId!),
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: stoopCream(context),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _folderTile(CharacterFolder folder, int count) {
    return GestureDetector(
      onTap: () => setState(() {
        if (_folderId != null) _folderStack.add(_folderId!);
        _folderId = folder.id;
      }),
      child: Container(
        decoration: BoxDecoration(
          gradient: stoopCardGradient(context),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: stoopBorder(context)),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Expanded(
              child: Center(
                child: Icon(
                  Icons.folder_rounded,
                  size: 44,
                  color: AppColors.stoopAmberDeep,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              child: Text(
                '${folder.name} ($count)',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: stoopCream(context),
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _groupTile(GroupChat group) {
    final selected = widget.selectedGroup?.id == group.id;
    final accent = AppColors.stoopAmberDeep;
    return GestureDetector(
      onTap: () => widget.onSelectGroup(group),
      child: Container(
        decoration: BoxDecoration(
          gradient: stoopCardGradient(context),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? accent : stoopBorder(context),
            width: selected ? 2 : 1,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              // Groups are teal on The Stoop (hub badge color) — no purple.
              child: ColoredBox(
                color: stoopTealSoft(context),
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: StoopGroupMontage(group: group),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              child: Text(
                group.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: stoopCream(context),
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _cardTile(CharacterCard card) {
    final selected =
        widget.selectedCard?.dbId == card.dbId && widget.selectedCard != null;
    final accent = AppColors.stoopAmberDeep;
    return GestureDetector(
      onTap: () => widget.onSelectCard(card),
      child: Container(
        decoration: BoxDecoration(
          gradient: stoopCardGradient(context),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? accent : stoopBorder(context),
            width: selected ? 2 : 1,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Image.file(File(card.imagePath!), fit: BoxFit.cover),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              child: Text(
                card.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: stoopCream(context),
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _label(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Text(
      text,
      style: TextStyle(
        color: stoopCream2(context),
        fontSize: 13,
        fontWeight: FontWeight.w500,
      ),
    ),
  );

  Widget _centeredHint(IconData icon, String title, String body) {
    return Center(
      key: const ValueKey('hint'),
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: stoopMute(context)),
            const SizedBox(height: 14),
            Text(
              title,
              style: TextStyle(
                color: stoopCream(context),
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              body,
              textAlign: TextAlign.center,
              style: TextStyle(color: stoopMute(context)),
            ),
          ],
        ),
      ),
    );
  }
}

/// A folder-style montage of a group's member avatars, sized to fill its
/// slot. Shared by the Pick step's group tile and the upload wizard's
/// review-step preview. Falls back to a groups glyph while members load or
/// if none have an avatar.
///
/// Stateful ONLY to hold the avatar future (same reasoning as GroupGridCard):
/// building it inline issued a fresh SQLite query per tile on EVERY rebuild —
/// in the Pick grid that's N queries per search keystroke.
class StoopGroupMontage extends StatefulWidget {
  const StoopGroupMontage({super.key, required this.group});

  final GroupChat group;

  @override
  State<StoopGroupMontage> createState() => _StoopGroupMontageState();
}

class _StoopGroupMontageState extends State<StoopGroupMontage> {
  late Future<List<File>> _files;

  @override
  void initState() {
    super.initState();
    _files = context.read<GroupChatRepository>().getMemberAvatarFiles(
      widget.group.id,
    );
  }

  @override
  void didUpdateWidget(StoopGroupMontage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.group.id != oldWidget.group.id) {
      _files = context.read<GroupChatRepository>().getMemberAvatarFiles(
        widget.group.id,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<File>>(
      future: _files,
      builder: (context, snap) {
        final files = snap.data ?? const <File>[];
        if (files.isEmpty) {
          return const Center(
            child: Icon(
              Icons.groups_rounded,
              size: 44,
              color: AppColors.stoopTeal,
            ),
          );
        }
        return LayoutBuilder(
          builder: (context, c) {
            final side = c.maxWidth < c.maxHeight ? c.maxWidth : c.maxHeight;
            return Center(
              child: GroupAvatarMontage(
                images: files.take(4).toList(),
                side: side,
              ),
            );
          },
        );
      },
    );
  }
}
