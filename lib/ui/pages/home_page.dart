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
import 'package:path/path.dart' as path;

import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/providers/app_state.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';

// Barrel imports (preferred during major refactor per project guidelines)
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/utils/character_id.dart';
import 'package:front_porch_ai/ui/widgets/widgets.dart';

// Specific pages, dialogs, and internal services not in barrels
import 'package:front_porch_ai/ui/pages/chat_page.dart';
import 'package:front_porch_ai/ui/pages/home/dialogs/session_picker_dialog.dart';
import 'package:front_porch_ai/ui/pages/edit_character_page.dart';
import 'package:front_porch_ai/ui/pages/edit_group_page.dart';
import 'package:front_porch_ai/services/group_card_importer.dart';
import 'package:front_porch_ai/ui/pages/character_creator_page.dart';
import 'package:front_porch_ai/ui/pages/story_home_view.dart';
import 'package:front_porch_ai/ui/dialogs/avatar_gallery/avatar_gallery_controller.dart';
import 'package:front_porch_ai/ui/dialogs/avatar_gallery/avatar_gallery_dialog.dart';
import 'package:front_porch_ai/ui/dialogs/byaf_import_dialog.dart';
import 'package:front_porch_ai/ui/dialogs/import_name_collision_dialog.dart';
import 'package:front_porch_ai/ui/dialogs/tag_dialog.dart';
import 'package:front_porch_ai/ui/dialogs/type_delete_dialog.dart';
import 'package:front_porch_ai/services/byaf_service.dart';
import 'package:front_porch_ai/utils/picker_prefs.dart';

// _HomePageState is split across these part files (each a private extension on
// the State) to keep every file under the 500-line cap while preserving full
// access to page state. Lifecycle + build() stay here.
part 'home/home_page_chrome.dart';
part 'home/home_page_handlers.dart';
part 'home/home_page_dialogs.dart';
part 'home/home_page_char_ops.dart';
part 'home/home_page_transfer.dart';

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

  // Multi-select mode (used for organizing into folders, bulk actions, etc.)
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

  /// setState is @protected, and the analyzer doesn't treat the extension
  /// methods in the home_page_*.dart part files as instance members of this
  /// State subclass — so those parts rebuild through this wrapper instead.
  void applyState(VoidCallback fn) => setState(fn);

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

  /// The file to show as [c]'s library card cover: the ★ starred gallery
  /// avatar when set (same star-aware resolution the web library and card
  /// exports already use — the gallery dialog promises "★ sets the default +
  /// card cover"), else the portrait.
  File _resolveCharImage(CharacterCard c) {
    final repo = Provider.of<CharacterRepository>(context, listen: false);
    final cover = repo.coverImageFileFor(c);
    if (cover != null) return cover;
    final storage = Provider.of<StorageService>(context, listen: false);
    return storage.resolveCharacterImage(c.imagePath ?? '');
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
                Icon(
                  Icons.check_circle,
                  color: AppColors.verifiedAccentOf(context),
                  size: 20,
                ),
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
  ///
  /// Keys in the output maps are always the stableGroupId (image basename or sanitized name)
  /// so they match what the grid and sort logic use via CharacterCard.stableGroupId.
  ///
  /// We correlate via each library card's dbId because 1:1 sessions currently store the
  /// integer dbId in sessions.character_id (post group overhaul). Group sessions (with
  /// groupId set, character_id often null) do not contribute here — this is by design
  /// for the decoupled model (group activity lives with the private group members).
  Future<void> _refreshLastActivityCache() async {
    try {
      final db = await AppDatabase.instance();
      final charRepo = Provider.of<CharacterRepository>(context, listen: false);

      // Get counts and activity from DB (keys are whatever was stored in sessions.character_id,
      // currently the dbId for 1:1 sessions).
      final msgCounts = await db.getMessageCountsPerCharacter();
      final lastActivity = await db.getLastActivityPerCharacter();

      // Output maps MUST be keyed by stableGroupId (the value used for all lookups
      // in the grid for chips + 'recent'/'messages' sorting).
      final newMsgCount = <String, int>{};
      final newCache = <String, DateTime>{};

      for (final card in charRepo.characters) {
        final stableId = card.stableGroupId;
        if (card.dbId != null) {
          final dbKey =
              card.dbId!; // matches what is stored in sessions for 1:1
          if (msgCounts.containsKey(dbKey)) {
            newMsgCount[stableId] = msgCounts[dbKey]!;
          }
          if (lastActivity.containsKey(dbKey)) {
            newCache[stableId] = lastActivity[dbKey]!;
          }
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

  /// Delegates to the canonical stable group ID.
  /// See [StableGroupId.stableGroupId] in lib/utils/character_id.dart
  String _getCharacterIdFromCard(CharacterCard card) => card.stableGroupId;

  /// Legacy alias — prefer _getCharacterIdFromCard for new code.
  @Deprecated('Use _getCharacterIdFromCard for stable group ID resolution')
  String getStableCharacterId(CharacterCard card) => card.stableGroupId;

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
        : character.name
              .replaceAll(RegExp(r'[^\w\s]'), '')
              .replaceAll(' ', '_');
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
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    color: Theme.of(
                      context,
                    ).textTheme.titleLarge?.color?.withValues(alpha: 0.7),
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
                        backgroundColor: AppColors.porchAmberOf(context),
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
            onAcceptFolderDrop: _handleAcceptFolderDrop,
            onFolderDialogAction: _handleFolderDialogAction,
            onFolderTap: _handleFolderTap,
            onFolderNavigateBack: _handleFolderNavigateBack,
            onCancelSelection: _cancelSelection,
            onDeleteSelected: _massDeleteSelected,
            // onCreateGroup no longer wired — old select-for-group path deprecated.
            onMoveToFolder: _handleMoveToFolder,
            onSortChanged: _handleSortChanged,
            onGridScaleChanged: _handleGridScaleChanged,
            onGridScaleChangeEnd: _handleGridScaleChangeEnd,
            onSearchScopeChanged: _handleSearchScopeChanged,
            onSearchQueryChanged: _handleSearchQueryChanged,
            onResolveCharImage: _resolveCharImage,
            onDeleteGroup: _handleDeleteGroup,
            onAfterNavigateBack: _refreshLastActivityCache,
            onGroupContextMenuAction: _handleGroupContextMenuAction,
          ),
        );
      },
    );
  }
}
