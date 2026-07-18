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

/// Build helpers: the Characters/Stories mode toggle and the bottom status bar.
///
/// Split out of the _HomePageState god file as a private extension
/// (part of the same library, so it keeps full access to page state).
extension _HomePageChrome on _HomePageState {

  Widget _buildModeToggle() {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerOf(context),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.borderOf(context)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _modeButton(
            'Chats',
            Icons.chat_bubble_outline,
            !_showStories,
            () => applyState(() => _showStories = false),
          ),
          _modeButton(
            'Porch Stories',
            Icons.auto_stories,
            _showStories,
            () => applyState(() => _showStories = true),
          ),
        ],
      ),
    );
  }

  Widget _modeButton(
    String label,
    IconData icon,
    bool isActive,
    VoidCallback onTap,
  ) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isActive
              ? AppColors.porchAmberOf(context).withValues(alpha: 0.15)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          border: isActive
              ? Border.all(
                  color: AppColors.porchAmberOf(
                    context,
                  ).withValues(alpha: 0.45),
                )
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 18,
              color: isActive
                  ? AppColors.porchAmberOf(context)
                  : AppColors.iconSecondary(context),
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                color: isActive
                    ? AppColors.textPrimary(context)
                    : AppColors.textSecondary(context),
                fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
                fontSize: 14,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _wrapWithStatusBar(BuildContext context, Widget content) {
    String status = '';
    try {
      final kobold = Provider.of<KoboldService>(context, listen: false);
      status = kobold.modelLoadingStatus;
    } catch (_) {}

    if (status.isEmpty) return content;

    return Column(
      children: [
        Expanded(child: content),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
          decoration: BoxDecoration(
            color: AppColors.surfaceContainerOf(context),
            border: Border(top: BorderSide(color: AppColors.borderOf(context))),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                status,
                style: TextStyle(
                  color: AppColors.textSecondary(context),
                  fontSize: 13,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 6),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  minHeight: 4,
                  backgroundColor: AppColors.surfaceContainerOf(context),
                  valueColor: AlwaysStoppedAnimation<Color>(
                    AppColors.porchHoneyOf(context),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// Shows a dialog letting the user choose which saved session to resume.
  /// Returns the session ID, '__new__' for a new chat, or null if cancelled.

  // ─── CharacterCardGrid Callback Handlers ────────────────────────

  Future<void> _handleTapCharacter(CharacterCard character) async {
    final chatService = Provider.of<ChatService>(context, listen: false);
    final charId = character.dbId ?? _getCharacterIdFromCard(character);
    final sessions = await chatService.getSessionsForId(charId);

    if (!context.mounted) return;

    if (sessions.length > 1) {
      final selectedId = await showSessionPickerDialog(
        context,
        sessions,
        character.name,
      );
      if (selectedId == null || !context.mounted) return;
      await chatService.setActiveCharacter(character);
      if (selectedId != '__new__') {
        await chatService.loadSession(selectedId);
      }
      if (selectedId == '__new__') {
        await chatService.startNewChat();
      }
    } else {
      await chatService.setActiveCharacter(character);
    }
    if (context.mounted) {
      await Navigator.of(
        context,
      ).push(MaterialPageRoute(builder: (_) => const ChatPage()));
      _refreshLastActivityCache();
    }
  }

  Future<void> _handleTapGroup(GroupChat group) async {
    final chatService = Provider.of<ChatService>(context, listen: false);
    final groupRepo = Provider.of<GroupChatRepository>(context, listen: false);
    final groupId = 'group_${group.id}';
    final sessions = await chatService.getSessionsForId(groupId);

    if (!context.mounted) return;

    if (sessions.length > 1) {
      final selectedId = await showSessionPickerDialog(
        context,
        sessions,
        group.name,
      );
      if (selectedId == null || !context.mounted) return;
      await chatService.setActiveGroup(group, groupRepo: groupRepo);
      if (selectedId != '__new__') {
        await chatService.loadSession(selectedId);
      }
      if (selectedId == '__new__') {
        await chatService.startNewChat();
      }
    } else {
      await chatService.setActiveGroup(group, groupRepo: groupRepo);
    }
    if (context.mounted) {
      await Navigator.of(
        context,
      ).push(MaterialPageRoute(builder: (_) => const ChatPage()));
      _refreshLastActivityCache();
    }
  }

  void _handleContextMenuAction(String action, CharacterCard character) {
    switch (action) {
      case 'edit':
        _editCharacter(context, character);
        break;
      case 'avatar_gallery':
        // Replace-portrait / star both call repository.updateCharacter, which
        // notifyListeners() → the home grid rebuilds on its own (same as edit).
        showAvatarGallery(
          context: context,
          character: character,
          repository: Provider.of<CharacterRepository>(context, listen: false),
          storage: Provider.of<StorageService>(context, listen: false),
          mode: WardrobeMode.library,
        );
        break;
      case 'duplicate':
        _duplicateCharacter(context, character);
        break;
      case 'export':
        _exportCharacter(context, character);
        break;
      case 'export_json':
        _exportCharacterJson(context, character);
        break;
      case 'remove_folder':
        final folderService = Provider.of<FolderService>(
          context,
          listen: false,
        );
        if (_activeFolderId != null && character.imagePath != null) {
          folderService.removeFromFolder(
            _activeFolderId!,
            character.imagePath!,
          );
        }
        break;
      case 'delete':
        _confirmDeleteCharacter(context, character);
        break;
    }
  }

  void _handleGroupContextMenuAction(String action, GroupChat group) {
    switch (action) {
      case 'edit':
        _editGroup(group);
        break;
      case 'duplicate':
        _duplicateGroup(group);
        break;
      case 'export':
        _exportGroup(group);
        break;
      case 'extract':
        _extractCharactersFromGroup(group);
        break;
      case 'delete':
        _confirmDeleteGroup(context, group);
        break;
    }
  }

  Future<void> _editGroup(GroupChat group) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => EditGroupPage(group: group)),
    );
    // GroupChatRepository.save() already calls notifyListeners(),
    // so the home grid rebuilds automatically after edit.
  }

  void _duplicateGroup(GroupChat group) {
    // Placeholder — real implementation will copy the GroupChat definition (new id, "Copy of" name, same seeds/ lore / worlds / prompts).
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Duplicate Group not yet implemented: ${group.name}'),
        ),
      );
    }
  }

  void _handleImport(String source) {
    switch (source) {
      case 'cards':
        _importCharacter(context);
        break;
      case 'folder':
        _folderImportCharacters(context);
        break;
      case 'byaf':
        _importByaf(context);
        break;
    }
  }


  Future<void> _handleAcceptFolderDrop(
    CharacterCard character,
    CharacterFolder folder,
  ) async {
    final folderService = Provider.of<FolderService>(context, listen: false);
    if (character.imagePath != null) {
      await folderService.addToFolder(folder.id, character.imagePath!);
    }
  }

  void _handleFolderDialogAction(
    FolderDialogAction action, {
    CharacterFolder? folder,
    String? parentId,
  }) {
    final folderService = Provider.of<FolderService>(context, listen: false);
    switch (action) {
      case FolderDialogAction.create:
        _createFolder(context, folderService, parentId: parentId);
        break;
      case FolderDialogAction.rename:
        if (folder != null) _renameFolder(context, folder, folderService);
        break;
      case FolderDialogAction.delete:
        if (folder != null) _deleteFolder(context, folder, folderService);
        break;
    }
  }

  void _handleFolderTap(CharacterFolder folder) {
    applyState(() {
      if (_activeFolderId != null) {
        _folderStack.add(_activeFolderId!);
      }
      _activeFolderId = folder.id;
    });
  }

  void _handleFolderNavigateBack() {
    applyState(() {
      if (_folderStack.isNotEmpty) {
        _activeFolderId = _folderStack.removeLast();
      } else {
        _activeFolderId = null;
      }
    });
  }

  void _handleMoveToFolder(Set<String> selectedIds) {
    final repo = Provider.of<CharacterRepository>(context, listen: false);
    final folderService = Provider.of<FolderService>(context, listen: false);
    _showMoveToFolderDialog(context, repo, folderService);
  }

  void _handleSortChanged(String mode) {
    applyState(() => _sortMode = mode);
    Provider.of<StorageService>(context, listen: false).setSortMode(mode);
  }

  void _handleGridScaleChanged(double scale) {
    applyState(() => _gridScale = scale);
  }

  void _handleGridScaleChangeEnd(double scale) {
    Provider.of<StorageService>(context, listen: false).setGridScale(scale);
  }

  void _handleSearchScopeChanged(SearchScope scope) {
    applyState(() => _searchScope = scope);
  }

  void _handleSearchQueryChanged(String query) {
    applyState(() => _searchQuery = query);
  }

  void _handleDeleteGroup(GroupChat group) {
    _confirmDeleteGroup(context, group);
  }
}
