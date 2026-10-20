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

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/providers/app_state.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/utils/utils.dart';
import 'package:front_porch_ai/ui/pages/home/cards/library_drag_payload.dart';
import 'package:front_porch_ai/ui/pages/home/home_actions/home_actions.dart';
import 'package:front_porch_ai/ui/pages/home/home_drop_zone.dart';
import 'package:front_porch_ai/ui/pages/home/home_page_chrome.dart';
import 'package:front_porch_ai/ui/pages/home/library_selection.dart';
import 'package:front_porch_ai/ui/pages/home/widgets/home_mode_toggle.dart';
import 'package:front_porch_ai/ui/pages/story_home_view.dart';
import 'package:front_porch_ai/ui/theme/studio_colors.dart';
import 'package:front_porch_ai/ui/waifu/waifu.dart';
import 'package:front_porch_ai/ui/widgets/widgets.dart';

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

  /// Every way into a chat (taps, menus, Manage Chats, OPEN_CHAT) and the
  /// busy guard that stops stacked open-chat taps.
  late final HomeChatOpener _chats;

  // Scroll controller for the character grid (visible scrollbar)
  final ScrollController _gridScrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _chats = HomeChatOpener(
      context: context,
      isMounted: () => mounted,
      onChatClosed: _refreshLastActivityCache,
    );
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
      (_) => _chats.maybeOpenChatFromEnv(),
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

  Widget _buildModeToggle() {
    return HomeModeToggle(
      showStories: _homeMode == HomeMode.stories,
      showWaifu: _homeMode == HomeMode.waifu,
      studio: _homeMode == HomeMode.stories,
      onShowChats: () => _setHomeMode(HomeMode.chats),
      onShowStories: () => _setHomeMode(HomeMode.stories),
      onShowWaifu: () => _setHomeMode(HomeMode.waifu),
    );
  }

  void _setHomeMode(HomeMode mode) {
    setState(() => _homeMode = mode);
    Provider.of<AppState>(
      context,
      listen: false,
    ).setSidebarHidden(mode != HomeMode.chats);
  }

  void _onAppStateChanged() {
    if (!mounted) return;
    try {
      final appState = Provider.of<AppState>(context, listen: false);
      if (appState.homeResetTick != _lastHomeResetTick) {
        _lastHomeResetTick = appState.homeResetTick;
        setState(() => _activeFolderId = null);
      }
    } catch (_) {}
  }

  void _onCharactersChanged() {
    if (!mounted) return;
    _activityRefreshDebounce?.cancel();
    _activityRefreshDebounce = Timer(const Duration(milliseconds: 250), () {
      _activityRefreshDebounce = null;
      if (mounted) _refreshLastActivityCache();
    });
    // Characters often land after Home's first frame — retry the launch hook.
    _chats.maybeOpenChatFromEnv();
  }

  // No toast when a model finishes loading: dual-local mouth/worker swaps
  // mark ready on every GGUF load, and the success SnackBars stacked.
  // Kobold notifies per console burst. While the chat route covers Home the
  // Overlay turns its tickers off; build depends on that, so Home redraws
  // fresh once it is uncovered and skips every update until then.
  void _onKoboldUpdate() {
    if (!mounted || !TickerMode.getValuesNotifier(context).value.enabled) {
      return;
    }
    setState(() {}); // Rebuild to update status bar
  }

  /// Picks changed (any gesture, see [LibrarySelection]): redraw the grid.
  void _onSelectionChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _refreshLastActivityCache() async {
    try {
      final db = await AppDatabase.instance();
      final charRepo = Provider.of<CharacterRepository>(context, listen: false);
      final activity = await loadHomeLibraryActivity(db, charRepo);
      if (mounted) {
        setState(() {
          _lastActivityCache
            ..clear()
            ..addAll(activity.lastActivity);
          _messageCountCache
            ..clear()
            ..addAll(activity.messageCounts);
        });
      }
    } catch (e) {
      debugPrint('Error refreshing activity cache: $e');
      if (mounted) setState(() {});
    }
  }

  /// A drop on a folder tile or on a level of the path (null: the top
  /// level). A dragged selection moves in one go and says so; a single
  /// card moves quietly, as it always has.
  Future<void> _handleDropOnLevel(Object item, String? folderId) async {
    final moved = await _selection.drop(
      item,
      folderId,
      folders: Provider.of<FolderService>(context, listen: false),
      library: Provider.of<CharacterRepository>(
        context,
        listen: false,
      ).characters,
    );
    if (moved != null && item is LibraryDragPayload && mounted) {
      snackHomeMoved(context, moved, folderId);
    }
  }

  /// If the user is standing inside the folder being deleted, step back out
  /// to its parent (top level when the folder was top-level).
  void _leaveDeletedFolder(CharacterFolder folder) {
    if (_activeFolderId != folder.id) return;
    setState(() => _activeFolderId = folder.parentId);
  }

  /// Up one level. Subfolder cards only render inside their parent, so the
  /// parent chain IS the navigation history — no stack needed (and the
  /// breadcrumb trail can jump to any ancestor directly).
  void _handleFolderNavigateBack() {
    final folderService = Provider.of<FolderService>(context, listen: false);
    final current = folderService.folders
        .where((f) => f.id == _activeFolderId)
        .firstOrNull;
    setState(() => _activeFolderId = current?.parentId);
  }

  SelectionTally _selectionTally() => tallyHomeSelection(
    context,
    _selection,
    activeFolderId: _activeFolderId,
    query: _searchQuery,
    scope: _searchScope,
    sortMode: _sortMode,
  );

  void _handleSortChanged(String mode) {
    setState(() => _sortMode = mode);
    Provider.of<StorageService>(
      context,
      listen: false,
    ).uiSettings.setSortMode(mode);
  }

  /// Remembered per level, like the sort: the top level offers Everywhere
  /// and Top level only, a folder its three choices.
  void _handleSearchScopeChanged(SearchScope scope) {
    final prefs = Provider.of<StorageService>(
      context,
      listen: false,
    ).uiSettings;
    if (_activeFolderId == null) {
      setState(() => _topSearchScope = scope);
      prefs.setTopSearchScope(scope.name);
    } else {
      setState(() => _folderSearchScope = scope);
      prefs.setFolderSearchScope(scope.name);
    }
  }

  /// Desktop PNG/BYAF/.porch drop on the chats library. [context] is the
  /// library view's, which survives the empty → populated switch.
  Widget _wrapChatsWithDrop(BuildContext context, Widget child) {
    return HomeDropZone(
      onDrop: (sources) => HomeDropImport(
        context,
        importPorchPaths: (paths) => importHomePorchPaths(this.context, paths),
      ).importDroppedFiles(sources),
      child: child,
    );
  }

  @override
  Widget build(BuildContext context) {
    TickerMode.valuesOf(context); // see _onKoboldUpdate
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
        if (_homeMode != HomeMode.chats) {
          final stories = _homeMode == HomeMode.stories;
          final bar = HomeModeToggleBar(toggle: _buildModeToggle());
          return HomeStatusFrame(
            content: Column(
              children: [
                if (stories)
                  ColoredBox(color: StudioColors.sideOf(context), child: bar)
                else
                  bar,
                Expanded(
                  child: stories
                      ? const StoryHomeView()
                      : const WaifuHomeView(),
                ),
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
                HomeModeToggleBar(toggle: _buildModeToggle()),
                Expanded(
                  child: HomeEmptyLibrary(
                    onImportCards: () => HomeCardImport(context).pickCards(),
                    onBulkImport: () => HomeBulkImport(context).importFolder(),
                    onImportByaf: () => HomeCardImport(context).pickByaf(),
                  ),
                ),
              ],
            ),
          );
        }

        return _wrapChatsWithDrop(
          context,
          HomeStatusFrame(
            content: CharacterCardGrid(
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
              onTapCharacter: _chats.tapCharacter,
              onTapGroup: _chats.tapGroup,
              onToggleSelect: (c) =>
                  _selection.toggle(c.stableGroupId, group: false),
              onToggleSelectGroup: (g) => _selection.toggle(g.id, group: true),
              onToggleSelectMode: _selection.toggleSelectMode,
              onToggleOrganizeMode: _selection.toggleOrganizeMode,
              onContextMenuAction: (action, character) =>
                  runHomeCharacterMenuAction(
                    this.context,
                    action,
                    character,
                    chats: _chats,
                    activeFolderId: _activeFolderId,
                  ),
              onImport: (source) => runHomeImportMenu(this.context, source),
              // Both draggable kinds: characters keyed by image filename, group
              // casts by their group id (see FolderService).
              onAcceptFolderDrop: (item, folder) =>
                  _handleDropOnLevel(item, folder.id),
              onFolderDialogAction: (action, {folder, parentId}) =>
                  runHomeFolderDialogAction(
                    this.context,
                    action,
                    folder: folder,
                    parentId: parentId,
                    onLeaveFolder: _leaveDeletedFolder,
                  ),
              onFolderTap: (folder) =>
                  setState(() => _activeFolderId = folder.id),
              onFolderNavigateBack: _handleFolderNavigateBack,
              onFolderJump: (id) => setState(() => _activeFolderId = id),
              onCancelSelection: _selection.cancel,
              onDeleteSelected: (ids) => massDeleteHomeSelection(
                this.context,
                ids,
                groupIds: _selection.groupIds,
                hiddenCount: () => _selectionTally().hidden,
                onDeleted: _selection.cancel,
              ),
              // onCreateGroup no longer wired — old select-for-group path deprecated.
              onMoveToFolder: (_) => showHomeMoveSelectionDialog(
                this.context,
                picks: _selectionTally(),
                selection: _selection,
              ),
              onExportSelected: (ids) => exportHomeSelectionPorch(
                this.context,
                ids,
                groupsLeftOut: _selection.groupIds.isNotEmpty,
                onSaved: _selection.cancel,
              ),
              onSortChanged: _handleSortChanged,
              onGridScaleChanged: (scale) => setState(() => _gridScale = scale),
              onGridScaleChangeEnd: (scale) => Provider.of<StorageService>(
                this.context,
                listen: false,
              ).uiSettings.setGridScale(scale),
              onSearchScopeChanged: _handleSearchScopeChanged,
              onSearchQueryChanged: (query) =>
                  setState(() => _searchQuery = query),
              onResolveCharImage: (c) => resolveHomeCardImage(this.context, c),
              onDeleteGroup: (group) =>
                  confirmDeleteHomeGroup(this.context, group),
              onAfterNavigateBack: _refreshLastActivityCache,
              onGroupContextMenuAction: (action, group) =>
                  runHomeGroupMenuAction(
                    this.context,
                    action,
                    group,
                    chats: _chats,
                    activeFolderId: _activeFolderId,
                  ),
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
