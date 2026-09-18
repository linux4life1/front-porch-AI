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

/// Session hydrate — messages, scalars, persona, Porch diary import.
extension ChatServiceSessionHydrate on ChatService {
  /// Decode DB [Message] rows into [_messages], applying retroactive output
  /// sanitisation when the per-chat or global setting requests it.
  /// Caller must clear `_messages` and set `_sessionGenSettings` beforehand.
  void _hydrateMessagesFromRows(List<Message> dbMessages) {
    // Output sanitizer: apply configured replacements to loaded swipes
    // so legacy messages (saved before this feature) are also normalised.
    // Gated by sanitiseExistingHistory — when off, even chats with
    // per-chat sanitizer enabled keep their raw saved text on load.
    // Resolved (per-chat override + rules, falling back to global) and
    // compiled ONCE out here: this loop runs per message and sanitize runs
    // per swipe, so compiling per swipe was thousands of RegExp
    // constructions on the UI isolate per chat open (hot-path rule).
    final compiledRules =
        _sessionGenSettings.resolveOutputSanitizerEnabled(_storageService) &&
            _storageService.generationSettings.sanitiseExistingHistory
        ? compileSanitizerRules(
            _sessionGenSettings.resolveOutputSanitizerRules(_storageService),
          )
        : const <CompiledSanitizerRule>[];
    for (final m in dbMessages) {
      List<String> swipes;
      try {
        swipes = List<String>.from(jsonDecode(m.swipes));
      } catch (_) {
        swipes = [''];
      }

      // Model output ONLY — the feature's contract. Without the isUser
      // gate, a broad rule + retroactive-on rewrote the USER's own words in
      // memory, and the next _saveChat persisted the corruption. (Impersonate
      // drafts are sanitized at creation time, before they become user rows.)
      // System rows (backend notices, app status) are skipped too — rules
      // rewriting those could break the backend-notice dedupe comparison.
      if (!m.isUser &&
          m.sender != 'System' &&
          compiledRules.isNotEmpty &&
          swipes.isNotEmpty) {
        swipes = swipes
            .map((s) => sanitizeOutputCompiled(s, compiledRules))
            .toList();
      }

      List<int> swipeDurations;
      try {
        swipeDurations = List<int>.from(
          (jsonDecode(m.swipeDurations) as List).map((e) => (e as num).toInt()),
        );
      } catch (_) {
        swipeDurations = [0];
      }

      final safeSwipeIndex = (m.swipeIndex >= 0 && m.swipeIndex < swipes.length)
          ? m.swipeIndex
          : 0;

      _messages.add(
        ChatMessage(
          text: swipes.isNotEmpty ? swipes[safeSwipeIndex] : '',
          sender: m.sender,
          isUser: m.isUser,
          characterId: m.characterId,
          swipes: swipes,
          swipeIndex: safeSwipeIndex,
          swipeDurations: swipeDurations,
          metadata: m.metadata != null
              ? Map<String, dynamic>.from(jsonDecode(m.metadata!))
              : null,
          swipeMetadata: m.swipeMetadata != null
              ? (jsonDecode(m.swipeMetadata!) as List<dynamic>)
                    .map(
                      (e) => e != null
                          ? Map<String, dynamic>.from(e as Map)
                          : null,
                    )
                    .toList()
              : null,
        ),
      );
    }

    if (_messages.isNotEmpty) {
      _lorebookScanner.scanLatest();
    }
    _restoreGreetingIndex();
  }

