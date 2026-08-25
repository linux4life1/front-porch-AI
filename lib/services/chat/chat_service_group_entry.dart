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
    final ownedLoad = !_isLoadingSession;
    beginSessionLoad();
    try {
      // Cancel any in-flight generation before switching context AND reset author note for new session context
      await _cancelAndWaitForGeneration();
      await _waitForTurnToSettle();
      // Groups have no same-cast fast path — every re-enter clears
      // `_messages`. Persist first or the last exchange dies the same
      // way as the 1:1 slow path.
      await flushPendingSaves();
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
      _groupRetrievalCount = 4;
      _groupMemoryBudgetPercent = 10.0;
      _groupCharacterRAGPriorities = {};

      // Scene Guests are 1:1-only — clear them when entering a group.
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

      if (_characterRepository == null) return;

      // Clear 1:1 mode
      _activeCharacter = null;
      // Defensive: zero key 1:1 scalars so rapid 1:1↔group toggles cannot observe
      // stale values in the brief window before group per-speaker loads take over.
      // (Full reset happens on return to any 1:1 via setActiveCharacter.)
      _characterEmotion = '';
      _emotionIntensity = '';
      // Realism/Needs are per-chat and were never zeroed here. The promotion
      // block below only fires when the group definition carries member realism
      // seeds, so a group authored without them simply INHERITED the previous
      // chat's flags and needs vector — and the `_saveChat()` at the end of this
      // method baked them onto the group's first session row for good. Same
      // zeros the 1:1 twin does in setActiveCharacter; a stored session still
      // wins, because _loadLastSession hydrates both flags below.
      _realismEnabled = false;
      _needsSimEnabled = false;
      _enjoysLowHygiene = false;
      _needsSimulation.clearVector();
      _needsSimulation.resetBuffers();
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

      // Auto-start local backend when entering a group chat.
      // Gated by autostartOnChatOpen — when off, the user must start manually.
      if (_storageService.autostartOnChatOpen) {
        _llmProvider?.ensureManagedBackendIsRunning();
      }

      debugPrint(
        '[ChatService] 🟡 setActiveGroup: clearing messages '
        '(had ${_messages.length}) for group ${group.name}',
      );
      await _invalidateGreetingEval();
      _messages.clear();
      _greetingIndex = 0;
      _history.reset();
      _currentSessionId = null;
      _clearTodayPointer();
      // Clear fork/branch state so it doesn't leak across group switches
      // (see startNewChat and setActiveCharacter for rationale).
      _parentSessionId = null;
      _forkIndex = null;

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
      //
      // Reset FIRST, exactly as the 1:1 twin does: seedFromGroupOrExt sets only
      // the two switches ("pressure left as-is or explicitly zeroed by caller"),
      // so without this the previous chat's chance-time pressure — and an
      // un-delivered manual "SPIN NOW" event, which injects as CANON with no
      // chaos-enabled gate — walked into the group.
      _chaosModeService.resetForFreshChat();
      _chaosModeService.seedFromGroupOrExt(
        // OR-override, matching the two 1:1 seed sites: the group asks, or the
        // Porch Life global default does. A user who switched Chaos on globally
        // means it for groups too — this is the third of three seed sites and
        // missing it would have made the global switch quietly 1:1-only.
        group.chaosModeEnabled ||
            _storageService.realismSettings.chaosModeDefault,
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
          // Presence-inference — see the matching note in
          // group_realism_dynamics_editor. An explicit flag belongs at the blob's
          // top level, not in the per-member seed; that is a schema change.
          // AND-gated by the global Needs switch (Porch Life tab), like all four
          // 1:1/import seed sites. Without it the global was quietly 1:1-only:
          // every group still ran the full simulation and its per-turn eval.
          _needsSimEnabled =
              _storageService.realismSettings.needsSimDefault &&
              _groupRealism.values.any((state) {
                final n = state.needs;
                return n != null && n.isNotEmpty;
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

      // Path B: per-character group system prompts come from the group row's own
      // v32 column, and this seed MUST come after the block above: on a fresh
      // group `_loadGroupRealismStateFromSession(null)` zeroes every per-char
      // config map and can only refill them from `defaultMemberRealismState`,
      // which is perChar-only and never carries `characterSystemPrompts`. Seeding
      // before it meant the wizard's prompts were wiped on entry and the first
      // `_saveChat` below baked the empty map into the session blob — dead for
      // the life of the chat. (startNewChat avoids the same trap by not calling
      // that loader at all; see its group branch.) `addAll`, not assign, so a
      // legacy blob that did carry entries keeps them.
      _groupCharacterSystemPrompts.addAll(group.characterSystemPrompts);

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

      // Same as the 1:1 twin in chat_service_chat_entry: message 0 needs every
      // member's authored wardrobe in place, and after the load so a restored
      // session wins. Parity is not optional here — a group member dressed by her
      // author must arrive dressed exactly as she would in a 1:1.
      seedPocketsFromCards();

      // Load the objectives for whoever is the initial next speaker (or first char)
      if (_activeGroup != null) {
        await _loadObjectivesForCurrentSpeaker();
      }

      // Seed objectives that came from an imported Group Card (one-time), in case it wasn't caught above
      await _seedImportedMemberObjectivesIfPresent();

      // If no session, create a greeting
      if (_messages.isEmpty && _groupCharacters.isNotEmpty) {
        // Each member's authored starting quest, imported once per fresh chat.
        for (final c in _groupCharacters) {
          _importAuthoredTask(c.frontPorchExtensions, target: c);
        }

        String greetingText;
        String greetingSender;
        String? greetingCharId;

        if (!greetingFirstMesEmpty(group.firstMessage)) {
          // Use custom group first message — attribute to "Narrator" or group name
          greetingText = _macroResolver.resolve(
            group.firstMessage,
            MacroContext(userName: _userPersonaService.persona.name),
            section: 'greeting',
          );
          greetingSender = group.name;
          greetingCharId = null;
        } else {
          // Fall back to first member's allGreetings (same pairing as 1:1).
          final first = _groupCharacters.first;
          greetingText = _memberOpeningGreetingText(first);
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
          if (greetingFirstMesEmpty(group.firstMessage) &&
              greetingFirstMesEmpty(_groupCharacters.first.firstMessage)) {
            await _applyGreetingOpeningSeed(
              card: _groupCharacters.first,
              index: 0,
            );
          }
        }
        _currentSessionId = DateTime.now().millisecondsSinceEpoch.toString();
        // Seed chat worlds from the group's template (Living Worlds).
        await _seedChatWorldsForNewSession();
        await _saveChat();
      }

      // Cache growth rings (and any not-yet-distilled legacy evolved blobs)
      // for all group characters so the injection layer can read them sync.
      await _refreshGrowthCache();
    } finally {
      if (ownedLoad) endSessionLoad();
    }
  }

  /// The LIBRARY character this card came from. Identity first (dbId, then
  /// stableGroupId), name only when it is unique — two "Rachel"s must not
  /// share a face. Null when there is no confident match (imported-only
  /// member, or two library cards with the same name and no stamp).
  /// Used to inherit expressions and to route the in-chat Expression
  /// Images editor at the member's real library home.
  CharacterCard? originLibraryCardFor(CharacterCard member) {
    final lib = _characterRepository?.characters;
    if (lib == null) return null;
    return MemberOriginResolver.resolveForCard(member, lib);
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
