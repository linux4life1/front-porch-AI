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

import 'package:drift/drift.dart' as drift;
import 'package:flutter/foundation.dart';

import 'package:front_porch_ai/database/database.dart' hide AvatarImage, World;
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/chat/chat.dart';
import 'package:front_porch_ai/services/group_chat_repository.dart';
import 'package:front_porch_ai/services/v2_card_service.dart';

import 'session_store.dart';

/// New-chat prep: the explicit "Start New Chat" entry, the persona write,
/// the character refresh and the transcript reset a fresh chat starts from.
class NewChatPrep {
  NewChatPrep(this._d, this._store);

  final SessionDeps _d;
  final SessionStore _store;

  ChatSessionState get _session => _d.session;
  SessionServices get _s => _d.services;
  SessionShellHooks get _h => _d.hooks;

  /// Open a FRESH chat with [character] or [group] under an explicitly chosen
  /// user persona — the home grid's "Start New Chat" (desktop context menu and
  /// the web library card menu both land here, so the ordering below exists
  /// once).
  ///
  /// The chosen persona rides all the way into startNewChat rather than
  /// being applied here: entering a cast loads its most recent session, and
  /// that restores the OTHER chat's persona, so anything set before the entry
  /// call is overwritten. Handing it to the session-creating step removes the
  /// ordering trap instead of documenting it.
  Future<void> startFreshChatWith({
    CharacterCard? character,
    GroupChat? group,
    GroupChatRepository? groupRepo,
    required String personaId,
  }) async {
    if (character == null && (group == null || groupRepo == null)) return;
    // Hold the overlay across enter + startNewChat so ChatPage never paints
    // the previous session's last transcript in between the two awaits.
    _h.beginSessionLoad();
    try {
      if (character != null) {
        await _h.setActiveCharacter(character);
      } else {
        await _h.setActiveGroup(group!, groupRepo: groupRepo!);
      }
      await _store.loader.startNewChat(
        personaId: personaId.isEmpty ? null : personaId,
      );
    } finally {
      _h.endSessionLoad();
    }
  }

  /// Write the currently-active persona onto the open session right now.
  ///
  /// The in-chat switcher (desktop composer avatar, web chat menu) changes who
  /// you are speaking as; every save stamps that onto the session row, so
  /// the binding would normally land with the next message. This makes it land
  /// immediately, so switching and then closing the app is not silently
  /// forgotten. No-op when no chat is open.
  Future<void> persistSessionPersona() async {
    if (_session.currentSessionId == null) return;
    await _store.save();
    unawaited(_s.birthdays().ensure());
  }

  Future<void> refreshCharacterForNewChat() async {
    // Refresh the active character from the repository so we pick up any
    // edits made in the character editor (personality, description, etc.)
    final repository = _s.characters();
    if (_session.activeCharacter != null && repository != null) {
      final freshChar = repository.characters.cast<CharacterCard?>().firstWhere(
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

  Future<void> resetNewChatTranscript() async {
    final cast = _s.cast();
    _session.messages.clear();
    _store.history.reset();
    cast.greetings.greetingIndex = 0;
    // A fresh chat starts with no Scene Guests (they don't carry across sessions).
    final guests = cast.guests;
    guests.state.ids.clear();
    guests.state.cards.clear();
    guests.state.pendingDeparture = null;
    guests.state.pendingPickerFilter = null;
    guests.resetActivityState();
    // Phase 2 cast detection: reset the scan cadence + pending/debounce state
    // for the new 1:1 context (kept in sync with the Scene Guest clears).
    guests.state.turnsSinceCastScan = 0;
    guests.state.pendingDetection = null;
    guests.state.offeredOrIgnoredNames.clear();
    _s.sceneMoves.reset(); // Slice 6: stale offers die with the session too.
    _store.summary = '';
    _store.summaryLastIndex = 0;
    // Fresh 1:1: drop the prior chat's per-chat look selection (keep reset
    // blocks in sync).
    _store.selectedLooks.clear();
    // Fresh chat: drop the prior chat's per-chat gen overrides — forkSession
    // is the ONE path that inherits them on purpose (keep reset blocks in sync).
    _store.genSettings = ChatGenerationSettings();
    _h.armPromptPicker(); // prompt-picker SOW: new 1:1 with a card prompt asks (or applies the remembered choice)
    _h.clearContextBudget();
    // Explicit secondary zeros in the startNewChat 1:1/ext-seed branch.
    _store.summaryPaused = false;
    _store.isSummaryGenerating = false;

    // Explicitly clear any prior branching/fork metadata. A "New Chat" is
    // never a branch/fork from a previous session. This prevents stale
    // parent/fork values (from a previous branched chat or different
    // character) from being written into the brand-new session record by the
    // save, which was causing new chats to incorrectly show "Branched at
    // message #NNNN" in history lists even for characters with no prior chats.
    _store.parentSessionId = null;
    _store.forkIndex = null;

    // Mark this as a new chat to prevent memory retrieval
    _store.isNewChat = true;
    debugPrint('[startNewChat] Marked as new chat - memories will be filtered');

    // Save the current session (preserves objectives for this session)
    if (_session.currentSessionId != null) {
      await _store.save();
    }

    // Clear objectives for fresh session start
    _s.objectives().resetForChatSwitch();
    _s.graph().growthPassRunning = false; // keep reset blocks in sync

    // Create new session ID for the new chat
    _session.currentSessionId = DateTime.now().millisecondsSinceEpoch
        .toString();
    _store.computeAbsenceGap(
      const [],
    ); // fresh session — no real-world gap (Living Time §2)

    // Clear memory sources to prevent old memories from being retrieved
    // Cross-character memory can still be re-selected by user after new chat starts
    if (_session.activeCharacter?.dbId != null) {
      try {
        await _s.db().updateCharacter(
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