  /// Hydrates every session-scoped scalar the two load paths share, from one
  /// [Session] row: metadata (author note, summary, name/description, look
  /// selection, fork lineage), relationship scalars (RAW persisted values —
  /// the legacy ±150→×2 era wrappers were deleted 2026-07-27; see the
  /// era-heuristic warning atop relationship_service.dart), realism/mood/
  /// emotion, time, NSFW, needs (seed-then-overlay so a blank saved vector
  /// can't clobber defaults), the "enjoys low hygiene" re-sync, per-chat
  /// theme overrides, chaos mode, transient-flag zeroing, and the
  /// session-scoped growth-ring cache.
  ///
  /// Extracted per docs/design/session-load-refactor.md Step 2. Two fixes by
  /// construction: chaos-mode scalars now load on the history-picker path too
  /// (they only loaded on library open, so picked sessions lost Chaos Mode
  /// state), and fixation truncation now runs AFTER the relationship load on
  /// both paths (loadSession used to sanitize the PREVIOUS session's fixation
  /// before loading this one's).
  ///
  /// Callers keep what genuinely differs: group-realism/scene-guest branch,
  /// objectives zeroing (library path only), per-chat gen settings placement
  /// (must precede message hydration for the retroactive sanitizer), and the
  /// persona activation. Both load paths restore the row's persona so a
  /// hydrate save cannot stamp the previous chat's live persona onto the
  /// row. The default is still unmoved (setActivePersona is chat-scoped).
  Future<void> _hydrateSessionScalars(Session s) async {
    _authorNote = s.authorNote;
    _authorNoteStrength = s.authorNoteDepth;
    _summary = s.summary ?? '';
    _summaryLastIndex = s.summaryLastIndex ?? 0;
    _sessionName = s.name;
    _sessionDescription = s.description;
    _selectedLooks = decodeSelectedLooks(s.selectedLookAvatarId);
    _parentSessionId = s.parentSession;
    _forkIndex = s.forkIndex;
    _relationshipService.loadScalars(
      affectionScore: s.affectionScore,
      longTermScore: s.longTermScore,
      trustLevel: s.trustLevel,
      activeFixation: s.activeFixation,
      fixationLifespan: s.fixationLifespan,
      spatialStance: s.spatialStance,
      withUser: s.withUser,
      trustRepairPending: s.trustRepairPending,
      turnsSinceLongTermCheck: s.turnsSinceLongTermCheck,
      shortTermDeltasSummary: s.shortTermDeltasSummary,
    );
    // The fixation coming out of the LLM can sometimes be a full paragraph
    // instead of a short topic — truncate to keep the UI and prompts sane.
    _relationshipService.sanitizeFixationIfTooLong();
    _realismEnabled = s.realismEnabled;
    _characterEmotion = s.characterEmotion;
    _emotionIntensity = s.emotionIntensity;
    _timeService.loadTimeScalars(
      timeOfDay: s.timeOfDay,
      dayCount: s.dayCount,
      startDayOfWeek: s.startDayOfWeek,
      storyClock: s.storyClock,
      storyStartDate: s.storyStartDate,
      // The saved per-chat value, NOT AND-ed with the global default. That
      // global is a seed-time ceiling: the four seedFromV2OrExt callers apply
      // it when a chat is first created ("Global ceiling applied before
      // passing"). Applying it again on every load would let switching the
      // global off retroactively disable time in chats the user had already
      // turned it on for. Until now the AND was computed and then thrown away
      // by loadTimeScalars, so it was inert; assigning the parameter without
      // removing it here would have quietly switched that behaviour on.
      passageOfTimeEnabled: s.passageOfTimeEnabled,
    );
    // Freeze a synthesised story date into the row the FIRST time we invent it.
    // The v38 ladder note promised legacy rows would "synthesize on first
    // load", but nothing wrote the result back, and the synthesis is anchored
    // on the real-world calendar — so the in-story date silently followed
    // whatever day the chat was opened on (96 of 109 sessions in the
    // maintainer's library were still in that state). A full save would have
    // fixed it, but a save only happens when you send a message: opening a
    // chat, reading it and closing it left the date free to move again.
    //
    // A partial patch, not _saveChat(): we are mid-hydration, so writing the
    // whole row here would persist the half-loaded needs/pockets/chaos state
    // that the lines below have not restored yet. Unawaited for the same reason
    // the other load-path writes are — the open path must not block on disk.
    if (_timeService.canonicalClockWasSynthesised) {
      unawaited(
        _db.patchSession(
          SessionsCompanion(
            id: drift.Value(s.id),
            storyClock: drift.Value(_timeService.storyClockIso),
            storyStartDate: drift.Value(_timeService.storyStartDateIso),
            startDayOfWeek: drift.Value(_timeService.startDayOfWeekAnchor),
            timeOfDay: drift.Value(_timeService.timeOfDay),
            dayCount: drift.Value(_timeService.dayCount),
          ),
        ),
      );
    }
    _nsfwService.loadNsfwScalars(
      nsfwCooldownEnabled: s.nsfwCooldownEnabled,
      arousalLevel: s.arousalLevel,
      cooldownTurnsRemaining: s.cooldownTurnsRemaining,
      cooldownTurnsTotal: s.cooldownTurnsTotal,
    );
    _needsSimEnabled = s.needsSimEnabled;
    _objectivesEnabled = s.objectivesEnabled;
    if (_needsSimEnabled) {
      // Seed defaults first, then overlay the saved vector ONLY when it has
      // values. A blank saved vector (e.g. needs was toggled on mid-chat before
      // it seeded) must NOT clobber the defaults, or the sidebar shows no scores.
      _needsSimulation.initializeFresh();
      final nv = s.needsVector;
      final saved = (nv is String && nv.isNotEmpty)
          ? (jsonDecode(nv) as Map).cast<String, int>()
          : <String, int>{};
      if (saved.isNotEmpty) {
        _needsSimulation.restoreFromSnapshot({'vector': saved});
      }
    } else {
      _needsSimulation.clearVector();
    }

    // v47 — restore the 1:1 pockets record. Group members' records ride
    // groupRealismState and are restored with it; this is the half that had no
    // home and so was silently dropped on every reload.
    //
    // Restored regardless of whether Pockets is currently switched on: a
    // record only exists because it was on at the time, and rolling a chat
    // open must not be the thing that empties their hands.
    final pj = s.pockets;
    _pockets = (pj is String && pj.isNotEmpty)
        ? Pockets.fromJson(jsonDecode(pj))
        : null;
    // No saved record means this chat has never run the pass, so fall back to
    // what the card starts them with — otherwise the sidebar reads empty until
    // after the first reply and an author who just set a wardrobe concludes it
    // did not save. Skipped when a record exists: the chat has moved on.
    seedPocketsFromCards();

    _todayObjectiveId = s.todayObjectiveId;
    _todayObjectiveText = null;

    // Re-sync from the character's current setting so that toggling
    // "Enjoys low hygiene" on the character affects existing chats on next load.
    _enjoysLowHygiene =
        _activeCharacter?.frontPorchExtensions?.enjoysLowHygiene ?? false;

    // Load per-chat theme overrides.
    try {
      final themeJson = await _db.getThemeOverrides(s.id);
      _sessionThemeOverrides = ChatThemeOverrides.fromJsonString(themeJson);
    } catch (_) {
      _sessionThemeOverrides = ChatThemeOverrides();
    }

    // Context Budget bars from the last real send (empty on older chats).
    try {
      await _loadContextBudgetForSession(s.id);
    } catch (_) {
      _clearContextBudget();
    }

    _needsSimulation.resetBuffers();
    // Chaos scalars — the shared load is what fixed session-load-refactor.md
    // bug #1 (loadSession never loaded these, so history-picked chats lost
    // Chaos Mode state and pressure reset to defaults).
    _chaosModeService.loadScalars(
      modeEnabled: s.chaosModeEnabled,
      pressure: s.chaosPressure,
    );
    debugPrint(
      '[ChatService] session scalars hydrated: arousal=${_nsfwService.arousalLevel}, fixation=${_relationshipService.activeFixation}/${_relationshipService.fixationLifespan}',
    );

    // Transient-flag zeroing shared by both loaded paths (keep reset blocks in sync).
    _summaryPaused = false;
    _isSummaryGenerating = false;
    _isGrowthPassRunning = false;

    // Cache growth rings (and any not-yet-distilled legacy evolved blobs) for
    // this session so the injection layer can read them synchronously —
    // scoped to the session, not the character (1:1 + group both).
    await _refreshGrowthCache();
  }

