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

import 'package:front_porch_ai/database/database.dart';
import 'dart:io';
import 'package:path/path.dart' as path;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:front_porch_ai/providers/app_state.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:front_porch_ai/services/character_repository.dart';
import 'package:front_porch_ai/services/world_repository.dart';
import 'package:front_porch_ai/services/folder_service.dart';
import 'package:front_porch_ai/services/group_chat_repository.dart';
import 'package:front_porch_ai/services/cloud_sync_service.dart';
import 'package:front_porch_ai/services/kobold_service.dart';
import 'package:front_porch_ai/services/byaf_service.dart';
import 'package:front_porch_ai/ui/dialogs/byaf_import_dialog.dart';
import 'package:front_porch_ai/services/v2_card_service.dart';
import 'package:front_porch_ai/models/group_chat.dart';
import 'package:front_porch_ai/ui/pages/chat_page.dart';
import 'package:front_porch_ai/services/chat_service.dart';
import 'package:front_porch_ai/services/llm_provider.dart';
import 'package:front_porch_ai/services/llm_service.dart';
import 'package:front_porch_ai/ui/pages/edit_character_page.dart';
import 'package:front_porch_ai/ui/pages/character_creator_page.dart';
import 'package:front_porch_ai/ui/dialogs/tag_dialog.dart';
import 'package:front_porch_ai/models/character_card.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:front_porch_ai/services/storage_service.dart';
import 'package:front_porch_ai/services/tts_service.dart';
import 'package:front_porch_ai/ui/pages/story_home_view.dart';
import 'package:front_porch_ai/ui/widgets/character_card_grid.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  String _searchQuery = '';
  String? _activeFolderId; // null = top level view
  List<String> _folderStack = []; // navigation breadcrumb for subfolder back
  SearchScope _searchScope = SearchScope.currentFolder;
  final _searchController = TextEditingController();

  // Multi-select for group creation
  bool _isSelecting = false;
  // Multi-select for folder organization
  bool _isOrganizing = false;
  final Set<String> _selectedCharacterIds = {}; // imagePath-based IDs

  // Sorting
  String _sortMode = 'name'; // 'name', 'recent', 'importDate', 'messages'
  final Map<String, DateTime> _lastActivityCache = {};
  final Map<String, int> _messageCountCache = {};

  // Grid scale
  double _gridScale = 300.0;

  // Porch Stories mode toggle
  bool _showStories = false;

  // Scroll controller for the character grid (visible scrollbar)
  final ScrollController _gridScrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    final storage = Provider.of<StorageService>(context, listen: false);
    _sortMode = storage.sortMode;
    _gridScale = storage.gridScale;
    // StorageService._init() is async — settings may not be loaded yet.
    // Wait for init to complete so persisted values are reflected.
    storage.initialized.then((_) {
      if (!mounted) return;
      setState(() {
        _sortMode = storage.sortMode;
        _gridScale = storage.gridScale;
      });
    });
    Future.microtask(() => _refreshLastActivityCache());
  }

  /// Resolve a character [imagePath] (basename or full path) to a [File].
  File _resolveCharImage(String imagePath) {
    final storage = Provider.of<StorageService>(context, listen: false);
    return storage.resolveCharacterImage(imagePath);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Listen for model-ready events from KoboldService
    try {
      final kobold = Provider.of<KoboldService>(context, listen: false);
      kobold.removeListener(_onKoboldUpdate);
      kobold.addListener(_onKoboldUpdate);
    } catch (_) {
      // KoboldService might not be in the provider tree
    }
    // Listen for CharacterRepository changes to refresh cache after characters load
    try {
      final charRepo = Provider.of<CharacterRepository>(context, listen: false);
      charRepo.removeListener(_onCharactersChanged);
      charRepo.addListener(_onCharactersChanged);
    } catch (_) {}
  }

  void _onCharactersChanged() {
    if (!mounted) return;
    _refreshLastActivityCache();
  }

  void _onKoboldUpdate() {
    if (!mounted) return;
    try {
      final kobold = Provider.of<KoboldService>(context, listen: false);
      if (kobold.consumeModelReady()) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                Icon(Icons.check_circle, color: Colors.greenAccent, size: 20),
                const SizedBox(width: 8),
                const Text('Model loaded and ready!'),
              ],
            ),
            backgroundColor: AppColors.surfaceContainerOf(context),
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 3),
          ),
        );
      }
      setState(() {}); // Rebuild to update status bar
    } catch (_) {}
  }

  /// Query the DB to build caches for last activity time and message count per character.
  Future<void> _refreshLastActivityCache() async {
    try {
      final db = await AppDatabase.instance();
      final charRepo = Provider.of<CharacterRepository>(context, listen: false);

      // Get counts and activity from DB
      final msgCounts = await db.getMessageCountsPerCharacter();
      final lastActivity = await db.getLastActivityPerCharacter();

      // Map from character DB id (UUID) → message count
      final newMsgCount = <String, int>{};
      for (final card in charRepo.characters) {
        if (card.dbId != null && msgCounts.containsKey(card.dbId)) {
          newMsgCount[card.dbId!] = msgCounts[card.dbId!]!;
        }
      }

      // Map from character DB id (UUID) → last activity time
      final newCache = <String, DateTime>{};
      for (final card in charRepo.characters) {
        if (card.dbId != null && lastActivity.containsKey(card.dbId)) {
          newCache[card.dbId!] = lastActivity[card.dbId!]!;
        }
      }

      if (mounted) {
        setState(() {
          _lastActivityCache
            ..clear()
            ..addAll(newCache);
          _messageCountCache
            ..clear()
            ..addAll(newMsgCount);
        });
      }
    } catch (e) {
      debugPrint('Error refreshing activity cache: $e');
      if (mounted) setState(() {});
    }
  }

  String _getCharacterIdFromCard(CharacterCard card) {
    if (card.imagePath != null) {
      return path.basenameWithoutExtension(card.imagePath!);
    }
    return card.name.replaceAll(RegExp(r'[^\w\s]'), '').replaceAll(' ', '_');
  }

  void _toggleSelectMode() {
    setState(() {
      _isSelecting = !_isSelecting;
      _isOrganizing = false;
      if (!_isSelecting) _selectedCharacterIds.clear();
    });
  }

  void _toggleOrganizeMode() {
    setState(() {
      _isOrganizing = !_isOrganizing;
      _isSelecting = false;
      if (!_isOrganizing) _selectedCharacterIds.clear();
    });
  }

  void _toggleSelect(CharacterCard character) {
    final id = character.imagePath != null
        ? path.basenameWithoutExtension(character.imagePath!)
        : character.name.replaceAll(RegExp(r'[^\w\s]'), '').replaceAll(' ', '_');
    setState(() {
      if (_selectedCharacterIds.contains(id)) {
        _selectedCharacterIds.remove(id);
        if (_selectedCharacterIds.isEmpty) {
          _isSelecting = false;
          _isOrganizing = false;
        }
      } else {
        _selectedCharacterIds.add(id);
      }
    });
  }

  void _cancelSelection() {
    setState(() {
      _isSelecting = false;
      _isOrganizing = false;
      _selectedCharacterIds.clear();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _gridScrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer3<CharacterRepository, FolderService, GroupChatRepository>(
      builder: (context, repo, folderService, groupRepo, child) {
        if (repo.isLoading) {
          return const Center(child: CircularProgressIndicator());
        }

        if (repo.characters.isEmpty && groupRepo.groups.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  'Get started by creating a new character!',
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(
                    color: Theme.of(context)
                        .textTheme
                        .titleLarge
                        ?.color
                        ?.withValues(alpha: 0.7),
                  ),
                ),
                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    ElevatedButton.icon(
                      onPressed: () => Provider.of<AppState>(
                        context,
                        listen: false,
                      ).setIndex(1),
                      icon: const Icon(Icons.add_circle_outline),
                      label: const Text('Create New'),
                      style: _buttonStyle(),
                    ),
                    const SizedBox(width: 16),
                    ElevatedButton.icon(
                      onPressed: () => _importCharacter(context),
                      icon: const Icon(Icons.download),
                      label: const Text('Import Card'),
                      style: _buttonStyle(),
                    ),
                    const SizedBox(width: 16),
                    ElevatedButton.icon(
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const CharacterCreatorPage(),
                        ),
                      ),
                      icon: const Icon(Icons.auto_awesome),
                      label: const Text('AI Create'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.amber.shade800,
                        foregroundColor: Colors.white,
                      ),
                    ),
                    const SizedBox(width: 16),
                    ElevatedButton.icon(
                      onPressed: () => _folderImportCharacters(context),
                      icon: const Icon(Icons.library_add),
                      label: const Text('Bulk Import'),
                      style: _buttonStyle(),
                    ),
                    const SizedBox(width: 16),
                    ElevatedButton.icon(
                      onPressed: () => _importByaf(context),
                      icon: const Icon(Icons.archive_outlined),
                      label: const Text('Import BYAF'),
                      style: _buttonStyle(),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    TextButton.icon(
                      onPressed: () => _openBrowser(context),
                      icon: const Icon(Icons.public, color: Colors.blueAccent),
                      label: const Text(
                        'AI Character Cards',
                        style: TextStyle(color: Colors.blueAccent),
                      ),
                    ),
                    const SizedBox(width: 16),
                    TextButton.icon(
                      onPressed: () => _showChubWarning(context),
                      icon: const Icon(
                        Icons.warning_amber_rounded,
                        color: Colors.redAccent,
                      ),
                      label: const Text(
                        'Chub.ai',
                        style: TextStyle(color: Colors.redAccent),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          );
        }

        // If Porch Stories mode is active, show the stories view
        if (_showStories) {
          return _wrapWithStatusBar(
            context,
            Column(
              children: [
                // Radio toggle
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24.0,
                    vertical: 16.0,
                  ),
                  child: Row(children: [_buildModeToggle(), const Spacer()]),
                ),
                const Expanded(child: StoryHomeView()),
              ],
            ),
          );
        }

        return _wrapWithStatusBar(
          context,
          CharacterCardGrid(
            searchQuery: _searchQuery,
            searchScope: _searchScope,
            activeFolderId: _activeFolderId,
            sortMode: _sortMode,
            lastActivityCache: _lastActivityCache,
            messageCountCache: _messageCountCache,
            gridScale: _gridScale,
            isSelecting: _isSelecting,
            isOrganizing: _isOrganizing,
            selectedCharacterIds: _selectedCharacterIds,
            searchController: _searchController,
            gridScrollController: _gridScrollController,
            repo: repo,
            folderService: folderService,
            groupRepo: groupRepo,
            modeToggle: _buildModeToggle(),
            onTapCharacter: _handleTapCharacter,
            onTapGroup: _handleTapGroup,
            onToggleSelect: _toggleSelect,
            onToggleSelectMode: _toggleSelectMode,
            onToggleOrganizeMode: _toggleOrganizeMode,
            onContextMenuAction: _handleContextMenuAction,
            onImport: _handleImport,
            onOpenBrowser: _handleOpenBrowser,
            onAcceptFolderDrop: _handleAcceptFolderDrop,
            onFolderDialogAction: _handleFolderDialogAction,
            onFolderTap: _handleFolderTap,
            onFolderNavigateBack: _handleFolderNavigateBack,
            onCancelSelection: _cancelSelection,
            onCreateGroup: _handleCreateGroup,
            onMoveToFolder: _handleMoveToFolder,
            onSortChanged: _handleSortChanged,
            onGridScaleChanged: _handleGridScaleChanged,
            onGridScaleChangeEnd: _handleGridScaleChangeEnd,
            onSearchScopeChanged: _handleSearchScopeChanged,
            onSearchQueryChanged: _handleSearchQueryChanged,
            onResolveCharImage: _resolveCharImage,
            onDeleteGroup: _handleDeleteGroup,
            onAfterNavigateBack: _refreshLastActivityCache,
          ),
        );
      },
    );
  }

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
            () => setState(() => _showStories = false),
          ),
          _modeButton(
            'Porch Stories',
            Icons.auto_stories,
            _showStories,
            () => setState(() => _showStories = true),
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
              ? AppColors.resolve(
                  context,
                  Colors.amber.shade800.withValues(alpha: 0.25),
                  Colors.amber.withValues(alpha: 0.15),
                )
              : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          border: isActive
              ? Border.all(
                  color: AppColors.resolve(
                    context,
                    Colors.amber.shade700.withValues(alpha: 0.5),
                    Colors.amber.shade700.withValues(alpha: 0.4),
                  ),
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
                  ? AppColors.resolve(
                      context,
                      Colors.amber.shade400,
                      Colors.amber.shade800,
                    )
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
                style: TextStyle(color: AppColors.textSecondary(context), fontSize: 13),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 6),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  minHeight: 4,
                  backgroundColor: AppColors.resolve(
                    context,
                    const Color(0xFF333333),
                    AppColors.surfaceContainerLight,
                  ),
                  valueColor: const AlwaysStoppedAnimation<Color>(Colors.greenAccent),
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
  Future<String?> _showSessionPickerDialog(
    BuildContext context,
    List<Map<String, dynamic>> sessions,
    String characterName,
  ) {
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surfaceOf(context),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: Colors.blueAccent, width: 0.5),
        ),
        title: Row(
          children: [
            const Icon(
              Icons.chat_bubble_outline,
              color: Colors.blueAccent,
              size: 22,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Continue a chat with $characterName?',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary(context),
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        content: SizedBox(
          width: 420,
          height: 350,
          child: Column(
            children: [
              // New chat button
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () => Navigator.of(ctx).pop('__new__'),
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Start New Chat'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.greenAccent,
                    side: BorderSide(color: Colors.greenAccent),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Divider(color: AppColors.borderOf(context)),
              const SizedBox(height: 4),
              // Session list
              Expanded(
                child: ListView.builder(
                  itemCount: sessions.length,
                  itemBuilder: (context, index) {
                    final s = sessions[index];
                    final date = s['date'] as DateTime;
                    final dateStr =
                        '${date.year}-${date.month.toString().padLeft(2, "0")}-${date.day.toString().padLeft(2, "0")} ${date.hour}:${date.minute.toString().padLeft(2, "0")}';
                    final messageCount = s['message_count'] ?? 0;
                    final userMessageCount = s['user_message_count'] ?? 0;
                    final isBranch = s['parent_session'] != null;
                    final description = s['session_description'] as String?;

                    return Card(
                      color: AppColors.cardOf(context),
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: ListTile(
                        leading: isBranch
                            ? const Icon(
                                Icons.call_split,
                                size: 20,
                                color: Colors.blueAccent,
                              )
                            : Icon(
                                Icons.chat,
                                size: 20,
                                color: AppColors.textTertiary(context),
                              ),
                        title: Text(
                          s['preview'],
                          style: TextStyle(
                            fontSize: 13,
                            color: AppColors.textPrimary(context),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const SizedBox(height: 4),
                            Text(
                              dateStr,
                              style: TextStyle(
                                fontSize: 11,
                                color: AppColors.textTertiary(context),
                              ),
                            ),
                            if (description != null && description.isNotEmpty) ...[
                              const SizedBox(height: 4),
                              Text(
                                description,
                                style: TextStyle(
                                  fontSize: 11,
                                  color: AppColors.textTertiary(context),
                                  fontStyle: FontStyle.italic,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                            const SizedBox(height: 6),
                            Wrap(
                              spacing: 6,
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: Colors.blueAccent.withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(4),
                                    border: Border.all(color: Colors.blueAccent.withValues(alpha: 0.3), width: 0.5),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.forum, size: 10, color: AppColors.resolve(context, Colors.blueAccent.shade200, Colors.blueAccent.shade700)),
                                      const SizedBox(width: 4),
                                      Text(
                                        '$messageCount total',
                                        style: TextStyle(fontSize: 10, color: AppColors.resolve(context, Colors.blueAccent.shade200, Colors.blueAccent.shade700), fontWeight: FontWeight.w500),
                                      ),
                                    ],
                                  ),
                                ),
                                if (userMessageCount > 0)
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: Colors.greenAccent.withValues(alpha: 0.15),
                                      borderRadius: BorderRadius.circular(4),
                                      border: Border.all(color: Colors.greenAccent.withValues(alpha: 0.3), width: 0.5),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(Icons.person, size: 10, color: AppColors.resolve(context, Colors.greenAccent.shade200, Colors.greenAccent.shade700)),
                                        const SizedBox(width: 4),
                                        Text(
                                          '$userMessageCount user',
                                          style: TextStyle(fontSize: 10, color: AppColors.resolve(context, Colors.greenAccent.shade200, Colors.greenAccent.shade700), fontWeight: FontWeight.w500),
                                        ),
                                      ],
                                    ),
                                  ),
                              ],
                            ),
                            if (isBranch) ...[
                              const SizedBox(height: 4),
                              Text(
                                '↳ Branched at message #${(s['fork_index'] ?? 0) + 1}',
                                style: TextStyle(
                                  fontSize: 10,
                                  color: AppColors.textSecondary(context),
                                ),
                              ),
                            ],
                          ],
                        ),
                        onTap: () => Navigator.of(ctx).pop(s['id']),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
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
            onPressed: () => Navigator.of(ctx).pop(null),
            child: Text(
              'Cancel',
              style: TextStyle(color: AppColors.textSecondary(context)),
            ),
          ),
        ],
      ),
    );
  }

  // ─── CharacterCardGrid Callback Handlers ────────────────────────

  Future<void> _handleTapCharacter(CharacterCard character) async {
    final chatService = Provider.of<ChatService>(context, listen: false);
    final charId = character.dbId ?? _getCharacterIdFromCard(character);
    final sessions = await chatService.getSessionsForId(charId);

    if (!context.mounted) return;

    if (sessions.length > 1) {
      final selectedId = await _showSessionPickerDialog(
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
      await Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const ChatPage()),
      );
      _refreshLastActivityCache();
    }
  }

  Future<void> _handleTapGroup(GroupChat group) async {
    final chatService = Provider.of<ChatService>(context, listen: false);
    final groupId = 'group_${group.id}';
    final sessions = await chatService.getSessionsForId(groupId);

    if (!context.mounted) return;

    if (sessions.length > 1) {
      final selectedId = await _showSessionPickerDialog(
        context,
        sessions,
        group.name,
      );
      if (selectedId == null || !context.mounted) return;
      await chatService.setActiveGroup(group);
      if (selectedId != '__new__') {
        await chatService.loadSession(selectedId);
      }
      if (selectedId == '__new__') {
        await chatService.startNewChat();
      }
    } else {
      await chatService.setActiveGroup(group);
    }
    if (context.mounted) {
      await Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const ChatPage()),
      );
      _refreshLastActivityCache();
    }
  }

  void _handleContextMenuAction(String action, CharacterCard character) {
    switch (action) {
      case 'edit':
        _editCharacter(context, character);
        break;
      case 'duplicate':
        _duplicateCharacter(context, character);
        break;
      case 'export':
        _exportCharacter(context, character);
        break;
      case 'remove_folder':
        final folderService = Provider.of<FolderService>(context, listen: false);
        if (_activeFolderId != null && character.imagePath != null) {
          folderService.removeFromFolder(_activeFolderId!, character.imagePath!);
        }
        break;
      case 'delete':
        _confirmDeleteCharacter(context, character);
        break;
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

  void _handleOpenBrowser(String site) {
    switch (site) {
      case 'aicc':
        _openBrowser(context);
        break;
      case 'chub':
        _showChubWarning(context);
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
    setState(() {
      if (_activeFolderId != null) {
        _folderStack.add(_activeFolderId!);
      }
      _activeFolderId = folder.id;
    });
  }

  void _handleFolderNavigateBack() {
    setState(() {
      if (_folderStack.isNotEmpty) {
        _activeFolderId = _folderStack.removeLast();
      } else {
        _activeFolderId = null;
      }
    });
  }

  void _handleCreateGroup(Set<String> selectedIds) {
    final repo = Provider.of<CharacterRepository>(context, listen: false);
    _showCreateGroupDialog(context, repo);
  }

  void _handleMoveToFolder(Set<String> selectedIds) {
    final repo = Provider.of<CharacterRepository>(context, listen: false);
    final folderService = Provider.of<FolderService>(context, listen: false);
    _showMoveToFolderDialog(context, repo, folderService);
  }

  void _handleSortChanged(String mode) {
    setState(() => _sortMode = mode);
    Provider.of<StorageService>(context, listen: false).setSortMode(mode);
  }

  void _handleGridScaleChanged(double scale) {
    setState(() => _gridScale = scale);
  }

  void _handleGridScaleChangeEnd(double scale) {
    Provider.of<StorageService>(context, listen: false).setGridScale(scale);
  }

  void _handleSearchScopeChanged(SearchScope scope) {
    setState(() => _searchScope = scope);
  }

  void _handleSearchQueryChanged(String query) {
    setState(() => _searchQuery = query);
  }

  void _handleDeleteGroup(GroupChat group) {
    _confirmDeleteGroup(context, group);
  }

  void _confirmDeleteGroup(BuildContext context, GroupChat group) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF2D1111),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: Colors.redAccent, width: 2),
        ),
        title: const Text(
          'Delete Group',
          style: TextStyle(
            color: Colors.redAccent,
            fontWeight: FontWeight.bold,
          ),
        ),
        content: Text(
          'Delete group "${group.name}"?\n\nThe characters themselves will NOT be deleted.',
          style: const TextStyle(color: Colors.white70, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text(
              'Cancel',
              style: TextStyle(color: Colors.white54),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () {
              final groupRepo = Provider.of<GroupChatRepository>(
                context,
                listen: false,
              );
              final cloudSyncService = Provider.of<CloudSyncService>(
                context,
                listen: false,
              );
              groupRepo.delete(group.id, cloudSyncService: cloudSyncService);
              Navigator.pop(ctx);
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  // ─── Group Creation Dialog ──────────────────────────────────────

  void _showMoveToFolderDialog(
    BuildContext context,
    CharacterRepository repo,
    FolderService folderService,
  ) {
    final folders = folderService.folders.toList()
      ..sort((a, b) {
        final pathA = folderService.getFolderPath(a.id).toLowerCase();
        final pathB = folderService.getFolderPath(b.id).toLowerCase();
        return pathA.compareTo(pathB);
      });

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: Colors.blueAccent, width: 0.5),
        ),
        title: Row(
          children: [
            const Icon(Icons.drive_file_move, color: Colors.blueAccent),
            const SizedBox(width: 12),
            Text(
              'Move ${_selectedCharacterIds.length} character${_selectedCharacterIds.length == 1 ? '' : 's'} to folder',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        content: SizedBox(
          width: 320,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (folders.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Text(
                      'No folders yet. Create one below.',
                      style: TextStyle(color: Colors.white54),
                    ),
                  ),
                ...folders.map((folder) {
                  final folderPath = folderService.getFolderPath(folder.id);
                  final isSubfolder = folder.parentId != null;
                  return ListTile(
                    leading: Icon(
                      isSubfolder ? Icons.subdirectory_arrow_right : Icons.folder,
                      color: Colors.amberAccent,
                    ),
                    title: Text(
                      folderPath,
                      style: const TextStyle(color: Colors.white),
                    ),
                    subtitle: Text(
                      '${folder.characterPaths.length} characters',
                      style: const TextStyle(color: Colors.white38, fontSize: 12),
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    hoverColor: Colors.white10,
                    onTap: () async {
                      Navigator.pop(ctx);
                      await _moveSelectedToFolder(
                        context,
                        folder.id,
                        repo,
                        folderService,
                      );
                    },
                  );
                }),
              const Divider(color: Colors.white12),
              ListTile(
                leading: const Icon(
                  Icons.create_new_folder,
                  color: Colors.greenAccent,
                ),
                title: const Text(
                  'New Folder',
                  style: TextStyle(color: Colors.greenAccent),
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                hoverColor: Colors.white10,
                onTap: () async {
                  Navigator.pop(ctx);
                  final name = await _promptFolderName(context);
                  if (name != null && name.isNotEmpty && context.mounted) {
                    final folder = await folderService.createFolder(name);
                    await _moveSelectedToFolder(
                      context,
                      folder.id,
                      repo,
                      folderService,
                    );
                  }
                },
              ),
            ],
          ),
        ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text(
              'Cancel',
              style: TextStyle(color: Colors.white54),
            ),
          ),
        ],
      ),
    );
  }

  Future<String?> _promptFolderName(BuildContext context) async {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('New Folder'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Folder name'),
          onSubmitted: (val) => Navigator.pop(ctx, val),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text(
              'Cancel',
              style: TextStyle(color: Colors.white54),
            ),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.blueAccent),
            child: const Text('Create'),
          ),
        ],
      ),
    );
  }

  Future<void> _moveSelectedToFolder(
    BuildContext context,
    String folderId,
    CharacterRepository repo,
    FolderService folderService,
  ) async {
    // Resolve selected IDs back to imagePaths
    for (final id in _selectedCharacterIds) {
      final card = repo.characters
          .where((c) => _getCharacterIdFromCard(c) == id)
          .firstOrNull;
      if (card?.imagePath != null) {
        await folderService.addToFolder(folderId, card!.imagePath!);
      }
    }
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Moved ${_selectedCharacterIds.length} character${_selectedCharacterIds.length == 1 ? '' : 's'} to folder',
          ),
        ),
      );
    }
    _cancelSelection();
  }

  void _showCreateGroupDialog(BuildContext context, CharacterRepository repo) {
    _showCreateGroupDialogInner(context, repo);
  }

  void _showCreateGroupDialogInner(
    BuildContext context,
    CharacterRepository repo,
  ) {
    final nameController = TextEditingController();
    final firstMessageController = TextEditingController();
    final scenarioController = TextEditingController();
    final systemPromptController = TextEditingController(); // Defaults to empty - uses built-in group rules unless overridden
    TurnOrder selectedTurnOrder = TurnOrder.roundRobin;
    bool autoAdvance = false;
    bool isGeneratingFirstMessage = false;
    bool isGeneratingScenario = false;
    bool directorMode = false;
    final Map<String, String> characterVoices = {}; // charId -> voiceKey

    // Build default name from selected character names
    final selectedChars = <CharacterCard>[];
    for (final id in _selectedCharacterIds) {
      final match = repo.characters
          .where((c) => _getCharacterIdFromCard(c) == id)
          .firstOrNull;
      if (match != null) selectedChars.add(match);
    }
    nameController.text = selectedChars.map((c) => c.name).join(' & ');

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          backgroundColor: const Color(0xFF1F2937),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: const Row(
            children: [
              Icon(Icons.group_add, color: Colors.purpleAccent),
              SizedBox(width: 8),
              Text('Create Group Chat', style: TextStyle(color: Colors.white)),
            ],
          ),
          content: SizedBox(
            width: 400,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Selected characters preview
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: selectedChars
                        .map(
                          (c) => Chip(
                            avatar: c.imagePath != null
                                ? CircleAvatar(
                                    child: ClipOval(
                                      child: Image.file(
                                        _resolveCharImage(c.imagePath!),
                                        fit: BoxFit.cover,
                                        errorBuilder: (_, _, _) => const Icon(Icons.person, size: 14),
                                        width: 24,
                                        height: 24,
                                      ),
                                    ),
                                  )
                                : const CircleAvatar(
                                    child: Icon(Icons.person, size: 14),
                                  ),
                            label: Text(
                              c.name,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                              ),
                            ),
                            backgroundColor: Colors.purpleAccent.withValues(
                              alpha: 0.2,
                            ),
                            side: BorderSide(
                              color: Colors.purpleAccent.withValues(alpha: 0.4),
                            ),
                          ),
                        )
                        .toList(),
                  ),
                  const SizedBox(height: 16),
                  // Group name
                  TextField(
                    controller: nameController,
                    style: const TextStyle(color: Colors.white),
                    decoration: const InputDecoration(
                      labelText: 'Group Name',
                      labelStyle: TextStyle(color: Colors.white54),
                      hintText: 'Enter a group name...',
                      hintStyle: TextStyle(color: Colors.white24),
                      enabledBorder: UnderlineInputBorder(
                        borderSide: BorderSide(color: Colors.white24),
                      ),
                      focusedBorder: UnderlineInputBorder(
                        borderSide: BorderSide(color: Colors.purpleAccent),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  // Turn order
                  const Text(
                    'Turn Order',
                    style: TextStyle(color: Colors.white70, fontSize: 13),
                  ),
                  const SizedBox(height: 8),
                  SegmentedButton<TurnOrder>(
                    segments: const [
                      ButtonSegment(
                        value: TurnOrder.roundRobin,
                        label: Text('Round Robin'),
                        icon: Icon(Icons.repeat),
                      ),
                      ButtonSegment(
                        value: TurnOrder.random,
                        label: Text('Random'),
                        icon: Icon(Icons.shuffle),
                      ),
                    ],
                    selected: {selectedTurnOrder},
                    onSelectionChanged: (val) =>
                        setDialogState(() => selectedTurnOrder = val.first),
                    style: ButtonStyle(
                      foregroundColor: WidgetStateProperty.resolveWith(
                        (states) => states.contains(WidgetState.selected)
                            ? Colors.white
                            : Colors.white54,
                      ),
                      backgroundColor: WidgetStateProperty.resolveWith(
                        (states) => states.contains(WidgetState.selected)
                            ? Colors.purpleAccent
                            : Colors.transparent,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  // Auto-advance toggle
                  SwitchListTile(
                    value: autoAdvance,
                    onChanged: directorMode
                        ? null
                        : (val) => setDialogState(() => autoAdvance = val),
                    title: Text(
                      'Auto-Advance',
                      style: TextStyle(
                        color: directorMode ? Colors.white30 : Colors.white,
                        fontSize: 14,
                      ),
                    ),
                    subtitle: const Text(
                      'Characters respond automatically one after another',
                      style: TextStyle(color: Colors.white38, fontSize: 12),
                    ),
                    activeThumbColor: Colors.purpleAccent,
                    contentPadding: EdgeInsets.zero,
                  ),
                  const SizedBox(height: 8),
                  // ── Director Mode toggle ──
                  SwitchListTile(
                    value: directorMode,
                    onChanged: (val) async {
                      setDialogState(() {
                        directorMode = val;
                        if (val) autoAdvance = true;
                      });
                      // Auto-generate scenario, first message when entering Director Mode
                      if (val) {
                        // Auto-generate scenario
                        final llmProvider = Provider.of<LLMProvider>(
                          context,
                          listen: false,
                        );
                        final service = llmProvider.activeService;
                        if (service.isReady &&
                            scenarioController.text.trim().isEmpty) {
                          setDialogState(() => isGeneratingScenario = true);
                          try {
                            final charBriefs = selectedChars
                                .map((c) {
                                  final trait = c.personality.isNotEmpty
                                      ? c.personality.split('.').first
                                      : (c.description.isNotEmpty
                                            ? c.description.split('.').first
                                            : c.name);
                                  return '${c.name} ($trait)';
                                })
                                .join(', ');
                            final scenarioPrompt =
                                '[Output ONLY the scenario text. No planning, reasoning, or explanation. '
                                'Do NOT use <think> tags.]\n\n'
                                'Write a brief scenario (1-2 sentences max) for a group roleplay with: $charBriefs.\n'
                                'This is a DIRECTOR MODE scenario — there is NO user/player present. '
                                'The characters interact ONLY with each other.\n'
                                'Describe WHERE the characters are and WHAT is happening between them.\n\n'
                                'SCENARIO: ';
                            final buffer = StringBuffer();
                            final params = GenerationParams(
                              prompt: scenarioPrompt,
                              maxLength: 500,
                              temperature: 0.9,
                              stopSequences: ['\n\n', 'END', '---', '<think>'],
                            );
                            await for (final token in service.generateStream(
                              params,
                            )) {
                              buffer.write(token);
                            }
                            var result = buffer
                                .toString()
                                .replaceAll(
                                  RegExp(
                                    r'<think>[\s\S]*?</think>',
                                    caseSensitive: false,
                                  ),
                                  '',
                                )
                                .replaceAll(
                                  RegExp(
                                    r'<think>[\s\S]*$',
                                    caseSensitive: false,
                                  ),
                                  '',
                                )
                                .replaceAll(
                                  RegExp(r'</think>', caseSensitive: false),
                                  '',
                                )
                                .replaceAll(
                                  RegExp(
                                    r'^SCENARIO:\s*',
                                    caseSensitive: false,
                                  ),
                                  '',
                                )
                                .replaceAll('"', '')
                                .trim();
                            if (result.isNotEmpty) {
                              scenarioController.text = result;
                            }
                          } catch (_) {}
                          setDialogState(() => isGeneratingScenario = false);
                          // Auto-generate first message using the scenario
                          if (service.isReady) {
                            setDialogState(
                              () => isGeneratingFirstMessage = true,
                            );
                            try {
                              final charDescriptions = selectedChars
                                  .map((c) {
                                    final persona = c.personality.isNotEmpty
                                        ? c.personality
                                        : c.description;
                                    return '- ${c.name}: $persona';
                                  })
                                  .join('\n');
                              final scenarioCtx =
                                  scenarioController.text.trim().isNotEmpty
                                  ? '\nThe scenario is: ${scenarioController.text.trim()}'
                                  : '';
                              final metaPrompt =
                                  '[INSTRUCTIONS: Output ONLY the creative scene text. '
                                  'Do NOT plan, reason, analyze, or explain. '
                                  'Do NOT use <think> tags. Start writing IMMEDIATELY.]\n\n'
                                  'Write a vivid, immersive opening scene (3-5 paragraphs) '
                                  'for a DIRECTOR MODE group roleplay featuring:\n$charDescriptions\n$scenarioCtx\n\n'
                                  'CRITICAL: There is NO user/player present. Characters interact ONLY with each other.\n'
                                  'Each character MUST have at least 2 lines of dialogue.\n'
                                  'Characters address and react to EACH OTHER.\n'
                                  'Use *asterisks* for actions.\n'
                                  'When done, write "END SCENE" on its own line.\n\n'
                                  'BEGIN SCENE:\n';
                              final buffer = StringBuffer();
                              final params = GenerationParams(
                                prompt: metaPrompt,
                                maxLength: 2000,
                                temperature: 0.85,
                                stopSequences: [
                                  'END SCENE',
                                  '---',
                                  '[END]',
                                  '<think>',
                                ],
                              );
                              await for (final token in service.generateStream(
                                params,
                              )) {
                                buffer.write(token);
                              }
                              var result = buffer
                                  .toString()
                                  .replaceAll(
                                    RegExp(
                                      r'<think>[\s\S]*?</think>',
                                      caseSensitive: false,
                                    ),
                                    '',
                                  )
                                  .replaceAll(
                                    RegExp(
                                      r'<think>[\s\S]*$',
                                      caseSensitive: false,
                                    ),
                                    '',
                                  )
                                  .replaceAll(
                                    RegExp(r'</think>', caseSensitive: false),
                                    '',
                                  );
                              final marker = result.indexOf('BEGIN SCENE:');
                              if (marker >= 0) {
                                result = result.substring(
                                  marker + 'BEGIN SCENE:'.length,
                                );
                              }
                              final cleaned = result
                                  .split('\n')
                                  .where((line) {
                                    final t = line.trimLeft();
                                    return !(t.startsWith('The user wants') ||
                                        t.startsWith('I need to') ||
                                        t.startsWith('I will') ||
                                        t.startsWith('I should') ||
                                        t.startsWith('Let me ') ||
                                        t.startsWith('I\'ll ') ||
                                        RegExp(
                                          r'^\d+\.\s+(Write|Use|Set|Make|Do|Keep|NOT|Create|End|Establish)',
                                        ).hasMatch(t));
                                  })
                                  .join('\n')
                                  .trim();
                              if (cleaned.isNotEmpty) {
                                firstMessageController.text = cleaned;
                              }
                            } catch (_) {}
                            setDialogState(
                              () => isGeneratingFirstMessage = false,
                            );
                          }
                        }
                      }
                    },
                    title: Row(
                      children: [
                        const Icon(
                          Icons.movie_creation,
                          size: 16,
                          color: Colors.amberAccent,
                        ),
                        const SizedBox(width: 6),
                        const Text(
                          'Director Mode',
                          style: TextStyle(color: Colors.white, fontSize: 14),
                        ),
                      ],
                    ),
                    subtitle: const Text(
                      'Characters chat autonomously — you direct the scene',
                      style: TextStyle(color: Colors.amberAccent, fontSize: 11),
                    ),
                    activeThumbColor: Colors.amberAccent,
                    contentPadding: EdgeInsets.zero,
                  ),
                  // ── Per-character voice selection ──
                  if (selectedChars.length > 1) ...[
                    const SizedBox(height: 12),
                    const Text(
                      'Character Voices',
                      style: TextStyle(color: Colors.white54, fontSize: 12),
                    ),
                    const SizedBox(height: 6),
                    ...selectedChars.map((c) {
                      final charId = _getCharacterIdFromCard(c);
                      final currentVoice =
                          characterVoices[charId] ?? c.ttsVoice;
                      final tts = Provider.of<TtsService>(
                        context,
                        listen: false,
                      );
                      final voices = tts.activeVoices;
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Row(
                          children: [
                            c.imagePath != null
                                ? CircleAvatar(
                                    radius: 12,
                                    child: ClipOval(
                                      child: Image.file(
                                        _resolveCharImage(c.imagePath!),
                                        fit: BoxFit.cover,
                                        errorBuilder: (_, _, _) => const Icon(Icons.person, size: 12),
                                        width: 24,
                                        height: 24,
                                      ),
                                    ),
                                  )
                                : const CircleAvatar(
                                    radius: 12,
                                    child: Icon(Icons.person, size: 12),
                                  ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                c.name,
                                style: const TextStyle(
                                  color: Colors.white70,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                            DropdownButton<String>(
                              value:
                                  (currentVoice != null &&
                                      currentVoice.isNotEmpty)
                                  ? currentVoice
                                  : null,
                              hint: const Text(
                                'Default',
                                style: TextStyle(
                                  color: Colors.white30,
                                  fontSize: 11,
                                ),
                              ),
                              dropdownColor: const Color(0xFF2D3748),
                              underline: const SizedBox(),
                              isDense: true,
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 11,
                              ),
                              items: [
                                const DropdownMenuItem(
                                  value: '',
                                  child: Text(
                                    'Default',
                                    style: TextStyle(fontSize: 11),
                                  ),
                                ),
                                ...voices.map(
                                  (v) => DropdownMenuItem(
                                    value: v.id,
                                    child: Text(
                                      v.name,
                                      style: const TextStyle(fontSize: 11),
                                    ),
                                  ),
                                ),
                              ],
                              onChanged: (val) {
                                setDialogState(() {
                                  characterVoices[charId] = val ?? '';
                                });
                              },
                            ),
                          ],
                        ),
                      );
                    }),
                  ],
                  const SizedBox(height: 16),
                  // ── Scenario (optional) — with Generate button ──
                  Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'Scenario (optional)',
                          style: TextStyle(color: Colors.white54, fontSize: 12),
                        ),
                      ),
                      TextButton.icon(
                        onPressed: isGeneratingScenario
                            ? null
                            : () async {
                                final llmProvider = Provider.of<LLMProvider>(
                                  context,
                                  listen: false,
                                );
                                final service = llmProvider.activeService;
                                if (!service.isReady) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text(
                                        'LLM backend is not ready. Start KoboldCPP or configure your API first.',
                                      ),
                                    ),
                                  );
                                  return;
                                }

                                setDialogState(
                                  () => isGeneratingScenario = true,
                                );

                                final charNames = selectedChars
                                    .map((c) => c.name)
                                    .join(', ');
                                final charBriefs = selectedChars
                                    .map((c) {
                                      final trait = c.personality.isNotEmpty
                                          ? c.personality.split('.').first
                                          : (c.description.isNotEmpty
                                                ? c.description.split('.').first
                                                : c.name);
                                      return '${c.name} ($trait)';
                                    })
                                    .join(', ');

                                final scenarioPrompt =
                                    '[Output ONLY the scenario text. No planning, reasoning, or explanation. '
                                    'Do NOT use <think> tags.]\n\n'
                                    'Write a brief scenario (1-2 sentences max) for a group roleplay with: $charBriefs.\n'
                                    'The scenario should describe WHERE the characters are and WHAT is happening.\n'
                                    'Use {{user}} to refer to the player. Keep it concise like:\n'
                                    '"{{user}} and $charNames are hanging out at a rooftop bar downtown on a Friday night."\n\n'
                                    'SCENARIO: ';

                                try {
                                  final buffer = StringBuffer();
                                  final params = GenerationParams(
                                    prompt: scenarioPrompt,
                                    maxLength: 500,
                                    temperature: 0.9,
                                    stopSequences: [
                                      '\n\n',
                                      'END',
                                      '---',
                                      '<think>',
                                    ],
                                  );
                                  await for (final token
                                      in service.generateStream(params)) {
                                    buffer.write(token);
                                  }
                                  var result = buffer
                                      .toString()
                                      .replaceAll(
                                        RegExp(
                                          r'<think>[\s\S]*?</think>',
                                          caseSensitive: false,
                                        ),
                                        '',
                                      )
                                      .replaceAll(
                                        RegExp(
                                          r'<think>[\s\S]*$',
                                          caseSensitive: false,
                                        ),
                                        '',
                                      )
                                      .replaceAll(
                                        RegExp(
                                          r'</think>',
                                          caseSensitive: false,
                                        ),
                                        '',
                                      )
                                      .replaceAll(
                                        RegExp(
                                          r'^SCENARIO:\s*',
                                          caseSensitive: false,
                                        ),
                                        '',
                                      )
                                      .replaceAll('"', '')
                                      .trim();

                                  if (result.isNotEmpty) {
                                    scenarioController.text = result;
                                  }
                                } catch (e) {
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text('Generation failed: $e'),
                                      ),
                                    );
                                  }
                                } finally {
                                  setDialogState(
                                    () => isGeneratingScenario = false,
                                  );
                                }
                              },
                        icon: isGeneratingScenario
                            ? const SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.amberAccent,
                                ),
                              )
                            : const Icon(
                                Icons.auto_awesome,
                                size: 16,
                                color: Colors.amberAccent,
                              ),
                        label: Text(
                          isGeneratingScenario ? 'Generating...' : 'Generate',
                          style: const TextStyle(
                            color: Colors.amberAccent,
                            fontSize: 12,
                          ),
                        ),
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  TextField(
                    controller: scenarioController,
                    style: const TextStyle(color: Colors.white),
                    maxLines: 2,
                    decoration: const InputDecoration(
                      hintText:
                          'e.g. {{user}} and friends are at a rooftop bar...',
                      hintStyle: TextStyle(color: Colors.white24),
                      enabledBorder: UnderlineInputBorder(
                        borderSide: BorderSide(color: Colors.white24),
                      ),
                      focusedBorder: UnderlineInputBorder(
                        borderSide: BorderSide(color: Colors.purpleAccent),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  // ── First Message (optional) — with Generate button ──
                  Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'First Message (optional)',
                          style: TextStyle(color: Colors.white54, fontSize: 12),
                        ),
                      ),
                      TextButton.icon(
                        onPressed: isGeneratingFirstMessage
                            ? null
                            : () async {
                                final llmProvider = Provider.of<LLMProvider>(
                                  context,
                                  listen: false,
                                );
                                final service = llmProvider.activeService;
                                if (!service.isReady) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text(
                                        'LLM backend is not ready. Start KoboldCPP or configure your API first.',
                                      ),
                                    ),
                                  );
                                  return;
                                }

                                setDialogState(
                                  () => isGeneratingFirstMessage = true,
                                );

                                // Build a meta-prompt from all selected characters
                                final charDescriptions = selectedChars
                                    .map((c) {
                                      final persona = c.personality.isNotEmpty
                                          ? c.personality
                                          : c.description;
                                      final scenario = c.scenario.isNotEmpty
                                          ? ' Scenario: ${c.scenario}'
                                          : '';
                                      return '- ${c.name}: $persona$scenario';
                                    })
                                    .join('\n');

                                final scenarioContext =
                                    scenarioController.text.trim().isNotEmpty
                                    ? '\nThe group scenario is: ${scenarioController.text.trim()}'
                                    : '';

                                final metaPrompt =
                                    '[INSTRUCTIONS: Output ONLY the creative scene text. '
                                    'Do NOT plan, reason, analyze, or explain what you will write. '
                                    'Do NOT list requirements or break down the task. '
                                    'Do NOT use <think> tags. Start writing the scene IMMEDIATELY.]\n\n'
                                    'Write a vivid, immersive opening scene (4-6 paragraphs, at least 400 words) '
                                    'for a group roleplay featuring:\n$charDescriptions\n$scenarioContext\n\n'
                                    'CRITICAL REQUIREMENTS:\n'
                                    '- {{user}} is PRESENT in the scene. Characters notice, acknowledge, and speak TO {{user}}.\n'
                                    '- EACH character MUST have at least 2 lines of spoken dialogue using quotation marks.\n'
                                    '- Characters MUST interact with EACH OTHER — they speak to, react to, and acknowledge one another.\n'
                                    '- Describe the environment with rich sensory details (sights, sounds, smells, textures).\n'
                                    '- Show each character doing physical actions that reveal their personality.\n'
                                    '- Use third-person narration with *asterisks* for actions and descriptions.\n'
                                    '- Do NOT write any dialogue, thoughts, or actions for {{user}}.\n'
                                    '- End with a character directly addressing {{user}}, creating a natural moment for {{user}} to respond.\n'
                                    '- When the scene is complete, write "END SCENE" on its own line.\n\n'
                                    'BEGIN SCENE:\n';

                                try {
                                  final buffer = StringBuffer();
                                  final params = GenerationParams(
                                    prompt: metaPrompt,
                                    maxLength: 4000,
                                    temperature: 0.85,
                                    stopSequences: [
                                      'END SCENE',
                                      '---',
                                      '[END]',
                                      '<think>',
                                    ],
                                  );
                                  await for (final token
                                      in service.generateStream(params)) {
                                    buffer.write(token);
                                  }
                                  var result = buffer
                                      .toString()
                                      .replaceAll(
                                        RegExp(
                                          r'<think>[\s\S]*?</think>',
                                          caseSensitive: false,
                                        ),
                                        '',
                                      )
                                      .replaceAll(
                                        RegExp(
                                          r'<think>[\s\S]*$',
                                          caseSensitive: false,
                                        ),
                                        '',
                                      )
                                      .replaceAll(
                                        RegExp(
                                          r'</think>',
                                          caseSensitive: false,
                                        ),
                                        '',
                                      );

                                  final sceneMarker = result.indexOf(
                                    'BEGIN SCENE:',
                                  );
                                  if (sceneMarker >= 0) {
                                    result = result.substring(
                                      sceneMarker + 'BEGIN SCENE:'.length,
                                    );
                                  }

                                  final lines = result.split('\n');
                                  final cleaned = lines
                                      .where((line) {
                                        final trimmed = line.trimLeft();
                                        if (trimmed.startsWith(
                                              'The user wants',
                                            ) ||
                                            trimmed.startsWith('I need to') ||
                                            trimmed.startsWith('I will') ||
                                            trimmed.startsWith('I should') ||
                                            trimmed.startsWith('Let me ') ||
                                            trimmed.startsWith('I\'ll ') ||
                                            RegExp(
                                              r'^\d+\.\s+(Write|Use|Set|Make|Do|Keep|NOT|Create|End|Establish)',
                                            ).hasMatch(trimmed)) {
                                          return false;
                                        }
                                        return true;
                                      })
                                      .join('\n')
                                      .trim();

                                  if (cleaned.isNotEmpty) {
                                    firstMessageController.text = cleaned;
                                  }
                                } catch (e) {
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text('Generation failed: $e'),
                                      ),
                                    );
                                  }
                                } finally {
                                  setDialogState(
                                    () => isGeneratingFirstMessage = false,
                                  );
                                }
                              },
                        icon: isGeneratingFirstMessage
                            ? const SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.amberAccent,
                                ),
                              )
                            : const Icon(
                                Icons.auto_awesome,
                                size: 16,
                                color: Colors.amberAccent,
                              ),
                        label: Text(
                          isGeneratingFirstMessage
                              ? 'Generating...'
                              : 'Generate',
                          style: const TextStyle(
                            color: Colors.amberAccent,
                            fontSize: 12,
                          ),
                        ),
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  TextField(
                    controller: firstMessageController,
                    style: const TextStyle(color: Colors.white),
                    maxLines: 5,
                    decoration: const InputDecoration(
                      hintText:
                          'Custom greeting or tap Generate ✨ (uses scenario above)',
                      hintStyle: TextStyle(color: Colors.white24),
                      enabledBorder: UnderlineInputBorder(
                        borderSide: BorderSide(color: Colors.white24),
                      ),
                      focusedBorder: UnderlineInputBorder(
                        borderSide: BorderSide(color: Colors.purpleAccent),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  // System Prompt (optional)
                  TextField(
                    controller: systemPromptController,
                    style: const TextStyle(color: Colors.white),
                    maxLines: 3,
                    decoration: const InputDecoration(
                      labelText: 'System Prompt (optional)',
                      labelStyle: TextStyle(color: Colors.white54),
                      hintText: 'Override the global system prompt...',
                      hintStyle: TextStyle(color: Colors.white24),
                      enabledBorder: UnderlineInputBorder(
                        borderSide: BorderSide(color: Colors.white24),
                      ),
                      focusedBorder: UnderlineInputBorder(
                        borderSide: BorderSide(color: Colors.purpleAccent),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text(
                'Cancel',
                style: TextStyle(color: Colors.white54),
              ),
            ),
            ElevatedButton.icon(
              icon: const Icon(Icons.check),
              label: const Text('Create'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.purpleAccent,
                foregroundColor: Colors.white,
              ),
              onPressed: () {
                final name = nameController.text.trim();
                if (name.isEmpty) return;

                final group = GroupChat(
                  id: 'group_${DateTime.now().millisecondsSinceEpoch}',
                  name: name,
                  characterIds: _selectedCharacterIds.toList(),
                  turnOrder: selectedTurnOrder,
                  autoAdvance: autoAdvance,
                  directorMode: directorMode,
                  firstMessage: firstMessageController.text.trim(),
                  scenario: scenarioController.text.trim(),
                  systemPrompt: systemPromptController.text.trim(),
                );

                final groupRepo = Provider.of<GroupChatRepository>(
                  context,
                  listen: false,
                );
                groupRepo.save(group);

                // Save per-character voices
                final charRepo = Provider.of<CharacterRepository>(
                  context,
                  listen: false,
                );
                for (final entry in characterVoices.entries) {
                  final card = charRepo.characters
                      .where((c) => _getCharacterIdFromCard(c) == entry.key)
                      .firstOrNull;
                  if (card != null && entry.value != card.ttsVoice) {
                    card.ttsVoice = entry.value.isEmpty ? null : entry.value;
                    charRepo.updateCharacter(card);
                  }
                }

                Navigator.pop(ctx);
                _cancelSelection();

                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Group "$name" created!'),
                    backgroundColor: Colors.purpleAccent.shade700,
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  // ─── Folder Actions ─────────────────────────────────────────────

  void _createFolder(
    BuildContext context,
    FolderService folderService, {
    String? parentId,
  }) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1F2937),
        title: Text(
          parentId != null ? 'New Subfolder' : 'New Folder',
          style: const TextStyle(color: Colors.white),
        ),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            hintText: 'Folder name...',
            hintStyle: TextStyle(color: Colors.white38),
          ),
          onSubmitted: (value) {
            if (value.trim().isNotEmpty) {
              folderService.createFolder(value.trim(), parentId: parentId);
              Navigator.pop(ctx);
            }
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text(
              'Cancel',
              style: TextStyle(color: Colors.white54),
            ),
          ),
          ElevatedButton(
            onPressed: () {
              if (controller.text.trim().isNotEmpty) {
                folderService.createFolder(
                  controller.text.trim(),
                  parentId: parentId,
                );
                Navigator.pop(ctx);
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.amber.shade700,
            ),
            child: const Text('Create'),
          ),
        ],
      ),
    );
  }

  void _renameFolder(
    BuildContext context,
    CharacterFolder folder,
    FolderService folderService,
  ) {
    final controller = TextEditingController(text: folder.name);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1F2937),
        title: const Text(
          'Rename Folder',
          style: TextStyle(color: Colors.white),
        ),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: const TextStyle(color: Colors.white),
          onSubmitted: (value) {
            if (value.trim().isNotEmpty) {
              folderService.renameFolder(folder.id, value.trim());
              Navigator.pop(ctx);
            }
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text(
              'Cancel',
              style: TextStyle(color: Colors.white54),
            ),
          ),
          ElevatedButton(
            onPressed: () {
              if (controller.text.trim().isNotEmpty) {
                folderService.renameFolder(folder.id, controller.text.trim());
                Navigator.pop(ctx);
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.amber.shade700,
            ),
            child: const Text('Rename'),
          ),
        ],
      ),
    );
  }

  void _deleteFolder(
    BuildContext context,
    CharacterFolder folder,
    FolderService folderService,
  ) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF2D1111),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: Colors.redAccent, width: 2),
        ),
        title: const Text(
          'Delete Folder',
          style: TextStyle(
            color: Colors.redAccent,
            fontWeight: FontWeight.bold,
          ),
        ),
        content: Text(
          'Delete "${folder.name}"?\n\nCharacters inside will NOT be deleted — they\'ll return to the top level.',
          style: const TextStyle(color: Colors.white70, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text(
              'Cancel',
              style: TextStyle(color: Colors.white54),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () {
              folderService.deleteFolder(folder.id);
              Navigator.pop(ctx);
              if (_activeFolderId == folder.id) {
                setState(() {
                  if (_folderStack.isNotEmpty) {
                    _activeFolderId = _folderStack.removeLast();
                  } else {
                    _activeFolderId = null;
                  }
                });
              }
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  // ─── Character Actions ──────────────────────────────────────────

  ButtonStyle _buttonStyle() {
    return ElevatedButton.styleFrom(
      backgroundColor: AppColors.resolve(
        context,
        Colors.white.withValues(alpha: 0.1),
        Colors.black.withValues(alpha: 0.05),
      ),
      foregroundColor: AppColors.textPrimary(context),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: AppColors.resolve(context, Colors.white24, Colors.black26)),
      ),
    );
  }

  void _confirmDeleteCharacter(BuildContext context, CharacterCard character) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF2D1111),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: Colors.redAccent, width: 2),
        ),
        title: const Row(
          children: [
            Icon(
              Icons.warning_amber_rounded,
              color: Colors.redAccent,
              size: 28,
            ),
            SizedBox(width: 8),
            Text(
              'Delete Character',
              style: TextStyle(
                color: Colors.redAccent,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        content: Text(
          'Are you sure you want to delete "${character.name}"?\n\nThis will permanently remove the character card and its image file. This action cannot be undone.',
          style: const TextStyle(color: Colors.white70, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text(
              'Cancel',
              style: TextStyle(color: Colors.white54),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              foregroundColor: Colors.white,
            ),
            onPressed: () async {
              Navigator.of(context).pop();
              final repo = Provider.of<CharacterRepository>(
                context,
                listen: false,
              );
              final worldRepo = Provider.of<WorldRepository>(
                context,
                listen: false,
              );
              final storageService = Provider.of<StorageService>(
                context,
                listen: false,
              );
              final cloudSyncService = Provider.of<CloudSyncService>(
                context,
                listen: false,
              );
              await repo.deleteCharacter(
                character,
                worldRepo: worldRepo,
                chatsDir: storageService.chatsDir,
                cloudSyncService: cloudSyncService,
              );
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('${character.name} has been deleted.'),
                    backgroundColor: Colors.red.shade800,
                  ),
                );
              }
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  Future<void> _editCharacter(
    BuildContext context,
    CharacterCard character,
  ) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => EditCharacterPage(character: character),
      ),
    );
    // No loadCharacters() needed here — updateCharacter() already updates the
    // in-memory list and calls notifyListeners(). Calling loadCharacters() was
    // re-reading outdated in-memory extensions from the cache and overwriting
    // the freshly-saved values.
  }

  Future<void> _duplicateCharacter(
    BuildContext context,
    CharacterCard character,
  ) async {
    try {
      await Provider.of<CharacterRepository>(
        context,
        listen: false,
      ).duplicateCharacter(character);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Character duplicated successfully.')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to duplicate: $e')));
      }
    }
  }

  Future<void> _importCharacter(BuildContext context) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['png', 'json'],
      allowMultiple: true,
    );

    if (result == null || result.files.isEmpty) return;
    if (!context.mounted) return;

    final files = result.files
        .where((f) => f.path != null)
        .map((f) => File(f.path!))
        .toList();

    if (files.isEmpty) return;

    // Single file: use the original flow with tag dialog
    if (files.length == 1) {
      final file = files.first;
      try {
        final worldRepo = Provider.of<WorldRepository>(context, listen: false);
        final repo = Provider.of<CharacterRepository>(context, listen: false);
        final card = await repo.importCharacter(file, worldRepo: worldRepo);
        if (context.mounted && card != null) {
          // Show tag dialog
          final tags = await TagDialog.show(context, card);
          if (tags != null && context.mounted) {
            card.tags = List.from(tags);
            await repo.updateCharacter(card);
          }
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Character imported successfully!')),
            );
          }
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('Import failed: $e')));
        }
      }
      return;
    }

    // Multiple files: use bulk import with progress dialog
    _runBulkImport(context, files);
  }

  Future<void> _importByaf(BuildContext context) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['byaf'],
      allowMultiple: false,
    );

    if (result == null ||
        result.files.isEmpty ||
        result.files.first.path == null) {
      return;
    }
    if (!context.mounted) return;

    final filePath = result.files.first.path!;
    final byafService = ByafService();

    try {
      // Parse the .byaf archive
      final preview = await byafService.parseByaf(filePath);

      if (!context.mounted) return;

      // Show preview dialog
      final result2 = await showDialog<ByafImportResult>(
        context: context,
        builder: (context) => ByafImportDialog(preview: preview),
      );

      if (result2 == null || !result2.confirmed || !context.mounted) return;

      // Convert to CharacterCard
      final card = byafService.toCharacterCard(preview);

      // Save as PNG (with image if available)
      final storageService = Provider.of<StorageService>(
        context,
        listen: false,
      );
      final pngPath = await byafService.saveCharacterPng(
        card,
        charactersDirPath: storageService.charactersDir.path,
      );

      // Now use V2CardService to embed character data into the PNG
      final v2Service = V2CardService();
      await v2Service.saveCardAsPng(card, pngPath, preview.extractedImagePath);

      // Import via CharacterRepository (reads PNG metadata + inserts into DB)
      final repo = Provider.of<CharacterRepository>(context, listen: false);
      final worldRepo = Provider.of<WorldRepository>(context, listen: false);
      final importedCard = await repo.importCharacter(
        File(pngPath),
        worldRepo: worldRepo,
      );

      // Import chat history if requested
      if (result2.importChatHistory &&
          preview.messages.isNotEmpty &&
          importedCard != null) {
        final db = await AppDatabase.instance();
        await byafService.importChatHistory(db, preview, importedCard);
      }

      if (context.mounted && importedCard != null) {
        final chatNote =
            result2.importChatHistory && preview.messages.isNotEmpty
            ? ' with ${preview.messages.length} chat messages'
            : '';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Imported "${importedCard.name}" from Backyard AI$chatNote!',
            ),
            backgroundColor: Colors.green.shade700,
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to import .byaf: $e')));
      }
    }
  }

  Future<void> _folderImportCharacters(BuildContext context) async {
    final dirPath = await FilePicker.platform.getDirectoryPath(
      dialogTitle: 'Select folder containing character PNGs',
    );

    if (dirPath == null) return;
    if (!context.mounted) return;

    // Scan the folder for PNG files
    final dir = Directory(dirPath);
    final files = <File>[];
    await for (final entity in dir.list(recursive: true)) {
      if (entity is File && entity.path.toLowerCase().endsWith('.png')) {
        files.add(entity);
      }
    }

    if (files.isEmpty) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No PNG files found in the selected folder.'),
          ),
        );
      }
      return;
    }

    _runBulkImport(context, files);
  }

  /// Shared bulk import with progress dialog — used by both multi-select and folder import.
  void _runBulkImport(BuildContext context, List<File> files) {
    bool cancelled = false;
    int currentCount = 0;
    int totalCount = files.length;
    int importedCount = 0;
    int failedCount = 0;
    String currentName = '';

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogCtx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            // Start the import on first build
            if (currentCount == 0 && !cancelled) {
              final repo = Provider.of<CharacterRepository>(
                context,
                listen: false,
              );
              final worldRepo = Provider.of<WorldRepository>(
                context,
                listen: false,
              );
              repo
                  .importCharacters(
                    files,
                    worldRepo: worldRepo,
                    isCancelled: () => cancelled,
                    onProgress: (current, total, name, error) {
                      if (ctx.mounted) {
                        setDialogState(() {
                          currentCount = current;
                          currentName = name;
                          if (error == null) {
                            importedCount++;
                          } else {
                            failedCount++;
                          }
                        });
                      }
                    },
                  )
                  .then((summary) {
                    if (ctx.mounted) Navigator.of(ctx).pop();
                    if (context.mounted) {
                      final msg = failedCount > 0
                          ? 'Imported $importedCount character${importedCount == 1 ? '' : 's'} ($failedCount failed)'
                          : 'Imported $importedCount character${importedCount == 1 ? '' : 's'} successfully!';
                      ScaffoldMessenger.of(
                        context,
                      ).showSnackBar(SnackBar(content: Text(msg)));
                    }
                  });
            }

            final progress = totalCount > 0 ? currentCount / totalCount : 0.0;

            return AlertDialog(
              backgroundColor: const Color(0xFF1E293B),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(
                  color: Colors.blueAccent.withValues(alpha: 0.5),
                ),
              ),
              title: const Row(
                children: [
                  Icon(Icons.library_add, color: Colors.blueAccent),
                  SizedBox(width: 12),
                  Text(
                    'Bulk Import',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              content: SizedBox(
                width: 400,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Progress bar
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: LinearProgressIndicator(
                        value: progress,
                        minHeight: 12,
                        backgroundColor: Colors.white10,
                        valueColor: const AlwaysStoppedAnimation(
                          Colors.blueAccent,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    // Status text
                    Text(
                      currentCount == 0
                          ? 'Starting import...'
                          : 'Importing $currentCount of $totalCount...',
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 8),
                    // Current file name
                    if (currentName.isNotEmpty)
                      Text(
                        currentName,
                        style: const TextStyle(
                          color: Colors.white38,
                          fontSize: 12,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    const SizedBox(height: 16),
                    // Counts row
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _bulkStatChip(
                          Icons.check_circle,
                          Colors.green,
                          '$importedCount imported',
                        ),
                        const SizedBox(width: 16),
                        _bulkStatChip(
                          Icons.error,
                          Colors.redAccent,
                          '$failedCount failed',
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    cancelled = true;
                  },
                  child: Text(
                    cancelled ? 'Cancelling...' : 'Cancel',
                    style: TextStyle(
                      color: cancelled ? Colors.white38 : Colors.redAccent,
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _bulkStatChip(IconData icon, Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 4),
        Text(label, style: TextStyle(color: color, fontSize: 13)),
      ],
    );
  }

  Future<void> _exportCharacter(BuildContext context, character) async {
    String? outputFile = await FilePicker.platform.saveFile(
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
        await v2Service.saveCardAsPng(
          character,
          outputFile,
          character.imagePath,
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

  // ─── Browser Integrations ──────────────────────────────────────

  Future<void> _openBrowser(BuildContext context) async {
    // Skip embedded browser on Linux due to WPE WebKit rendering issues
    if (Platform.isLinux) {
      _showBrowserFallbackDialog(
        context,
        'https://aicharactercards.com/',
        'AI Character Cards',
      );
      return;
    }

    try {
      final repo = Provider.of<CharacterRepository>(context, listen: false);
      final worldRepo = Provider.of<WorldRepository>(context, listen: false);
      final messenger = ScaffoldMessenger.of(context);

      Future<void> handleDownloadUrl(String url) async {
        debugPrint('AG_DEBUG: Download card intercepted: $url');

        try {
          final httpClient = HttpClient();
          final request = await httpClient.getUrl(Uri.parse(url));
          final httpResponse = await request.close();

          final bytes = <int>[];
          await for (final chunk in httpResponse) {
            bytes.addAll(chunk);
          }

          httpClient.close();

          final storageService = Provider.of<StorageService>(
            context,
            listen: false,
          );
          final charDir = storageService.charactersDir;
          if (!await charDir.exists()) {
            await charDir.create(recursive: true);
          }

          final uri = Uri.parse(url);
          String fileName;
          if (uri.pathSegments.isNotEmpty &&
              uri.pathSegments.last.endsWith('.png')) {
            fileName = uri.pathSegments.last;
          } else {
            fileName = 'card_${DateTime.now().millisecondsSinceEpoch}.png';
          }
          final tempFile = File('${charDir.path}/$fileName');
          await tempFile.writeAsBytes(bytes);

          final card = await repo.importCharacter(
            tempFile,
            worldRepo: worldRepo,
          );

          // Show tag dialog after download
          if (card != null && context.mounted) {
            final tags = await TagDialog.show(context, card);
            if (tags != null && context.mounted) {
              card.tags = List.from(tags);
              await repo.updateCharacter(card);
            }
          }

          messenger.showSnackBar(
            SnackBar(
              content: const Text('Character card downloaded and imported!'),
              backgroundColor: Colors.green.shade800,
            ),
          );
        } catch (e) {
          debugPrint('AG_DEBUG: Download error: $e');
          messenger.showSnackBar(
            SnackBar(
              content: Text('Download failed: $e'),
              backgroundColor: Colors.red.shade800,
            ),
          );
        }
      }

      final browser = CharacterBrowser(onDownload: handleDownloadUrl);

      await browser.openUrlRequest(
        urlRequest: URLRequest(url: WebUri('https://aicharactercards.com/')),
        settings: InAppBrowserClassSettings(
          browserSettings: InAppBrowserSettings(
            hideUrlBar: false,
            toolbarTopBackgroundColor: const Color(0xFF1F2937),
          ),
        ),
      );
    } catch (e) {
      debugPrint('AG_DEBUG: Browser failed to launch: $e');
      if (context.mounted) {
        _showBrowserFallbackDialog(
          context,
          'https://aicharactercards.com/',
          'AI Character Cards',
        );
      }
    }
  }

  Future<void> _openChubBrowser(BuildContext context) async {
    // Skip embedded browser on Linux due to WPE WebKit rendering issues
    if (Platform.isLinux) {
      _showBrowserFallbackDialog(context, 'https://chub.ai/', 'Chub.ai');
      return;
    }

    try {
      final repo = Provider.of<CharacterRepository>(context, listen: false);
      final worldRepo = Provider.of<WorldRepository>(context, listen: false);
      final messenger = ScaffoldMessenger.of(context);

      Future<void> handleChubDownload(String url) async {
        debugPrint('AG_DEBUG: Chub download intercepted: $url');

        try {
          final httpClient = HttpClient();
          final request = await httpClient.getUrl(Uri.parse(url));
          final httpResponse = await request.close();

          final bytes = <int>[];
          await for (final chunk in httpResponse) {
            bytes.addAll(chunk);
          }

          httpClient.close();

          final storageService = Provider.of<StorageService>(
            context,
            listen: false,
          );
          final charDir = storageService.charactersDir;
          if (!await charDir.exists()) {
            await charDir.create(recursive: true);
          }

          final uri = Uri.parse(url);
          String fileName;
          if (uri.pathSegments.isNotEmpty &&
              uri.pathSegments.last.endsWith('.png')) {
            fileName = uri.pathSegments.last;
          } else {
            fileName = 'chub_card_${DateTime.now().millisecondsSinceEpoch}.png';
          }
          final tempFile = File('${charDir.path}/$fileName');
          await tempFile.writeAsBytes(bytes);

          final card = await repo.importCharacter(
            tempFile,
            worldRepo: worldRepo,
          );

          // Show tag dialog — Chub.ai cards likely have tags already
          if (card != null && context.mounted) {
            final tags = await TagDialog.show(context, card);
            if (tags != null && context.mounted) {
              card.tags = List.from(tags);
              await repo.updateCharacter(card);
            }
          }

          messenger.showSnackBar(
            SnackBar(
              content: const Text('Chub character downloaded and imported!'),
              backgroundColor: Colors.green.shade800,
            ),
          );
        } catch (e) {
          debugPrint('AG_DEBUG: Chub download error: $e');
          messenger.showSnackBar(
            SnackBar(
              content: Text('Chub download failed: $e'),
              backgroundColor: Colors.red.shade800,
            ),
          );
        }
      }

      final browser = CharacterBrowser(onDownload: handleChubDownload);

      await browser.openUrlRequest(
        urlRequest: URLRequest(url: WebUri('https://chub.ai/')),
        settings: InAppBrowserClassSettings(
          browserSettings: InAppBrowserSettings(
            hideUrlBar: false,
            toolbarTopBackgroundColor: const Color(0xFF1F2937),
          ),
        ),
      );
    } catch (e) {
      debugPrint('AG_DEBUG: Chub browser failed to launch: $e');
      if (context.mounted) {
        _showBrowserFallbackDialog(context, 'https://chub.ai/', 'Chub.ai');
      }
    }
  }

  void _showBrowserFallbackDialog(
    BuildContext context,
    String url,
    String siteName,
  ) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: const Color(0xFF1F2937),
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.orange),
            SizedBox(width: 8),
            Text(
              'Browser Rendering Issue',
              style: TextStyle(color: Colors.white),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'The embedded browser is having trouble rendering on your system. This is a known issue with certain Linux GPU configurations.',
              style: TextStyle(color: Colors.white70),
            ),
            const SizedBox(height: 16),
            const Text(
              'You can still download characters manually:',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              '1. Click "Open in Browser" below\n2. Download character .png files\n3. Use "Import Card" button to add them',
              style: TextStyle(color: Colors.white70),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text(
              'Cancel',
              style: TextStyle(color: Colors.white70),
            ),
          ),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blueAccent,
              foregroundColor: Colors.white,
            ),
            icon: const Icon(Icons.open_in_browser),
            label: const Text('Open in Browser'),
            onPressed: () async {
              Navigator.pop(dialogContext);
              final uri = Uri.parse(url);
              if (await canLaunchUrl(uri)) {
                await launchUrl(uri, mode: LaunchMode.externalApplication);
              } else {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Could not open $siteName'),
                      backgroundColor: Colors.red.shade800,
                    ),
                  );
                }
              }
            },
          ),
        ],
      ),
    );
  }

  void _showChubWarning(BuildContext context) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: const Color(0xFF2D1111),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: Colors.redAccent, width: 2),
        ),
        title: const Row(
          children: [
            Icon(
              Icons.warning_amber_rounded,
              color: Colors.redAccent,
              size: 28,
            ),
            SizedBox(width: 8),
            Text(
              '⚠️ TRAVELER, BEWARE ⚠️',
              style: TextStyle(
                color: Colors.redAccent,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.asset(
                  'assets/images/eye_bleach.jpg',
                  height: 200,
                  fit: BoxFit.contain,
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'You are about to enter Chub.ai — a land where content '
                'moderation is more of a suggestion than a rule.',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  height: 1.5,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              const Text(
                'You WILL encounter NSFW and potentially NSFL content. '
                'There is no "safe" section. There is no lifeguard on duty. '
                'Eye bleach is strongly advised — and may still not be enough.',
                style: TextStyle(
                  color: Colors.redAccent,
                  fontSize: 13,
                  height: 1.5,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              const Text(
                'Browse at your own discretion. '
                'We are not responsible for what you find... '
                'or what finds you. 👁️',
                style: TextStyle(
                  color: Colors.white60,
                  fontSize: 12,
                  fontStyle: FontStyle.italic,
                  height: 1.5,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text(
              'Nope, I Choose Life',
              style: TextStyle(color: Colors.white70),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              foregroundColor: Colors.white,
            ),
            onPressed: () {
              Navigator.pop(dialogContext);
              _openChubBrowser(context);
            },
            child: const Text('I Fear Nothing. Proceed.'),
          ),
        ],
      ),
    );
  }
}

// Custom InAppBrowser for character downloads
class CharacterBrowser extends InAppBrowser {
  final Future<void> Function(String url) onDownload;

  CharacterBrowser({required this.onDownload});

  @override
  Future<NavigationActionPolicy>? shouldOverrideUrlLoading(
    NavigationAction navigationAction,
  ) async {
    final url = navigationAction.request.url.toString();

    // Intercept character card downloads
    if (url.endsWith('.png') ||
        url.contains('download_card_image=true') ||
        url.contains('/download') ||
        url.contains('characterhub.org/characters/download')) {
      debugPrint('AG_DEBUG: Intercepted download URL: $url');
      await onDownload(url);
      return NavigationActionPolicy.CANCEL;
    }

    return NavigationActionPolicy.ALLOW;
  }

  @override
  void onLoadError(Uri? url, int code, String message) {
    debugPrint('AG_DEBUG: Browser load error: $message');
  }

  @override
  void onExit() {
    debugPrint('AG_DEBUG: Browser closed');
  }
}
