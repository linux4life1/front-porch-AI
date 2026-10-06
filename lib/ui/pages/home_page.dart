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

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:path/path.dart' as path;

import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/providers/app_state.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';
import 'package:front_porch_ai/ui/theme/studio_colors.dart';

// Barrel imports (preferred during major refactor per project guidelines)
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/utils/utils.dart';
import 'package:front_porch_ai/ui/widgets/widgets.dart';

// Specific pages, dialogs, and internal services not in barrels
import 'package:front_porch_ai/ui/pages/chat_page.dart';
import 'package:front_porch_ai/ui/pages/home/dialogs/session_picker_dialog.dart';
import 'package:front_porch_ai/ui/pages/home/enhance/enhance_wizard_page.dart';
import 'package:front_porch_ai/ui/pages/home/cards/library_drag_payload.dart';
import 'package:front_porch_ai/ui/pages/home/home_drop_zone.dart';
import 'package:front_porch_ai/ui/pages/home/library_import_picks.dart';
import 'package:front_porch_ai/ui/pages/home/library_selection.dart';
import 'package:front_porch_ai/ui/pages/home/widgets/home_mode_toggle.dart';
import 'package:front_porch_ai/ui/pages/home/open_chat_env.dart';
import 'package:front_porch_ai/ui/pages/edit_character_page.dart';
import 'package:front_porch_ai/ui/pages/edit_group_page.dart';
import 'package:front_porch_ai/services/group_card_importer.dart';
import 'package:front_porch_ai/services/porch/porch.dart';
import 'package:front_porch_ai/ui/pages/character_creator_page.dart';
import 'package:front_porch_ai/ui/pages/story_home_view.dart';
import 'package:front_porch_ai/ui/waifu/waifu.dart';
import 'package:front_porch_ai/ui/dialogs/avatar_gallery/avatar_gallery_controller.dart';
import 'package:front_porch_ai/ui/dialogs/avatar_gallery/avatar_gallery_dialog.dart';
import 'package:front_porch_ai/ui/dialogs/dialogs.dart';

