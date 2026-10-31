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

part of '../chat_service.dart';

/// startNewChat prep — character refresh, transcript reset, opening greeting.
extension ChatServiceSessionNewChatPrep on ChatService {
  Future<void> _refreshCharacterForNewChat() async {
    // Refresh _session.activeCharacter from the repository so we pick up any edits
    // made in the character editor (personality, description, etc.)
    if (_session.activeCharacter != null && _characterRepository != null) {
      final freshChar = _characterRepository!.characters
          .cast<CharacterCard?>()
          .firstWhere(
            (c) => c!.dbId == _session.activeCharacter!.dbId,
            orElse: () => null,
          );
      if (freshChar != null) {
        // Preserve any runtime-loaded extensions if the repository instance lacks them
        final existingExt = _session.activeCharacter!.frontPorchExtensions;
        final existingRaw = _session.activeCharacter!.rawExtensions;

        _session.activeCharacter = freshChar;

        if (existingExt != null &&
            _session.activeCharacter!.frontPorchExtensions == null) {
          _session.activeCharacter!.frontPorchExtensions = existingExt;
          _session.activeCharacter!.rawExtensions = existingRaw;
          debugPrint(
            '[startNewChat] Preserved existing extensions during character refresh',
          );
        } else if (existingExt == null &&
            _session.activeCharacter!.frontPorchExtensions == null) {
          debugPrint(
            '[startNewChat] DEBUG: existingExt was null AND freshChar had null extensions.',
          );
        }
      } else {
        debugPrint(
          '[startNewChat] DEBUG: freshChar was null (repository lookup failed).',
        );
      }
    }

    // Fallback: If extensions are STILL missing, forcefully reload from PNG.
    // This catches edge cases where repository/memory loses sync with the file.
    if (_session.activeCharacter != null &&
        _session.activeCharacter!.frontPorchExtensions == null) {
      debugPrint(
        '[startNewChat] DEBUG: Extensions are missing. Attempting PNG fallback.',
      );
      if (_session.activeCharacter!.imagePath != null) {
        debugPrint(
          '[startNewChat] DEBUG: Image path exists: ${_session.activeCharacter!.imagePath}',
        );
        try {
          final v2Service = V2CardService();
          final reloaded = await v2Service.readCard(
            _session.activeCharacter!.imagePath!,
          );
          if (reloaded == null) {
            debugPrint(
              '[startNewChat] DEBUG: readCard returned null. Failed to parse PNG.',
            );
          } else if (reloaded.frontPorchExtensions != null) {
            _session.activeCharacter!.frontPorchExtensions =
                reloaded.frontPorchExtensions;
            _session.activeCharacter!.rawExtensions = reloaded.rawExtensions;
            debugPrint(
              '[startNewChat] Force-reloaded frontPorchExtensions from PNG',
            );
          } else {
            debugPrint(
              '[startNewChat] DEBUG: readCard succeeded, BUT reloaded.frontPorchExtensions was NULL! Meaning the PNG file does NOT contain the front_porch extension data.',
            );
          }
        } catch (e) {
          debugPrint('[startNewChat] Force-reload failed with exception: $e');
        }
      } else {
        debugPrint('[startNewChat] DEBUG: Cannot fallback. imagePath is null.');
      }
    }
  }

  Future<void> _resetNewChatTranscript() async {
    _session.messages.clear();
    _history.reset();
    _greetingIndex = 0;
    // A fresh chat starts with no Scene Guests (they don't carry across sessions).
    _sceneGuest.ids.clear();
    _sceneGuest.cards.clear();
    _sceneGuest.pendingDeparture = null;
    _sceneGuest.pendingPickerFilter = null;
    _resetGuestActivityState();
    // Phase 2 cast detection: reset the scan cadence + pending/debounce state
    // for the new 1:1 context (kept in sync with the Scene Guest clears).
    _sceneGuest.turnsSinceCastScan = 0;
    _sceneGuest.pendingDetection = null;
    _sceneGuest.offeredOrIgnoredNames.clear();
    _sceneMoves.reset(); // Slice 6: stale offers die with the session too.
    _summary = '';
    _summaryLastIndex = 0;
    _selectedLooks
        .clear(); // fresh 1:1: drop prior chat's per-chat look selection (keep reset blocks in sync)
    _sessionGenSettings =
        ChatGenerationSettings(); // fresh chat: drop prior chat's per-chat gen overrides — forkSession is the ONE path that inherits them on purpose (keep reset blocks in sync)
    _armPromptPickerIfDue(); // prompt-picker SOW: new 1:1 with a card prompt asks (or applies the remembered choice)
    _clearContextBudget();
    _summaryPaused =
        false; // explicit secondary zero for _summaryPaused (symmetric; startNew 1:1/ext-seed branch + incomplete zeroing ... now complete)
    _isSummaryGenerating =
        false; // explicit in startNewChat 1:1/ext-seed branch (both startNew explicit + incomplete zeroing... now complete (see CLAUDE.md); journal_maintenance) + "needsSimulation. (reason support kept for Director chips) ; cleared via sim initializeFresh/clearVector/resetBuffers on all paths; now complete in both branches)"

    // Explicitly clear any prior branching/fork metadata. A "New Chat" is
    // never a branch/fork from a previous session. This prevents stale
    // _parentSessionId / _forkIndex (from a previous branched chat or
    // different character) from being written into the brand-new session
    // record via _saveChat(), which was causing new chats to incorrectly
    // show "Branched at message #NNNN" in history lists even for characters
    // with no prior chats.
    _parentSessionId = null;
    _forkIndex = null;

    // Mark this as a new chat to prevent memory retrieval
    _isNewChat = true;
    debugPrint('[startNewChat] Marked as new chat - memories will be filtered');

    // Save the current session (preserves objectives for this session)
    if (_session.currentSessionId != null) {
      await _saveChat();
    }

    // Clear objectives for fresh session start
    objectivesDoor.resetForChatSwitch();
    _isGrowthPassRunning =
        false; // growth-pass flag zero in startNew 1:1/ext-seed branch (both startNew explicit; keep reset blocks in sync)

    // Create new session ID for the new chat
    _session.currentSessionId = DateTime.now().millisecondsSinceEpoch
        .toString();
    _computeAbsenceGap(
      const [],
    ); // fresh session — no real-world gap (Living Time §2)

    // Clear memory sources to prevent old memories from being retrieved
    // Cross-character memory can still be re-selected by user after new chat starts
    if (_session.activeCharacter?.dbId != null) {
      try {
        await _db.updateCharacter(
          CharactersCompanion(
            id: drift.Value(_session.activeCharacter!.dbId!),
            memorySources: drift.Value('[]'),
          ),
        );
        debugPrint('[startNewChat] Cleared memory sources from DB');
      } catch (e) {
        debugPrint('[startNewChat] Failed to clear memory sources: $e');
      }
    }
  }
}
