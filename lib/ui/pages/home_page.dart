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

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  String _searchQuery = '';
  String? _activeFolderId; // null = top level view
  List<String> _folderStack = []; // navigation breadcrumb for subfolder back
  bool _searchAll =
      false; // when true, search spans all characters even in a folder
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
    // Load persisted sort preference
    final storage = Provider.of<StorageService>(context, listen: false);
    _sortMode = storage.sortMode;
    _gridScale = storage.gridScale;
    // Defer cache refresh to after characters load to avoid race condition
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
            backgroundColor: const Color(0xFF2A2A2A),
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

  void _toggleSelect(CharacterCard character) {
    final id = _getCharacterIdFromCard(character);
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
                  ).textTheme.titleLarge?.copyWith(color: Colors.white70),
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

        // Filter characters based on search and active folder
        final filteredCharacters = _getFilteredCharacters(repo, folderService);

        return _wrapWithStatusBar(
          context,
          Stack(
            children: [
              Column(
                children: [
                  // Header row
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24.0,
                      vertical: 16.0,
                    ),
                    child: Row(
                      children: [
                        if (_isSelecting || _isOrganizing) ...[
                          IconButton(
                            icon: const Icon(Icons.close),
                            tooltip: 'Cancel selection',
                            onPressed: _cancelSelection,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '${_selectedCharacterIds.length} selected',
                            style: Theme.of(context).textTheme.headlineSmall
                                ?.copyWith(
                                  fontWeight: FontWeight.bold,
                                  color: _isOrganizing
                                      ? Colors.blueAccent
                                      : Colors.purpleAccent,
                                ),
                          ),
                        ] else if (_activeFolderId != null) ...[
                          IconButton(
                            icon: const Icon(Icons.arrow_back),
                            tooltip: 'Back to all characters',
                            onPressed: () => setState(() {
                              if (_folderStack.isNotEmpty) {
                                _activeFolderId = _folderStack.removeLast();
                              } else {
                                _activeFolderId = null;
                              }
                              _searchAll = false;
                            }),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            _getActiveFolderName(folderService),
                            style: Theme.of(context).textTheme.headlineSmall
                                ?.copyWith(fontWeight: FontWeight.bold),
                          ),
                        ] else
                          _buildModeToggle(),
                        const SizedBox(width: 16),
                        // Sort dropdown
                        if (!_isSelecting && !_isOrganizing)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFF1E293B),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.white12),
                            ),
                            child: DropdownButtonHideUnderline(
                              child: DropdownButton<String>(
                                value: _sortMode,
                                icon: const Icon(
                                  Icons.sort,
                                  size: 18,
                                  color: Colors.white54,
                                ),
                                dropdownColor: const Color(0xFF1E293B),
                                style: const TextStyle(
                                  color: Colors.white70,
                                  fontSize: 13,
                                ),
                                isDense: true,
                                items: const [
                                  DropdownMenuItem(
                                    value: 'name',
                                    child: Text('Name (A→Z)'),
                                  ),
                                  DropdownMenuItem(
                                    value: 'recent',
                                    child: Text('Recent Activity'),
                                  ),
                                  DropdownMenuItem(
                                    value: 'importDate',
                                    child: Text('Import Date'),
                                  ),
                                  DropdownMenuItem(
                                    value: 'messages',
                                    child: Text('Messages Sent'),
                                  ),
                                ],
                                onChanged: (value) {
                                  if (value != null) {
                                    setState(() => _sortMode = value);
                                    Provider.of<StorageService>(
                                      context,
                                      listen: false,
                                    ).setSortMode(value);
                                  }
                                },
                              ),
                            ),
                          ),
                        // Grid scale slider
                        if (!_isSelecting && !_isOrganizing)
                          SizedBox(
                            width: 120,
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.grid_view,
                                  size: 16,
                                  color: Colors.white38,
                                ),
                                Expanded(
                                  child: SliderTheme(
                                    data: SliderThemeData(
                                      trackHeight: 3,
                                      thumbShape: const RoundSliderThumbShape(
                                        enabledThumbRadius: 6,
                                      ),
                                      overlayShape:
                                          const RoundSliderOverlayShape(
                                            overlayRadius: 12,
                                          ),
                                      activeTrackColor: Colors.blueAccent
                                          .withValues(alpha: 0.7),
                                      inactiveTrackColor: Colors.white12,
                                      thumbColor: Colors.blueAccent,
                                    ),
                                    child: Slider(
                                      value: _gridScale,
                                      min: 150,
                                      max: 450,
                                      onChanged: (v) =>
                                          setState(() => _gridScale = v),
                                      onChangeEnd: (v) {
                                        Provider.of<StorageService>(
                                          context,
                                          listen: false,
                                        ).setGridScale(v);
                                      },
                                    ),
                                  ),
                                ),
                                const Icon(
                                  Icons.view_module,
                                  size: 16,
                                  color: Colors.white38,
                                ),
                              ],
                            ),
                          ),
                        const Spacer(),
                        if (!_isSelecting && !_isOrganizing) ...[
                          IconButton(
                            tooltip: 'Select characters for group chat',
                            icon: const Icon(
                              Icons.group_add,
                              color: Colors.purpleAccent,
                            ),
                            onPressed: () =>
                                setState(() => _isSelecting = true),
                          ),
                          IconButton(
                            tooltip: 'Organize into folders',
                            icon: const Icon(
                              Icons.drive_file_move_outlined,
                              color: Colors.blueAccent,
                            ),
                            onPressed: () =>
                                setState(() => _isOrganizing = true),
                          ),
                          if (_activeFolderId == null)
                            IconButton(
                              tooltip: 'New Folder',
                              icon: const Icon(
                                Icons.create_new_folder_outlined,
                              ),
                              onPressed: () =>
                                  _createFolder(context, folderService),
                            ),
                          if (_activeFolderId != null)
                            IconButton(
                              tooltip: 'New Subfolder',
                              icon: const Icon(
                                Icons.create_new_folder_outlined,
                                color: Colors.amberAccent,
                              ),
                              onPressed: () => _createFolder(
                                context,
                                folderService,
                                parentId: _activeFolderId,
                              ),
                            ),
                          PopupMenuButton<String>(
                            tooltip: 'Import Characters',
                            icon: const Icon(Icons.download),
                            onSelected: (value) {
                              if (value == 'cards') _importCharacter(context);
                              if (value == 'folder')
                                _folderImportCharacters(context);
                              if (value == 'byaf') _importByaf(context);
                            },
                            itemBuilder: (_) => [
                              const PopupMenuItem(
                                value: 'cards',
                                child: ListTile(
                                  leading: Icon(Icons.download),
                                  title: Text('Import Cards'),
                                  dense: true,
                                ),
                              ),
                              const PopupMenuItem(
                                value: 'folder',
                                child: ListTile(
                                  leading: Icon(Icons.library_add),
                                  title: Text('Import Folder'),
                                  dense: true,
                                ),
                              ),
                              const PopupMenuItem(
                                value: 'byaf',
                                child: ListTile(
                                  leading: Icon(Icons.archive_outlined),
                                  title: Text('Import Backyard AI (.byaf)'),
                                  dense: true,
                                ),
                              ),
                            ],
                          ),
                           IconButton(
                            tooltip: 'Browse AI Character Cards',
                            icon: const Icon(
                              Icons.public,
                              color: Colors.blueAccent,
                            ),
                            onPressed: () => _openBrowser(context),
                          ),
                          IconButton(
                            tooltip: 'Chub.ai (Caution)',
                            icon: const Icon(
                              Icons.warning_amber_rounded,
                              color: Colors.redAccent,
                            ),
                            onPressed: () => _showChubWarning(context),
                          ),
                        ],
                      ],
                    ),
                  ),

                  // Search bar
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24.0),
                    child: TextField(
                      controller: _searchController,
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        hintText: _activeFolderId != null && !_searchAll
                            ? 'Search this folder...'
                            : 'Search by name or tag...',
                        hintStyle: const TextStyle(color: Colors.white38),
                        prefixIcon: _activeFolderId != null
                            ? PopupMenuButton<bool>(
                                icon: Icon(
                                  _searchAll ? Icons.search : Icons.folder_open,
                                  color: _searchAll
                                      ? Colors.blueAccent
                                      : Colors.amberAccent,
                                  size: 20,
                                ),
                                tooltip: 'Search scope',
                                color: const Color(0xFF1E293B),
                                onSelected: (val) =>
                                    setState(() => _searchAll = val),
                                itemBuilder: (_) => [
                                  PopupMenuItem(
                                    value: false,
                                    child: Row(
                                      children: [
                                        Icon(
                                          Icons.folder_open,
                                          size: 18,
                                          color: !_searchAll
                                              ? Colors.amberAccent
                                              : Colors.white54,
                                        ),
                                        const SizedBox(width: 8),
                                        Text(
                                          'This Folder',
                                          style: TextStyle(
                                            color: !_searchAll
                                                ? Colors.amberAccent
                                                : Colors.white70,
                                            fontSize: 13,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  PopupMenuItem(
                                    value: true,
                                    child: Row(
                                      children: [
                                        Icon(
                                          Icons.search,
                                          size: 18,
                                          color: _searchAll
                                              ? Colors.blueAccent
                                              : Colors.white54,
                                        ),
                                        const SizedBox(width: 8),
                                        Text(
                                          'All Characters',
                                          style: TextStyle(
                                            color: _searchAll
                                                ? Colors.blueAccent
                                                : Colors.white70,
                                            fontSize: 13,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              )
                            : const Icon(Icons.search, color: Colors.white38),
                        suffixIcon: _searchQuery.isNotEmpty
                            ? IconButton(
                                icon: const Icon(
                                  Icons.clear,
                                  color: Colors.white38,
                                ),
                                onPressed: () {
                                  _searchController.clear();
                                  setState(() => _searchQuery = '');
                                },
                              )
                            : null,
                        filled: true,
                        fillColor: const Color(0xFF1E293B),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          vertical: 12,
                        ),
                      ),
                      onChanged: (value) =>
                          setState(() => _searchQuery = value),
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Grid with folders, groups, and characters
                  Expanded(
                    child: _buildGrid(
                      context,
                      repo,
                      folderService,
                      filteredCharacters,
                      groupRepo,
                    ),
                  ),
                ],
              ),
              // Group chat selection bar (purple)
              if (_isSelecting && _selectedCharacterIds.isNotEmpty)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1F2937),
                      border: const Border(
                        top: BorderSide(color: Colors.white10),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.3),
                          blurRadius: 8,
                          offset: const Offset(0, -2),
                        ),
                      ],
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.group,
                          color: Colors.purpleAccent.withValues(alpha: 0.7),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          '${_selectedCharacterIds.length} selected',
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 14,
                          ),
                        ),
                        const Spacer(),
                        TextButton(
                          onPressed: _cancelSelection,
                          child: const Text(
                            'Cancel',
                            style: TextStyle(color: Colors.white54),
                          ),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton.icon(
                          onPressed: _selectedCharacterIds.length >= 2
                              ? () => _showCreateGroupDialog(context, repo)
                              : null,
                          icon: const Icon(Icons.group_add),
                          label: const Text('Create Group'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.purpleAccent,
                            foregroundColor: Colors.white,
                            disabledBackgroundColor: Colors.white10,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              // Organize selection bar (blue)
              if (_isOrganizing && _selectedCharacterIds.isNotEmpty)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1F2937),
                      border: const Border(
                        top: BorderSide(color: Colors.white10),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.3),
                          blurRadius: 8,
                          offset: const Offset(0, -2),
                        ),
                      ],
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.drive_file_move,
                          color: Colors.blueAccent.withValues(alpha: 0.7),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          '${_selectedCharacterIds.length} selected',
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 14,
                          ),
                        ),
                        const Spacer(),
                        TextButton(
                          onPressed: _cancelSelection,
                          child: const Text(
                            'Cancel',
                            style: TextStyle(color: Colors.white54),
                          ),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton.icon(
                          onPressed: _selectedCharacterIds.isNotEmpty
                              ? () => _showMoveToFolderDialog(
                                  context,
                                  repo,
                                  folderService,
                                )
                              : null,
                          icon: const Icon(Icons.drive_file_move, size: 18),
                          label: const Text('Move to Folder'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.blueAccent,
                            foregroundColor: Colors.white,
                            disabledBackgroundColor: Colors.white10,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  List<CharacterCard> _getFilteredCharacters(
    CharacterRepository repo,
    FolderService folderService,
  ) {
    List<CharacterCard> characters;

    // When _searchAll is true and there's a search query, skip the folder filter
    final skipFolderFilter = _searchAll && _searchQuery.isNotEmpty;
    if (_activeFolderId != null && !skipFolderFilter) {
      // Show only characters in this folder
      final folderFilenames = folderService.getCharactersInFolderRecursive(
        _activeFolderId!,
      );
      // Compare by filename since FolderService stores filenames only
      characters = repo.characters
          .where(
            (c) =>
                c.imagePath != null &&
                folderFilenames.contains(path.basename(c.imagePath!)),
          )
          .toList();
    } else {
      characters = repo.characters.toList();
    }

    // Apply search filter
    if (_searchQuery.isNotEmpty) {
      final query = _searchQuery.toLowerCase();
      characters = characters.where((c) {
        if (c.name.toLowerCase().contains(query)) return true;
        if (c.tags.any((t) => t.toLowerCase().contains(query))) return true;
        return false;
      }).toList();
    }

    // Apply sort
    switch (_sortMode) {
      case 'name':
        characters.sort(
          (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
        );
        break;
      case 'recent':
        characters.sort((a, b) {
          final aId = a.dbId ?? _getCharacterIdFromCard(a);
          final bId = b.dbId ?? _getCharacterIdFromCard(b);
          final aTime = _lastActivityCache[aId] ?? DateTime(1970);
          final bTime = _lastActivityCache[bId] ?? DateTime(1970);
          return bTime.compareTo(aTime); // newest first
        });
        break;
      case 'importDate':
        characters.sort((a, b) {
          final aEpoch = _extractImportEpoch(a);
          final bEpoch = _extractImportEpoch(b);
          return bEpoch.compareTo(aEpoch); // newest first
        });
        break;
    }
    if (_sortMode == 'messages') {
      characters.sort((a, b) {
        final aId = a.dbId ?? _getCharacterIdFromCard(a);
        final bId = b.dbId ?? _getCharacterIdFromCard(b);
        final aCount = _messageCountCache[aId] ?? 0;
        final bCount = _messageCountCache[bId] ?? 0;
        return bCount.compareTo(aCount); // most messages first
      });
    }

    return characters;
  }

  /// Extracts the import epoch from a character's PNG filename.
  /// Filenames follow the pattern: `CharName_EPOCH.png`
  int _extractImportEpoch(CharacterCard card) {
    if (card.imagePath == null) return 0;
    final basename = path.basenameWithoutExtension(card.imagePath!);
    final lastUnderscore = basename.lastIndexOf('_');
    if (lastUnderscore == -1) return 0;
    return int.tryParse(basename.substring(lastUnderscore + 1)) ?? 0;
  }

  String _getActiveFolderName(FolderService folderService) {
    if (_activeFolderId == null) return 'My Characters';
    final folder = folderService.folders
        .where((f) => f.id == _activeFolderId)
        .firstOrNull;
    return folder?.name ?? 'Folder';
  }

  Widget _buildGrid(
    BuildContext context,
    CharacterRepository repo,
    FolderService folderService,
    List<CharacterCard> filteredCharacters,
    GroupChatRepository groupRepo,
  ) {
    // Show folders: at top level show top-level folders, inside a folder show subfolders
    final showFolders = _searchQuery.isEmpty;
    final folders = showFolders
        ? folderService.getSubfolders(_activeFolderId)
        : <CharacterFolder>[];

    // Show group cards at top level only
    final groups =
        (_activeFolderId == null &&
            _searchQuery.isEmpty &&
            !_isSelecting &&
            !_isOrganizing)
        ? groupRepo.groups
        : <GroupChat>[];

    // At top level, show unfoldered characters only (unless searching)
    List<CharacterCard> displayCharacters;
    if (showFolders && _activeFolderId == null) {
      final folderedFilenames = folderService.getUnfolderedCharacterPaths();
      displayCharacters = filteredCharacters
          .where(
            (c) =>
                c.imagePath == null ||
                !folderedFilenames.contains(path.basename(c.imagePath!)),
          )
          .toList();
    } else {
      displayCharacters = filteredCharacters;
    }

    final totalItems =
        folders.length + groups.length + displayCharacters.length;
    if (totalItems == 0) {
      return Center(
        child: Text(
          _searchQuery.isNotEmpty
              ? 'No characters match "$_searchQuery"'
              : 'This folder is empty',
          style: const TextStyle(color: Colors.white38, fontSize: 16),
        ),
      );
    }

    return Scrollbar(
      controller: _gridScrollController,
      thumbVisibility: true,
      child: GridView.builder(
        controller: _gridScrollController,
        padding: EdgeInsets.fromLTRB(
          24,
          24,
          24,
          (_isSelecting || _isOrganizing) ? 80 : 24,
        ),
        gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: _gridScale,
          childAspectRatio: 0.7,
          crossAxisSpacing: 24,
          mainAxisSpacing: 24,
        ),
        itemCount: totalItems,
        itemBuilder: (context, index) {
          // Render folder cards first
          if (index < folders.length) {
            return _buildFolderCard(
              context,
              folders[index],
              folderService,
              repo,
            );
          }
          // Then group cards
          final groupOffset = index - folders.length;
          if (groupOffset < groups.length) {
            return _buildGroupCard(context, groups[groupOffset], repo);
          }
          // Then character cards
          final character = displayCharacters[groupOffset - groups.length];
          return _buildCharacterCard(context, character, folderService);
        },
      ),
    );
  }

  Widget _buildFolderCard(
    BuildContext context,
    CharacterFolder folder,
    FolderService folderService,
    CharacterRepository repo,
  ) {
    final charCount = folder.characterPaths.length;

    return DragTarget<CharacterCard>(
      onAcceptWithDetails: (details) async {
        await folderService.addToFolder(folder.id, details.data.imagePath!);
      },
      builder: (context, candidateData, rejectedData) {
        final isHovering = candidateData.isNotEmpty;
        return Card(
          color: isHovering
              ? Colors.amber.shade900.withValues(alpha: 0.4)
              : const Color(0xFF1E293B),
          clipBehavior: Clip.antiAlias,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(
              color: isHovering
                  ? Colors.amber
                  : Colors.white.withValues(alpha: 0.1),
              width: isHovering ? 2 : 1,
            ),
          ),
          child: InkWell(
            onTap: () => setState(() {
              if (_activeFolderId != null) {
                _folderStack.add(_activeFolderId!);
              }
              _activeFolderId = folder.id;
            }),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final isSmall = constraints.maxHeight < 200;
                final isTiny = constraints.maxHeight < 140;
                final iconSize = isTiny ? 32.0 : (isSmall ? 48.0 : 72.0);
                final fontSize = isTiny ? 11.0 : (isSmall ? 13.0 : 16.0);

                return Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.folder,
                      size: iconSize,
                      color: isHovering ? Colors.amber : Colors.amber.shade700,
                    ),
                    SizedBox(height: isTiny ? 4 : (isSmall ? 8 : 16)),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Text(
                        folder.name,
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: fontSize,
                        ),
                        textAlign: TextAlign.center,
                        maxLines: isTiny ? 1 : 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (!isTiny) ...[
                      SizedBox(height: isSmall ? 4 : 8),
                      Text(
                        '$charCount character${charCount == 1 ? '' : 's'}',
                        style: TextStyle(
                          color: Colors.white54,
                          fontSize: isSmall ? 11 : 13,
                        ),
                      ),
                    ],
                    if (!isSmall) ...[
                      const SizedBox(height: 16),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(
                              Icons.edit,
                              color: Colors.white54,
                              size: 18,
                            ),
                            tooltip: 'Rename',
                            onPressed: () =>
                                _renameFolder(context, folder, folderService),
                          ),
                          IconButton(
                            icon: const Icon(
                              Icons.delete,
                              color: Colors.redAccent,
                              size: 18,
                            ),
                            tooltip: 'Delete folder',
                            onPressed: () =>
                                _deleteFolder(context, folder, folderService),
                          ),
                        ],
                      ),
                    ],
                  ],
                );
              },
            ),
          ),
        );
      },
    );
  }

  /// Wraps content with an optional model-loading status bar at the bottom.
  Widget _buildModeToggle() {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white10),
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
              ? Colors.amber.shade800.withValues(alpha: 0.25)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          border: isActive
              ? Border.all(color: Colors.amber.shade700.withValues(alpha: 0.5))
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 18,
              color: isActive ? Colors.amber.shade400 : Colors.white38,
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                color: isActive ? Colors.white : Colors.white54,
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
            color: const Color(0xFF1E1E1E),
            border: Border(top: BorderSide(color: Colors.white12)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                status,
                style: const TextStyle(color: Colors.white70, fontSize: 13),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 6),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: const LinearProgressIndicator(
                  minHeight: 4,
                  backgroundColor: Color(0xFF333333),
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.greenAccent),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildCharacterCard(
    BuildContext context,
    CharacterCard character,
    FolderService folderService,
  ) {
    return LongPressDraggable<CharacterCard>(
      data: character,
      feedback: Material(
        color: Colors.transparent,
        child: SizedBox(
          width: 150,
          height: 200,
          child: Card(
            color: const Color(0xFF1E293B),
            clipBehavior: Clip.antiAlias,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            child: character.imagePath != null
                ? Image.file(
                    _resolveCharImage(character.imagePath!),
                    fit: BoxFit.cover,
                    alignment: Alignment.topCenter,
                  )
                : const Icon(Icons.person, size: 64, color: Colors.white24),
          ),
        ),
      ),
      childWhenDragging: Opacity(
        opacity: 0.3,
        child: _buildCharacterCardInner(context, character, folderService),
      ),
      child: _buildCharacterCardInner(context, character, folderService),
    );
  }

  Widget _buildCharacterCardInner(
    BuildContext context,
    CharacterCard character,
    FolderService folderService,
  ) {
    final charId = character.dbId ?? _getCharacterIdFromCard(character);
    final msgCount = _messageCountCache[charId] ?? 0;
    final isSelected = _selectedCharacterIds.contains(charId);

    return Card(
      color: Theme.of(context).cardColor,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: isSelected
              ? Colors.purpleAccent
              : Theme.of(context).dividerColor.withValues(alpha: 0.1),
          width: isSelected ? 2.5 : 1,
        ),
      ),
      child: Stack(
        children: [
          InkWell(
            onTap: () async {
              if (_isSelecting || _isOrganizing) {
                _toggleSelect(character);
                return;
              }
              final chatService = Provider.of<ChatService>(
                context,
                listen: false,
              );
              final charId = _getCharacterIdFromCard(character);
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
                await Navigator.of(
                  context,
                ).push(MaterialPageRoute(builder: (_) => const ChatPage()));
                _refreshLastActivityCache();
              }
            },
            child: LayoutBuilder(
              builder: (context, constraints) {
                final isCompact = constraints.maxWidth < 200;
                final isTiny = constraints.maxWidth < 160;

                if (isTiny) {
                  // Very small: image only with name overlay
                  return Stack(
                    fit: StackFit.expand,
                    children: [
                      character.imagePath != null
                          ? Image.file(
                              _resolveCharImage(character.imagePath!),
                              fit: BoxFit.cover,
                              alignment: Alignment.topCenter,
                            )
                          : Container(
                              color: Colors.grey.shade800,
                              child: const Icon(
                                Icons.person,
                                size: 32,
                                color: Colors.white24,
                              ),
                            ),
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 0,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.bottomCenter,
                              end: Alignment.topCenter,
                              colors: [Colors.black87, Colors.transparent],
                            ),
                          ),
                          child: Text(
                            character.name,
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                    ],
                  );
                }

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      flex: isCompact ? 4 : 3,
                      child: character.imagePath != null
                          ? Image.file(
                              _resolveCharImage(character.imagePath!),
                              fit: BoxFit.cover,
                              alignment: Alignment.topCenter,
                            )
                          : Container(
                              color: Colors.grey.shade800,
                              child: Icon(
                                Icons.person,
                                size: isCompact ? 32 : 64,
                                color: Colors.white24,
                              ),
                            ),
                    ),
                    Expanded(
                      flex: 1,
                      child: Padding(
                        padding: EdgeInsets.all(isCompact ? 6.0 : 12.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    character.name,
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleMedium
                                        ?.copyWith(
                                          fontWeight: FontWeight.bold,
                                          fontSize: isCompact ? 12 : null,
                                        ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                if (msgCount > 0)
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        Icons.chat_bubble_outline,
                                        size: 11,
                                        color: Colors.white38,
                                      ),
                                      const SizedBox(width: 3),
                                      Text(
                                        '$msgCount',
                                        style: TextStyle(
                                          color: Colors.white38,
                                          fontSize: isCompact ? 10 : 11,
                                        ),
                                      ),
                                    ],
                                  ),
                              ],
                            ),
                            if (!isCompact) ...[
                              const SizedBox(height: 4),
                              // Tag chips (show first 3 tags)
                              if (character.tags.isNotEmpty)
                                Flexible(
                                  child: Wrap(
                                    spacing: 4,
                                    runSpacing: 2,
                                    children: character.tags
                                        .take(3)
                                        .map(
                                          (tag) => Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 6,
                                              vertical: 2,
                                            ),
                                            decoration: BoxDecoration(
                                              color: Colors.amber.shade900
                                                  .withValues(alpha: 0.3),
                                              borderRadius:
                                                  BorderRadius.circular(4),
                                            ),
                                            child: Text(
                                              tag,
                                              style: TextStyle(
                                                color: Colors.amber.shade300,
                                                fontSize: 10,
                                              ),
                                            ),
                                          ),
                                        )
                                        .toList(),
                                  ),
                                )
                              else
                                Flexible(
                                  child: Text(
                                    character.formattedDescription,
                                    style: Theme.of(
                                      context,
                                    ).textTheme.bodySmall,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),

          // Selection checkbox overlay
          if (_isSelecting || _isOrganizing)
            Positioned(
              top: 8,
              left: 8,
              child: Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: isSelected
                      ? (_isOrganizing
                            ? Colors.blueAccent
                            : Colors.purpleAccent)
                      : Colors.black54,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: isSelected
                        ? (_isOrganizing
                              ? Colors.blueAccent
                              : Colors.purpleAccent)
                        : Colors.white38,
                    width: 2,
                  ),
                ),
                child: isSelected
                    ? const Icon(Icons.check, size: 16, color: Colors.white)
                    : null,
              ),
            ),
          // Right-click context menu for actions (replaces overlay buttons)
          if (!_isSelecting && !_isOrganizing)
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onSecondaryTapUp: (details) {
                  final position = details.globalPosition;
                  showMenu<String>(
                    context: context,
                    position: RelativeRect.fromLTRB(
                      position.dx,
                      position.dy,
                      position.dx,
                      position.dy,
                    ),
                    color: const Color(0xFF2A2A2A),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    items: [
                      const PopupMenuItem(
                        value: 'edit',
                        child: ListTile(
                          leading: Icon(
                            Icons.edit,
                            color: Colors.white70,
                            size: 20,
                          ),
                          title: Text(
                            'Edit Character',
                            style: TextStyle(color: Colors.white),
                          ),
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
                      const PopupMenuItem(
                        value: 'duplicate',
                        child: ListTile(
                          leading: Icon(
                            Icons.copy,
                            color: Colors.white70,
                            size: 20,
                          ),
                          title: Text(
                            'Duplicate Character',
                            style: TextStyle(color: Colors.white),
                          ),
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
                      const PopupMenuItem(
                        value: 'export',
                        child: ListTile(
                          leading: Icon(
                            Icons.upload,
                            color: Colors.white70,
                            size: 20,
                          ),
                          title: Text(
                            'Export PNG',
                            style: TextStyle(color: Colors.white),
                          ),
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
                      if (_activeFolderId != null)
                        const PopupMenuItem(
                          value: 'remove_folder',
                          child: ListTile(
                            leading: Icon(
                              Icons.folder_off,
                              color: Colors.amber,
                              size: 20,
                            ),
                            title: Text(
                              'Remove from Folder',
                              style: TextStyle(color: Colors.amber),
                            ),
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                          ),
                        ),
                      const PopupMenuItem(
                        value: 'delete',
                        child: ListTile(
                          leading: Icon(
                            Icons.delete,
                            color: Colors.redAccent,
                            size: 20,
                          ),
                          title: Text(
                            'Delete',
                            style: TextStyle(color: Colors.redAccent),
                          ),
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
                    ],
                  ).then((value) {
                    if (value == null) return;
                    switch (value) {
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
                        folderService.removeFromFolder(
                          _activeFolderId!,
                          character.imagePath!,
                        );
                        break;
                      case 'delete':
                        _confirmDeleteCharacter(context, character);
                        break;
                    }
                  });
                },
                child: const SizedBox.shrink(),
              ),
            ),
        ],
      ),
    );
  }

  // ─── Group Card ─────────────────────────────────────────────────

  Widget _buildGroupCard(
    BuildContext context,
    GroupChat group,
    CharacterRepository repo,
  ) {
    // Resolve character cards for the group
    final characters = <CharacterCard>[];
    for (final id in group.characterIds) {
      final match = repo.characters
          .where((c) => _getCharacterIdFromCard(c) == id)
          .firstOrNull;
      if (match != null) characters.add(match);
    }

    return Card(
      color: const Color(0xFF1E293B),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.purpleAccent.withValues(alpha: 0.3)),
      ),
      child: InkWell(
        onTap: () async {
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
            await Navigator.of(
              context,
            ).push(MaterialPageRoute(builder: (_) => const ChatPage()));
            _refreshLastActivityCache();
          }
        },
        child: Stack(
          children: [
            LayoutBuilder(
              builder: (context, constraints) {
                final h = constraints.maxHeight;
                final isCompact = h < 220;
                final avatarSize = isCompact ? 40.0 : 56.0;
                final avatarAreaH = isCompact ? 50.0 : 80.0;
                final overlapStep = isCompact ? 22.0 : 30.0;
                final nameFontSize = isCompact ? 12.0 : 16.0;
                final subFontSize = isCompact ? 10.0 : 13.0;
                final badgeFontSize = isCompact ? 9.0 : 11.0;
                final iconSize = isCompact ? 16.0 : 20.0;

                return Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(height: isCompact ? 8 : 16),
                    // Stacked avatars
                    SizedBox(
                      height: avatarAreaH,
                      width: double.infinity,
                      child: Center(
                        child: SizedBox(
                          width:
                              avatarSize +
                              (characters.take(4).length - 1) * overlapStep,
                          height: avatarAreaH,
                          child: Stack(
                            children: [
                              for (
                                int i = 0;
                                i < characters.take(4).length;
                                i++
                              )
                                Positioned(
                                  left: i * overlapStep,
                                  child: Container(
                                    width: avatarSize,
                                    height: avatarSize,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                        color: Colors.purpleAccent,
                                        width: 2,
                                      ),
                                      image: characters[i].imagePath != null
                                          ? DecorationImage(
                                              image: FileImage(
                                                _resolveCharImage(
                                                  characters[i].imagePath!,
                                                ),
                                              ),
                                              fit: BoxFit.cover,
                                              alignment: Alignment.topCenter,
                                            )
                                          : null,
                                      color: characters[i].imagePath == null
                                          ? Colors.grey.shade700
                                          : null,
                                    ),
                                    child: characters[i].imagePath == null
                                        ? Icon(
                                            Icons.person,
                                            color: Colors.white24,
                                            size: avatarSize * 0.5,
                                          )
                                        : null,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    SizedBox(height: isCompact ? 4 : 16),
                    // Group icon badge
                    Icon(
                      Icons.group,
                      color: Colors.purpleAccent,
                      size: iconSize,
                    ),
                    SizedBox(height: isCompact ? 2 : 8),
                    Flexible(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        child: Text(
                          group.name,
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: nameFontSize,
                          ),
                          textAlign: TextAlign.center,
                          maxLines: isCompact ? 1 : 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                    if (!isCompact) ...[
                      const SizedBox(height: 4),
                      Text(
                        '${characters.length} character${characters.length == 1 ? '' : 's'}',
                        style: TextStyle(
                          color: Colors.white54,
                          fontSize: subFontSize,
                        ),
                      ),
                    ],
                    SizedBox(height: isCompact ? 2 : 4),
                    // Turn order label
                    Container(
                      padding: EdgeInsets.symmetric(
                        horizontal: isCompact ? 4 : 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.purpleAccent.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        group.turnOrder == TurnOrder.roundRobin
                            ? 'Round Robin'
                            : 'Random',
                        style: TextStyle(
                          color: Colors.purpleAccent.withValues(alpha: 0.8),
                          fontSize: badgeFontSize,
                        ),
                      ),
                    ),
                    SizedBox(height: isCompact ? 4 : 0),
                  ],
                );
              },
            ),
            // Delete group button
            Positioned(
              top: 8,
              right: 8,
              child: Material(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(20),
                child: InkWell(
                  borderRadius: BorderRadius.circular(20),
                  onTap: () => _confirmDeleteGroup(context, group),
                  child: const Padding(
                    padding: EdgeInsets.all(8.0),
                    child: Icon(
                      Icons.delete,
                      color: Colors.redAccent,
                      size: 18,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
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
        backgroundColor: const Color(0xFF1F2937),
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
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
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
                    side: const BorderSide(color: Colors.greenAccent),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              const Divider(color: Colors.white10),
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
                      color: const Color(0xFF374151),
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
                            : const Icon(
                                Icons.chat,
                                size: 20,
                                color: Colors.white38,
                              ),
                        title: Text(
                          s['preview'],
                          style: const TextStyle(
                            fontSize: 13,
                            color: Colors.white,
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
                              style: const TextStyle(
                                fontSize: 11,
                                color: Colors.white54,
                              ),
                            ),
                            if (description != null && description.isNotEmpty) ...[
                              const SizedBox(height: 4),
                              Text(
                                description,
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: Colors.white38,
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
                                      Icon(Icons.forum, size: 10, color: Colors.blueAccent.shade100),
                                      const SizedBox(width: 4),
                                      Text(
                                        '$messageCount total',
                                        style: TextStyle(fontSize: 10, color: Colors.blueAccent.shade100, fontWeight: FontWeight.w500),
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
                                        Icon(Icons.person, size: 10, color: Colors.greenAccent.shade100),
                                        const SizedBox(width: 4),
                                        Text(
                                          '$userMessageCount user',
                                          style: TextStyle(fontSize: 10, color: Colors.greenAccent.shade100, fontWeight: FontWeight.w500),
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
                                style: const TextStyle(
                                  fontSize: 10,
                                  color: Colors.blueAccent,
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
            child: const Text(
              'Cancel',
              style: TextStyle(color: Colors.white54),
            ),
          ),
        ],
      ),
    );
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
    final folders = folderService.folders;

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
              ...folders.map(
                (folder) => ListTile(
                  leading: const Icon(Icons.folder, color: Colors.amberAccent),
                  title: Text(
                    folder.name,
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
                ),
              ),
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
    final systemPromptController = TextEditingController(
      text: ChatService.defaultGroupSystemPrompt,
    );
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
                                    backgroundImage: FileImage(
                                      _resolveCharImage(c.imagePath!),
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
                    activeColor: Colors.purpleAccent,
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
                      // Auto-generate scenario, first message, and set director prompt
                      if (val) {
                        systemPromptController.text =
                            ChatService.observerModeSystemPrompt;
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
                            if (result.isNotEmpty)
                              scenarioController.text = result;
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
                              if (marker >= 0)
                                result = result.substring(
                                  marker + 'BEGIN SCENE:'.length,
                                );
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
                              if (cleaned.isNotEmpty)
                                firstMessageController.text = cleaned;
                            } catch (_) {}
                            setDialogState(
                              () => isGeneratingFirstMessage = false,
                            );
                          }
                        }
                      } else {
                        // Revert to default group prompt
                        systemPromptController.text =
                            ChatService.defaultGroupSystemPrompt;
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
                    activeColor: Colors.amberAccent,
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
                                    backgroundImage: FileImage(
                                      _resolveCharImage(c.imagePath!),
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
      backgroundColor: Colors.white.withValues(alpha: 0.1),
      foregroundColor: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: Colors.white24),
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
        result.files.first.path == null)
      return;
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