// State is split across part files (private extensions) to stay under 500.
part 'home/home_page_chrome.dart';
part 'home/home_page_chrome.actions.dart';
part 'home/home_page_library_actions.dart';
part 'home/home_page_handlers.dart';
part 'home/home_page_move.dart';
part 'home/home_page_dialogs.dart';
part 'home/home_page_dialogs.import.dart';
part 'home/home_page_drop.dart';
part 'home/home_page_char_ops.dart';
part 'home/home_page_transfer.dart';
part 'home/home_page_porch.dart';
part 'home/home_page_history.dart';
part 'home/home_page_lifecycle.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  String _searchQuery = '';
  String? _activeFolderId; // null = top level view
  // The top level and folders remember separate search scopes (#346): they
  // offer different choices, and the top level defaults to Everywhere.
  SearchScope _topSearchScope = SearchScope.allCharacters;
  SearchScope _folderSearchScope = SearchScope.currentFolder;
  SearchScope get _searchScope =>
      _activeFolderId == null ? _topSearchScope : _folderSearchScope;
  final _searchController = TextEditingController();

  // Multi-select / Organize into folders: mode, picks, Shift anchor, drag.
  final LibrarySelection _selection = LibrarySelection();

  // Sorting
  String _sortMode = 'name'; // 'name', 'recent', 'importDate', 'messages'
  final Map<String, DateTime> _lastActivityCache = {};
  final Map<String, int> _messageCountCache = {};

  // Grid scale
  double _gridScale = 300.0;

  // Chats / Porch Stories / Waifu Coder
  HomeMode _homeMode = HomeMode.chats;

  /// Blocks stacked open-chat taps while setActiveCharacter / loadSession
  /// runs (can take seconds). Without this, multi-tap after exit→reenter
  /// races dispose and throws "State no longer has a context".
  bool _openingChat = false;

  /// `--dart-define=OPEN_CHAT=Flora` opens that 1:1 card once per process.
  /// Empty define is a no-op. Static so a Home remount cannot re-fire.
  static bool _openChatEnvConsumed = false;

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
    _readViewPrefs(storage);
    // StorageService._init() is async — settings may not be loaded yet.
    // Wait for init to complete so persisted values are reflected.
    storage.initialized.then((_) {
      if (!mounted) return;
      setState(() => _readViewPrefs(storage));
    });
    _selection.addListener(_onSelectionChanged);
    Future.microtask(() => _refreshLastActivityCache());
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _maybeOpenChatFromEnv(),
    );
  }

  void _readViewPrefs(StorageService storage) {
    final prefs = storage.uiSettings;
    final scopes = SearchScope.values.asNameMap();
    _sortMode = prefs.sortMode;
    _gridScale = prefs.gridScale;
    _topSearchScope = scopes[prefs.topSearchScope] ?? SearchScope.allCharacters;
    _folderSearchScope =
        scopes[prefs.folderSearchScope] ?? SearchScope.currentFolder;
  }

  // The notifiers we subscribed to, held so dispose() can unsubscribe: they
  // are app-scoped providers, MainLayout swaps HomePage out of the tree on
  // every sidebar navigation, and a Provider.of lookup is no longer legal
  // once the element is defunct — so the reference has to be captured here.
  KoboldService? _koboldListened;
  CharacterRepository? _charRepoListened;
  AppState? _appStateListened;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Listen for model-ready events from KoboldService
    try {
      final kobold = Provider.of<KoboldService>(context, listen: false);
      _koboldListened?.removeListener(_onKoboldUpdate);
      kobold.removeListener(_onKoboldUpdate);
      kobold.addListener(_onKoboldUpdate);
      _koboldListened = kobold;
    } catch (_) {
      // KoboldService might not be in the provider tree
    }
    // Listen for CharacterRepository changes to refresh cache after characters load
    try {
      final charRepo = Provider.of<CharacterRepository>(context, listen: false);
      _charRepoListened?.removeListener(_onCharactersChanged);
      charRepo.removeListener(_onCharactersChanged);
      charRepo.addListener(_onCharactersChanged);
      _charRepoListened = charRepo;
    } catch (_) {}
    // Re-tapping the sidebar's Home entry bumps AppState.homeResetTick —
    // treat it as "take me back to the main screen" (library top level).
    try {
      final appState = Provider.of<AppState>(context, listen: false);
      _lastHomeResetTick ??= appState.homeResetTick;
      _appStateListened?.removeListener(_onAppStateChanged);
      appState.removeListener(_onAppStateChanged);
      appState.addListener(_onAppStateChanged);
      _appStateListened = appState;
    } catch (_) {}
  }

  int? _lastHomeResetTick;

  Timer? _activityRefreshDebounce;

  @override
  void dispose() {
    _activityRefreshDebounce?.cancel();
    _selection
      ..removeListener(_onSelectionChanged)
      ..dispose();
    _searchController.dispose();
    _gridScrollController.dispose();
    _koboldListened?.removeListener(_onKoboldUpdate);
    _charRepoListened?.removeListener(_onCharactersChanged);
    _appStateListened?.removeListener(_onAppStateChanged);
    // A remounted Home opens on Chats, so the sidebar comes back with it.
    _appStateListened?.setSidebarHidden(false, notify: false);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer3<CharacterRepository, FolderService, GroupChatRepository>(
      builder: (context, repo, folderService, groupRepo, child) {
        if (repo.isLoading) {
          return const Center(child: CircularProgressIndicator());
        }

        // Porch Stories BEFORE the empty-library check: a story needs no
        // characters, so stories mode has to win over the "create your first
        // character" panel. Checked after it, tapping the toggle on a fresh
        // install set stories mode but still fell into the empty branch, so
        // the view never opened.
        if (_homeMode == HomeMode.stories) {
          return _wrapWithStatusBar(
            context,
            Column(
              children: [
                ColoredBox(
                  color: StudioColors.sideOf(context),
                  child: _modeToggleBar(),
                ),
                const Expanded(child: StoryHomeView()),
              ],
            ),
          );
        }

        if (_homeMode == HomeMode.waifu) {
          return _wrapWithStatusBar(
            context,
            Column(
              children: [
                _modeToggleBar(),
                const Expanded(child: WaifuHomeView()),
              ],
            ),
          );
        }

        if (repo.characters.isEmpty && groupRepo.groups.isEmpty) {
          // The mode toggle rides ABOVE the empty state: Porch Stories needs
          // no characters, so a brand-new library must still be able to reach
          // it. Without this the toggle simply did not exist on a fresh
          // install and Stories was unreachable (found by the E2E suite).
          return _wrapChatsWithDrop(
            context,
            Column(
              children: [
                _modeToggleBar(),
                Expanded(
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            'Get started by creating a new character!',
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.titleLarge
                                ?.copyWith(
                                  color: Theme.of(context)
                                      .textTheme
                                      .titleLarge
                                      ?.color
                                      ?.withValues(alpha: 0.7),
                                ),
                          ),
                          const SizedBox(height: 24),
                          Wrap(
                            alignment: WrapAlignment.center,
                            spacing: 16,
                            runSpacing: 12,
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
                              ElevatedButton.icon(
                                onPressed: () => _importCharacter(context),
                                icon: const Icon(Icons.download),
                                label: const Text('Import Card'),
                                style: _buttonStyle(),
                              ),
                              ElevatedButton.icon(
                                onPressed: () => Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) =>
                                        const CharacterCreatorPage(),
                                  ),
                                ),
                                icon: const Icon(Icons.auto_awesome),
                                label: const Text('AI Create'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppColors.porchAmberOf(
                                    context,
                                  ),
                                  foregroundColor: AppColors.onChaosAccent,
                                ),
                              ),
                              ElevatedButton.icon(
                                onPressed: () =>
                                    _folderImportCharacters(context),
                                icon: const Icon(Icons.library_add),
                                label: const Text('Bulk Import'),
                                style: _buttonStyle(),
                              ),
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
                    ),
                  ),
                ),
              ],
            ),
          );
        }

        return _wrapChatsWithDrop(
          context,
          _wrapWithStatusBar(
            context,
            CharacterCardGrid(
              searchQuery: _searchQuery,
              searchScope: _searchScope,
              activeFolderId: _activeFolderId,
              sortMode: _sortMode,
              lastActivityCache: _lastActivityCache,
              messageCountCache: _messageCountCache,
              gridScale: _gridScale,
              isSelecting: _selection.isSelecting,
              isOrganizing: _selection.isOrganizing,
              selectedCharacterIds: _selection.characterIds,
              selectedGroupIds: _selection.groupIds,
              searchController: _searchController,
              gridScrollController: _gridScrollController,
              repo: repo,
              folderService: folderService,
              groupRepo: groupRepo,
              modeToggle: _buildModeToggle(),
              onTapCharacter: _handleTapCharacter,
              onTapGroup: _handleTapGroup,
              onToggleSelect: (c) =>
                  _selection.toggle(c.stableGroupId, group: false),
              onToggleSelectGroup: (g) => _selection.toggle(g.id, group: true),
              onToggleSelectMode: _selection.toggleSelectMode,
              onToggleOrganizeMode: _selection.toggleOrganizeMode,
              onContextMenuAction: _handleContextMenuAction,
              onImport: _handleImport,
              onAcceptFolderDrop: _handleAcceptFolderDrop,
              onFolderDialogAction: _handleFolderDialogAction,
              onFolderTap: _handleFolderTap,
              onFolderNavigateBack: _handleFolderNavigateBack,
              onFolderJump: (id) => setState(() => _activeFolderId = id),
              onCancelSelection: _cancelSelection,
              onDeleteSelected: _massDeleteSelected,
              // onCreateGroup no longer wired — old select-for-group path deprecated.
              onMoveToFolder: _handleMoveToFolder,
              onExportSelected: _exportSelectedPorch,
              onSortChanged: _handleSortChanged,
              onGridScaleChanged: _handleGridScaleChanged,
              onGridScaleChangeEnd: _handleGridScaleChangeEnd,
              onSearchScopeChanged: _handleSearchScopeChanged,
              onSearchQueryChanged: _handleSearchQueryChanged,
              onResolveCharImage: _resolveCharImage,
              onDeleteGroup: _handleDeleteGroup,
              onAfterNavigateBack: _refreshLastActivityCache,
              onGroupContextMenuAction: _handleGroupContextMenuAction,
              onSelectAll: _selection.selectAll,
              onSelectNone: _selection.selectNone,
              selection: _selection,
              onDropOnLevel: _handleDropOnLevel,
            ),
          ),
        );
      },
    );
  }
}