  /// Chat-scoped only — never moves [UserPersonaService.defaultPersonaId].
  Future<void> _activateSessionPersona(Session session) async {
    final sessionPersonaId = session.userPersonaId;
    final knownPersona =
        sessionPersonaId != null &&
        _userPersonaService.personas.any((p) => p.id == sessionPersonaId);
    await _userPersonaService.setActivePersona(
      knownPersona ? sessionPersonaId : _userPersonaService.defaultPersonaId,
    );
  }

  /// Diary targets for LLMerta porch import: library stableGroupId (match) +
  /// journal characterId (plant key). 1:1 uses the same id for both; group
  /// members match on originStableId and plant under the live card id.
  Future<List<PorchDiaryTarget>> _buildPorchDiaryTargets() async {
    if (_activeGroup == null && _activeCharacter != null) {
      final id = _getCharacterIdFromCard(_activeCharacter!);
      return [PorchDiaryTarget(libraryStableGroupId: id, diaryCharacterId: id)];
    }
    if (_activeGroup == null) return const [];

    final repo = _groupChatRepository;
    if (repo == null) {
      // Fall back to live roster stable ids (origin may equal library for
      // many members whose avatar stem matches the library basename).
      return [
        for (final c in _groupCharacters)
          PorchDiaryTarget(
            libraryStableGroupId: _getCharacterIdFromCard(c),
            diaryCharacterId: _getCharacterIdFromCard(c),
          ),
      ];
    }

    final rows = await repo.getMembersForGroup(_activeGroup!.id);
    final library = _characterRepository?.characters ?? const <CharacterCard>[];
    final targets = <PorchDiaryTarget>[];
    for (final m in rows) {
      if (m.avatarFilename == null) continue;
      final resolvedPath = path.join(
        _storageService.groupsDir.path,
        _activeGroup!.id,
        'avatars',
        m.avatarFilename!,
      );
      final diaryId = path.basenameWithoutExtension(resolvedPath);
      final origin = m.originStableId;
      final matchId = (origin != null && origin.isNotEmpty)
          ? origin
          : (MemberOriginResolver.resolve(
                  stampedOriginStableId: null,
                  memberName: m.name,
                  libraryCharacters: library,
                )?.stableGroupId ??
                diaryId);
      targets.add(
        PorchDiaryTarget(
          libraryStableGroupId: matchId,
          diaryCharacterId: diaryId,
        ),
      );
    }
    return targets;
  }

  /// Scan mailbox and plant into this session; never throws into open path.
  Future<void> _maybeImportPorchMemories() async {
    final sessionId = _currentSessionId;
    if (sessionId == null) return;
    final personaId = _userPersonaService.persona.id;
    if (personaId.isEmpty) return;
    try {
      final targets = await _buildPorchDiaryTargets();
      if (targets.isEmpty) return;
      await _porchMemoryImport.tryImportForSession(
        sessionId: sessionId,
        userPersonaId: personaId,
        targets: targets,
      );
    } catch (e) {
      debugPrint('[PorchMemories] session hook failed: $e');
    }
  }
}
