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
    return HomeModeToggle(
      showStories: _showStories,
      onShowChats: () => applyState(() => _showStories = false),
      onShowStories: () => applyState(() => _showStories = true),
    );
  }

  /// Toggle row that shrinks instead of overflowing when the window is
  /// squeezed. Used on the empty-library and Stories chrome.
  Widget _modeToggleBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
      child: Row(
        children: [
          Flexible(
            child: Align(
              alignment: Alignment.centerLeft,
              child: _buildModeToggle(),
            ),
          ),
        ],
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

  // ─── CharacterCardGrid Callback Handlers ────────────────────────

  /// Push ChatPage immediately and drain [load] after pop. The session
  /// overlay covers hydrate — awaiting load first is the home-grid freeze.
  /// A failed load pops the ghost ChatPage and snacks the error.
  Future<void> _pushChatWhile(Future<void> load) async {
    if (!mounted) {
      await load;
      return;
    }
    final nav = Navigator.of(context);
    final route = nav.push(MaterialPageRoute(builder: (_) => const ChatPage()));
    try {
      await load;
    } catch (e, st) {
      debugPrint('[Home] open chat failed: $e\n$st');
      if (mounted && nav.canPop()) {
        nav.pop();
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Could not open chat: $e')));
      }
      return;
    }
    await route;
    if (mounted) _refreshLastActivityCache();
  }

  Future<void> _handleTapCharacter(CharacterCard character) async {
    // Use State.mounted — NOT context.mounted. Reading State.context after
    // unmount throws before .mounted is ever evaluated (exit chat → reenter
    // multi-tap race, maintainer 2026-08-11).
    if (_openingChat || !mounted) return;
    _openingChat = true;
    try {
      final chatService = Provider.of<ChatService>(context, listen: false);
      // One session (the common case): skip the full session list + the
      // getAllCharacters scan inside getSessionsForId. The picker still
      // uses the basename id when there are several chats.
      if (!await chatService.hasMultipleSavedSessions(character)) {
        await _pushChatWhile(chatService.setActiveCharacter(character));
        return;
      }
      // getSessionsForId resolves 1:1 ids by imagePath basename (stableGroupId)
      // — the dbId UUID silently returns [] and kills the session picker
      // (documented identity gotcha; same warning at enhance_wizard_page.dart).
      final charId = _getCharacterIdFromCard(character);
      final sessions = await chatService.getSessionsForId(charId);

      if (!mounted) return;

      if (sessions.length > 1) {
        final selectedId = await showSessionPickerDialog(
          context,
          sessions,
          character.name,
        );
        if (selectedId == null || !mounted) return;
        chatService.beginSessionLoad();
        await _pushChatWhile(() async {
          try {
            await chatService.setActiveCharacter(character);
            if (selectedId != '__new__') {
              await chatService.loadSession(selectedId);
            } else {
              await chatService.startNewChat();
            }
          } finally {
            chatService.endSessionLoad();
          }
        }());
      } else {
        await _pushChatWhile(chatService.setActiveCharacter(character));
      }
    } finally {
      _openingChat = false;
    }
  }

  Future<void> _handleTapGroup(GroupChat group) async {
    if (_openingChat || !mounted) return;
    _openingChat = true;
    try {
      final chatService = Provider.of<ChatService>(context, listen: false);
      final groupRepo = Provider.of<GroupChatRepository>(
        context,
        listen: false,
      );
      final groupId = 'group_${group.id}';
      final sessions = await chatService.getSessionsForId(groupId);

      if (!mounted) return;

      if (sessions.length > 1) {
        final selectedId = await showSessionPickerDialog(
          context,
          sessions,
          group.name,
        );
        if (selectedId == null || !mounted) return;
        chatService.beginSessionLoad();
        await _pushChatWhile(() async {
          try {
            await chatService.setActiveGroup(group, groupRepo: groupRepo);
            if (selectedId != '__new__') {
              await chatService.loadSession(selectedId);
            } else {
              await chatService.startNewChat();
            }
          } finally {
            chatService.endSessionLoad();
          }
        }());
      } else {
        await _pushChatWhile(
          chatService.setActiveGroup(group, groupRepo: groupRepo),
        );
      }
    } finally {
      _openingChat = false;
    }
  }

  /// "Start New Chat" from either card's context menu: ask which persona
  /// (step 2 — never assumed), then open a fresh session and enter it.
  /// Cancelling the picker starts nothing. One handler for characters and
  /// group casts; [ChatService.startFreshChatWith] owns the ordering.
  Future<void> _startNewChatWith({
    CharacterCard? character,
    GroupChat? group,
  }) async {
    if (_openingChat || !mounted) return;
    _openingChat = true;
    try {
      final subject = character?.name ?? group?.name ?? '';
      final personaId = await showPersonaPickerDialog(
        context,
        subject: subject,
      );
      if (personaId == null || !mounted) return;

      final chatService = Provider.of<ChatService>(context, listen: false);
      await _pushChatWhile(
        chatService.startFreshChatWith(
          character: character,
          group: group,
          groupRepo: group == null
              ? null
              : Provider.of<GroupChatRepository>(context, listen: false),
          personaId: personaId,
        ),
      );
    } finally {
      _openingChat = false;
    }
  }

  void _handleContextMenuAction(String action, CharacterCard character) {
    switch (action) {
      case 'new_chat':
        _startNewChatWith(character: character);
        break;
      case 'edit':
        _editCharacter(context, character);
        break;
      case 'ai_enhance':
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => EnhanceWizardPage(character: character),
          ),
        );
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
      case 'move_folder':
        final moveService = Provider.of<FolderService>(context, listen: false);
        _showMoveToFolderDialog(
          context,
          moveService,
          title: 'Move "${character.name}" to folder',
          onMove: (folderId) async {
            if (character.imagePath == null) return;
            if (folderId == null) {
              await moveService.removeFromFolder(null, character.imagePath!);
            } else {
              await moveService.addToFolder(folderId, character.imagePath!);
            }
          },
        );
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
      case 'new_chat':
        _startNewChatWith(group: group);
        break;
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
      case 'move_folder':
        final folderService = Provider.of<FolderService>(
          context,
          listen: false,
        );
        _showMoveToFolderDialog(
          context,
          folderService,
          title: 'Move "${group.name}" to folder',
          onMove: (folderId) => folderId == null
              ? folderService.removeGroupFromFolder(null, group.id)
              : folderService.addGroupToFolder(folderId, group.id),
        );
        break;
      case 'remove_folder':
        if (_activeFolderId != null) {
          Provider.of<FolderService>(
            context,
            listen: false,
          ).removeGroupFromFolder(_activeFolderId!, group.id);
        }
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

  /// One drop handler for both draggable kinds: characters are keyed by image
  /// filename, group casts by their group id (see FolderService).
  Future<void> _handleAcceptFolderDrop(
    Object item,
    CharacterFolder folder,
  ) async {
    final folderService = Provider.of<FolderService>(context, listen: false);
    if (item is CharacterCard) {
      if (item.imagePath != null) {
        await folderService.addToFolder(folder.id, item.imagePath!);
      }
    } else if (item is GroupChat) {
      await folderService.addGroupToFolder(folder.id, item.id);
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
    applyState(() => _activeFolderId = folder.id);
  }

  /// Up one level. Subfolder cards only render inside their parent, so the
  /// parent chain IS the navigation history — no stack needed (and the
  /// breadcrumb trail can jump to any ancestor directly).
  void _handleFolderNavigateBack() {
    final folderService = Provider.of<FolderService>(context, listen: false);
    final current = folderService.folders
        .where((f) => f.id == _activeFolderId)
        .firstOrNull;
    applyState(() => _activeFolderId = current?.parentId);
  }

  void _handleMoveToFolder(Set<String> selectedIds) {
    final repo = Provider.of<CharacterRepository>(context, listen: false);
    final folderService = Provider.of<FolderService>(context, listen: false);
    final chars = _selectedCharacterIds.length;
    final groups = _selectedGroupIds.length;
    // "N characters" / "N groups" when the selection is homogeneous,
    // "N items" for a mixed grab.
    final title = groups == 0
        ? 'Move $chars character${chars == 1 ? '' : 's'} to folder'
        : chars == 0
        ? 'Move $groups group${groups == 1 ? '' : 's'} to folder'
        : 'Move ${chars + groups} items to folder';
    _showMoveToFolderDialog(
      context,
      folderService,
      title: title,
      onMove: (folderId) =>
          _moveSelectedToFolder(context, folderId, repo, folderService),
    );
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
