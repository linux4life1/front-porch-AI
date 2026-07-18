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

/// Chat-entry point — setActiveGroup (open/seed a group chat). Extracted verbatim (zero behaviour change) to shrink the god file.
extension ChatServiceGroupEntry on ChatService {
  /// Enter group chat mode with the given GroupChat definition.
  Future<void> setActiveGroup(
    GroupChat group, {
    GroupChatRepository? groupRepo,
  }) async {
    // Cancel any in-flight generation before switching context AND reset author note for new session context
    await _cancelAndWaitForGeneration();
    _generationEpoch++;

    // Reset AFK idle state when switching to a different group
    _cancelIdleTimer();
    _hasCompletedExchange = false;

    // Reset author notes and summary when starting fresh chat/group (will be overridden if loading existing session)
    _authorNote = '';
    _authorNoteStrength = 4;
    _summary = '';
    _summaryLastIndex = 0;
    _selectedLooks
        .clear(); // fresh group: drop prior chat's per-chat look selection (keep reset blocks in sync)
    _summaryPaused =
        false; // explicit secondary zero for _summaryPaused (symmetric; incomplete zeroing... now complete (see CLAUDE.md); see keep-sync + journal_maintenance)
    _isSummaryGenerating =
        false; // explicit secondary zero on setActiveGroup (incomplete zeroing ... now complete; keep-sync lists + journal_maintenance + " ; authority for needs deltas thin path)") + "needsSimulation. (reason support kept for Director chips) ; cleared via sim initializeFresh/clearVector/resetBuffers on all paths; now complete)"
    _groupRealism = {};
    _groupDecayRates = {};
    _groupAuthorNotes = {};
    _groupAuthorNoteStrengths = {};
    _groupCharacterSystemPrompts = {};
    _groupRagEnabled = true;
    _groupRetrievalCount = 8;
    _groupMemoryBudgetPercent = 10.0;
    _groupCharacterRAGPriorities = {};

    // Scene Guests are 1:1-only — clear them when entering a group.
    _sceneGuestIds.clear();
    _sceneGuestCards.clear();
    _pendingGuestDeparture = null;
    _pendingGuestPickerFilter = null;
    _resetGuestActivityState();
    // Phase 2 cast detection: reset the scan cadence + pending/debounce state
    // for the new 1:1 context (kept in sync with the Scene Guest clears).
    _userMessagesSinceLastCastScan = 0;
    _pendingGuestDetection = null;
    _offeredOrIgnoredGuestNames.clear();

    // Path B: Load per-character group system prompts from the clean model field
    _groupCharacterSystemPrompts = Map<String, String>.from(
      group.characterSystemPrompts,
    );

    if (_characterRepository == null) return;

    // Clear 1:1 mode
    _activeCharacter = null;
    // Defensive: zero key 1:1 scalars so rapid 1:1↔group toggles cannot observe
    // stale values in the brief window before group per-speaker loads take over.
    // (Full reset happens on return to any 1:1 via setActiveCharacter.)
    _characterEmotion = '';
    // Relationship scalars/fixation (affection/trust/tiers/fixation/spatial/pending) via extracted service.
    // Expression manual/caches via service. Time (clock/day/passage/anchor/turns) via service.
    // Nsfw (arousal/cooldown) via service.
    // Lorebook triggers via scanner (for group fresh/0-session hygiene; parallels time/nsfw defensive zeros).
    // Reset hygiene (see CLAUDE.md "keep reset blocks in sync" + "incomplete zeroing of secondary config on group/0-session/new-chat now complete" at *all* ~15+ sites + both startNew explicit; authority live ext no scalar; buffer removal complete; leaves stateless/prompt-only no reset calls; void_=15).
    // (cross-ref setActiveCharacter)
    _relationshipService.resetForFreshChat();
    _expressionService.resetForFreshChat();
    _timeService.resetForFreshChat();
    _nsfwService.resetForFreshChat();
    _lorebookScanner.resetLorebookTriggerState();

    // Auto-start local backend when entering a group chat
    _llmProvider?.ensureManagedBackendIsRunning();

    debugPrint(
      '[ChatService] 🟡 setActiveGroup: clearing messages '
      '(had ${_messages.length}) for group ${group.name}',
    );
    _messages.clear();
    _currentSessionId = null;
    // Clear fork/branch state so it doesn't leak across group switches
    // (see startNewChat and setActiveCharacter for rationale).
    _parentSessionId = null;
    _forkIndex = null;
    _isLoadingSession = true;
    notifyListeners();

    // Resolve characters from decoupled private members (GroupMembers table + private avatars dir).
    // Prefer passed repo, then wired one, then direct DB query as ultimate fallback
    // (ensures members appear in chat even if DI wiring or caller is incomplete).
    List<GroupMember> memberRows = const [];
    try {
      final effectiveGroupRepo = groupRepo ?? _groupChatRepository;
      if (effectiveGroupRepo != null) {
        memberRows = await effectiveGroupRepo.getMembersForGroup(group.id);
      } else {
        final db = await AppDatabase.instance();
        final rows = await db.getGroupMembers(group.id);
        memberRows = rows.map(GroupMember.fromRow).toList();
      }
    } catch (e) {
      debugPrint(
        '[ChatService] Failed to load group members for ${group.id}: $e',
      );
      memberRows = const [];
    }

    final resolved = <CharacterCard>[];
    for (final m in memberRows) {
      if (m.avatarFilename != null) {
        final p = path.join(
          _storageService.groupsDir.path,
          group.id,
          'avatars',
          m.avatarFilename!,
        );
        // Include the member even if the avatar file is missing (defensive for groups created
        // from sources that had no avatar, or partial copy failures). The UI already degrades
        // gracefully to a colored letter/initial when the image can't be loaded.
        if (await File(p).exists()) {
          resolved.add(m.toCharacterCard(resolvedImagePath: p));
        } else {
          // Still include them so the count and sidebar are correct; they just won't have a face.
          debugPrint(
            '[ChatService] Group member ${m.name} has no avatar file at $p — including without image',
          );
          resolved.add(m.toCharacterCard(resolvedImagePath: p));
        }
      } else {
        // No avatar filename at all — still include so the user sees the member.
        resolved.add(m.toCharacterCard(resolvedImagePath: ''));
      }
    }

    // Group members are single-avatar copies; let them borrow their origin
    // library character's expression images so expressions work in groups.
    _inheritGroupExpressionAvatars(resolved);

    // Hand off to the turn manager (single source of truth for group turn state)
    _groupManager ??= GroupTurnManager();
    _groupManager!.enterGroup(
      group,
      resolved,
      startInDirectorMode: group.directorMode,
    );

    // Seed group definition defaults for Chaos (can be overridden by per-session values loaded below).
    // This makes the chaosModeEnabled / chaosNsfwEnabled on the GroupChat model actually functional.
    _chaosModeService.seedFromGroupOrExt(
      group.chaosModeEnabled,
      group.chaosNsfwEnabled,
    );

    // v30: For newly created group sessions (no prior state), seed from the group's default realism data.
    // (The actual load of any prior session state happens in _loadLastSession below.)
    if (_messages.isEmpty && _activeGroup != null) {
      _loadGroupRealismStateFromSession(null);

      // Promote the group definition's realism/needs intent on first entry.
      // The creator (and Group Card import) express "realism on" by writing non-empty
      // defaultMemberRealismState. Without this promotion, the master flag stays false
      // (its Dart initializer), the first session is saved with realism off, and both
      // isGroupRealismActive and all per-char getters return nothing.
      if (_groupRealism.isNotEmpty) {
        _realismEnabled = true;
        // Infer needs from whether the seeded per-char states actually contain needs data.
        // (Creator omits the 'needs' sub-map entirely when the user disabled Needs in the wizard.)
        _needsSimEnabled = _groupRealism.values.any((state) {
          final n = state['needs'];
          return n is Map && n.isNotEmpty;
        });
        if (_needsSimEnabled) {
          // Seed from group definition's per-char needs baselines (falls back to 80 when absent).
          final defaults = <String, int>{
            'hunger': 80,
            'bladder': 80,
            'energy': 80,
            'social': 80,
            'fun': 80,
            'hygiene': 80,
            'comfort': 80,
          };
          _needsSimulation.initializeFreshWithDefaults(defaults);
        }
        debugPrint(
          '[GroupRealism] Promoted definition realism/needs on fresh group entry '
          '(realism=$_realismEnabled, needs=$_needsSimEnabled, chars=${_groupRealism.length})',
        );
      }
    }

    // Seed objectives that came from an imported Group Card (one-time)
    await _seedImportedMemberObjectivesIfPresent();

    // Lorebook trigger reset via extracted service (group path; see setActiveCharacter for the 1:1 counterpart + keep-sync cross-refs).
    // See "keep reset blocks in sync" comments (now explicitly lists needs/chaos/... + leaves (see CLAUDE.md for full; incomplete zeroing now complete) alongside prior services; incomplete zeroing now complete).
    // (cross-ref setActiveCharacter:1572)
    _lorebookScanner.resetLorebookTriggerState();

    // Zero secondary objective config on group fresh entry (before loadLast + _loadObjectivesForCurrentSpeaker); see decl + keep reset + incomplete zeroing now complete.
    _activeObjectives = [];
    _messagesSinceLastCheck = 0;
    _isCheckingCompletion = false;
    _summaryPaused =
        false; // explicit secondary zero for _summaryPaused (symmetric; group fresh entry zero)
    _isSummaryGenerating =
        false; // secondary flag zero for the journal recap state (stateless/prompt-only; see incomplete zeroing ... now complete + keep-sync lists)
    _isGrowthPassRunning =
        false; // growth-pass flag zero on group fresh entry (transient guard; keep reset blocks in sync)

    // Try to load last session for this group
    await _loadLastSession();

    // Load the objectives for whoever is the initial next speaker (or first char)
    if (_activeGroup != null) {
      await _loadObjectivesForCurrentSpeaker();
    }

    // Seed objectives that came from an imported Group Card (one-time), in case it wasn't caught above
    await _seedImportedMemberObjectivesIfPresent();

    // If no session, create a greeting
    if (_messages.isEmpty && _groupCharacters.isNotEmpty) {
      String greetingText;
      String greetingSender;
      String? greetingCharId;

      if (group.firstMessage.isNotEmpty) {
        // Use custom group first message — attribute to "Narrator" or group name
        greetingText = _macroResolver.resolve(
          group.firstMessage,
          MacroContext(userName: _userPersonaService.persona.name),
          section: 'greeting',
        );
        greetingSender = group.name;
        greetingCharId = null;
      } else {
        // Fall back to first character's greeting
        final first = _groupCharacters.first;
        greetingText = first.firstMessage.isNotEmpty
            ? _buildFirstMessage(first)
            : '';
        greetingSender = first.name;
        greetingCharId = _getCharacterIdFromCard(first);
      }

      if (greetingText.isNotEmpty) {
        _messages.add(
          ChatMessage(
            text: greetingText,
            sender: greetingSender,
            isUser: false,
            characterId: greetingCharId,
          ),
        );
        // Thin delegation to scanner (group greeting scan).
        _lorebookScanner.scanLatest();
      }
      _currentSessionId = DateTime.now().millisecondsSinceEpoch.toString();
      await _saveChat();
    }

    // Cache growth rings (and any not-yet-distilled legacy evolved blobs)
    // for all group characters so the injection layer can read them sync.
    await _refreshGrowthCache();

    _isLoadingSession = false;
    notifyListeners();
  }

