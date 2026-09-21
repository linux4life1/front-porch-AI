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

/// Activity-cache refresh, Kobold/repo listeners, and multi-select toggles.
extension _HomePageLifecycle on _HomePageState {
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

  void _onAppStateChanged() {
    if (!mounted) return;
    try {
      final appState = Provider.of<AppState>(context, listen: false);
      if (appState.homeResetTick != _lastHomeResetTick) {
        _lastHomeResetTick = appState.homeResetTick;
        applyState(() => _activeFolderId = null);
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
    _maybeOpenChatFromEnv();
  }

  void _onKoboldUpdate() {
    if (!mounted) return;
    try {
      final kobold = Provider.of<KoboldService>(context, listen: false);
      // Drain the one-shot. Do not toast — dual-local mouth/worker swaps
      // mark ready on every GGUF load and the success SnackBar stacked.
      kobold.consumeModelReady();
      applyState(() {}); // Rebuild to update status bar
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
        applyState(() {
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
      if (mounted) applyState(() {});
    }
  }

  /// Delegates to the canonical stable group ID.
  /// See [StableGroupId.stableGroupId] in lib/utils/character_id.dart
  String _getCharacterIdFromCard(CharacterCard card) => card.stableGroupId;

  void _toggleSelectMode() {
    applyState(() {
      _isSelecting = !_isSelecting;
      _isOrganizing = false;
      if (!_isSelecting) {
        _selectedCharacterIds.clear();
        _selectedGroupIds.clear();
      }
    });
  }

  void _toggleOrganizeMode() {
    applyState(() {
      _isOrganizing = !_isOrganizing;
      _isSelecting = false;
      if (!_isOrganizing) {
        _selectedCharacterIds.clear();
        _selectedGroupIds.clear();
      }
    });
  }

  void _toggleSelect(CharacterCard character) {
    final id = character.imagePath != null
        ? path.basenameWithoutExtension(character.imagePath!)
        : character.name
              .replaceAll(RegExp(r'[^\w\s]'), '')
              .replaceAll(' ', '_');
    applyState(() {
      if (_selectedCharacterIds.contains(id)) {
        _selectedCharacterIds.remove(id);
        if (_selectedCharacterIds.isEmpty && _selectedGroupIds.isEmpty) {
          _isSelecting = false;
          _isOrganizing = false;
        }
      } else {
        _selectedCharacterIds.add(id);
      }
    });
  }

  /// Group analogue of [_toggleSelect] — groups are selected by their id
  /// (they have no image-filename key).
  void _toggleSelectGroup(GroupChat group) {
    applyState(() {
      if (_selectedGroupIds.contains(group.id)) {
        _selectedGroupIds.remove(group.id);
        if (_selectedCharacterIds.isEmpty && _selectedGroupIds.isEmpty) {
          _isSelecting = false;
          _isOrganizing = false;
        }
      } else {
        _selectedGroupIds.add(group.id);
      }
    });
  }

  void _cancelSelection() {
    applyState(() {
      _isSelecting = false;
      _isOrganizing = false;
      _selectedCharacterIds.clear();
      _selectedGroupIds.clear();
    });
  }
}