  /// The LIBRARY character a group member was copied from, matched by NAME — the
  /// single home for that character's expression images and edits. Returns null
  /// if the member has no library counterpart (e.g. an imported-only member).
  /// Name-matching is the right key: a member keeps the library character's name,
  /// and the display resolves avatar files via `characterAvatarDir(name)`, so the
  /// origin's files land on the member's folder too. Used both to inherit
  /// expressions for display and to route the in-chat Expression Images editor at
  /// the member's real library home (where edits persist).
  CharacterCard? originLibraryCardFor(CharacterCard member) {
    final lib = _characterRepository?.characters;
    if (lib == null) return null;
    final name = member.name.toLowerCase();
    for (final c in lib) {
      if (c.name.toLowerCase() == name) return c;
    }
    return null;
  }

  /// Group members are single-avatar copies of LIBRARY characters (the decoupled
  /// model stores one PNG per member, no expression set). For the expression
  /// display, inherit the origin library character's expression images. No
  /// per-member storage: a character that has expressions set up in your library
  /// shows them in the group; a member with no library match keeps its single
  /// avatar. Mutates each card's `avatarImages` in place (defensive copy so the
  /// member can never mutate the shared library list).
  void _inheritGroupExpressionAvatars(List<CharacterCard> members) {
    for (final m in members) {
      if (m.avatarImages != null && m.avatarImages!.isNotEmpty) continue;
      final origin = originLibraryCardFor(m);
      if (origin?.avatarImages != null && origin!.avatarImages!.isNotEmpty) {
        m.avatarImages = List<AvatarImage>.from(origin.avatarImages!);
      }
    }
  }
}
