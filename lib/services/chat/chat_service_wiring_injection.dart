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

/// Builders for the prompt-injection leaves (author note, relationship,
/// emotion, behavioral, time, weather, ambition, promise/debt, nsfw, chaos,
/// needs, and the realism-state composer), plus their supporting lore/world
/// helper methods (the lorebook scanner/injector builders, the group lore
/// enumerator, world/biome reload + attach, and the chat macro-context
/// builder). Extracted verbatim from `chat_service.dart` — zero behaviour
/// change.
extension ChatServiceWiringInjection on ChatService {
  /// Returns all currently active lorebook entries (enabled + (triggered or constant))
  /// for the active group context. Includes:
  /// - Group-level lorebook
  /// - Lorebooks from worlds attached to the group
  /// - Per-character lorebooks (and their worlds) if `inheritCharacterLorebooks` is true
  ///
  /// This is intended for UI display (e.g. sidebar) to show what lore is currently "in play".
  List<LorebookEntry> getActiveGroupLoreEntries() {
    if (_activeGroup == null) return const [];
    // Post-group-filter truth (what actually injects), deduplicated by
    // content to avoid showing the exact same lore text twice.
    final seen = <String>{};
    return [
      for (final e in _lorebookInjector.activeEntries(
        sessionSeed: _currentSessionId ?? '',
      ))
        if (seen.add(e.content)) e,
    ];
  }

  // ── Lorebook scanner (extracted to LorebookScanner) ────────────────────────
  // Keyword scan (set isTriggered + remaining=sticky), decrement (post-AI
  // pre-set only), and reset of non-const trigger state live in
  // _lorebookScanner (plain class). ChatService owns via late final + thin
  // delegations at *all* call sites.
  // The entry universe comes from ONE enumerator: _collectLoreRefs →
  // collectLoreEntryRefs (group book + group worlds + member/1:1 books +
  // attached worlds). Scanning always covers everything (inherit=true);
  // the group's inheritCharacterLorebooks flag only filters injection and
  // the sidebar (getActiveGroupLoreEntries), matching prior behavior.
  // 1:1 vs group parity: scanner processes whatever the enumerator yields.
  // Reset hygiene: resetLorebookTriggerState() called from every keep-sync
  // site (startNewChat 1:1+group/ext+non-ext, setActive*, _load empty/
  // 0-session, setActiveGroup defensive+post, etc).
  LorebookScanner _buildLorebookScanner() {
    return LorebookScanner(
      onNotify: notifyListeners,
      getEntryRefs: () => _collectLoreRefs(inheritOverride: true),
      getRecentMessages: (count) {
        // Scan think-stripped prose (promptText), not raw .text — reasoning
        // that names a lore key used to false-trigger entries into the next
        // prompt (prompt-assembly audit 2026-08-11).
        final includeNames = _storageService.lorebookSettings.includeNames;
        final start = _messages.length > count ? _messages.length - count : 0;
        return [
          for (final m in _messages.sublist(start))
            m.characterId == '__director__'
                ? '[Director: ${m.text}]'
                : (includeNames
                      ? m.toPromptHistoryLine()
                      : m.promptText),
        ];
      },
      getGlobalScanDepth: () => _storageService.lorebookSettings.scanDepth,
      getRecursiveScan: () => _storageService.lorebookSettings.recursiveScan,
      getMaxRecursionSteps: () =>
          _storageService.lorebookSettings.maxRecursionSteps,
      timedEffects: _loreTimedEffects,
      getChatLength: () => _messages.length,
      resolveKeyMacros: (key) {
        final ch =
            _activeCharacter ??
            (_groupCharacters.isNotEmpty ? _groupCharacters.first : null);
        if (ch == null) return key;
        return _macroResolver.resolve(
          key,
          _buildChatMacroContext(ch),
          section: 'lorekeys',
        );
      },
    );
  }

  // Pure-read injection engine (positions, ordering, budget, inclusion
  // groups). Consumes the same enumerator as the scanner but honors the
  // group's inherit flag (injection semantics).
  LorebookInjector _buildLorebookInjector() {
    return LorebookInjector(
      getEntryRefs: () => _collectLoreRefs(),
      getSettings: () => _storageService.lorebookSettings,
      isStickyActive: (e) =>
          _loreTimedEffects.isStickyActive(e, _messages.length),
    );
  }

  // The group lorebook is stored as a JSON string on the group row. Parse it
  // ONCE and keep the live instance — the scanner writes trigger state onto
  // these entry objects, so a fresh parse per read (the pre-Phase-2 behavior)
  // silently discarded every keyword trigger and left group books constant-only.
  // String-compare invalidation: editing the book in group settings replaces
  // the JSON string, which re-parses (and intentionally clears trigger state,
  // same as editing semantics elsewhere).
  Lorebook? get _activeGroupLorebook {
    final raw = _activeGroup?.groupLorebook ?? '';
    if (raw.isEmpty) {
      _cachedGroupBook = null;
      _cachedGroupBookJson = null;
      return null;
    }
    if (_cachedGroupBookJson != raw) {
      try {
        _cachedGroupBook = Lorebook.fromJson(
          jsonDecode(raw) as Map<String, dynamic>,
        );
      } catch (_) {
        _cachedGroupBook = Lorebook(entries: []);
      }
      _cachedGroupBookJson = raw;
    }
    return _cachedGroupBook;
  }

  Future<void> _reloadChatWorldIds() async {
    final sid = _currentSessionId;
    if (sid == null) {
      _chatWorldIds = const [];
      _biomeSchedule = const BiomeSchedule();
      return;
    }
    try {
      // A chat opened BEFORE its character had a world predates any decision
      // about attachments, so its empty list means "undecided" — give it the
      // character's worlds now. Chats where the user actually chose (including
      // choosing none) are flagged and skipped, so a deliberate detach sticks.
      final refs = _activeGroup == null
          ? (_activeCharacter?.worldNames ?? const <String>[])
          : const <String>[];
      if (refs.isNotEmpty) {
        await _worldRepository.backfillChatWorldsFromCharacter(
          chatId: sid,
          characterWorldRefs: refs,
        );
      }
      _chatWorldIds = await _worldRepository.getChatWorldIds(sid);
    } catch (e) {
      debugPrint('[ChatService] chat world load failed: $e');
      _chatWorldIds = const [];
    }
    await _reloadBiomeSchedule();
  }

  Future<void> _reloadBiomeSchedule() async {
    final sid = _currentSessionId;
    if (sid == null) {
      _biomeSchedule = const BiomeSchedule();
      return;
    }
    try {
      final rows = await _worldRepository.getChatBiomeSpanRows(sid);
      _biomeSchedule = BiomeSchedule.fromJsonSpans(
        rows: rows,
        worldDefault: _worldDefaultBiome,
      );
    } catch (e) {
      debugPrint('[ChatService] biome schedule load failed: $e');
      _biomeSchedule = BiomeSchedule(worldDefault: _worldDefaultBiome);
    }
  }

  Future<void> setChatWorldIds(List<String> worldIds) async {
    final sid = _currentSessionId;
    if (sid == null) return;
    await _worldRepository.setChatWorlds(sid, worldIds);
    _chatWorldIds = List.unmodifiable(worldIds);
    await _reloadBiomeSchedule();
    notifyListeners();
  }

  /// Insert a mid-chat climate changeover from [dayCount] onward.
  Future<void> setChatClimate(Biome biome) async {
    final sid = _currentSessionId;
    if (sid == null) return;
    final day = _timeService.dayCount < 1 ? 1 : _timeService.dayCount;
    await _worldRepository.setChatBiome(
      chatId: sid,
      dayCount: day,
      biome: biome,
    );
    await _reloadBiomeSchedule();
    notifyListeners();
  }

  List<LoreEntryRef> _collectLoreRefs({bool? inheritOverride}) {
    return collectLoreEntryRefs(
      characters: _activeGroup != null
          ? _groupCharacters
          : (_activeCharacter != null
                ? [_activeCharacter!]
                : const <CharacterCard>[]),
      chatLorebook: _loreTimedEffects.chatLorebook,
      groupLorebook: _activeGroupLorebook,
      chatWorldIds: _chatWorldIds,
      groupWorldNames: _activeGroup?.worldIds ?? const [],
      resolveWorld: _worldRepository.resolveWorld,
      inherit:
          inheritOverride ?? (_activeGroup?.inheritCharacterLorebooks ?? true),
    );
  }

  /// Full chat-context MacroContext for prompt builds: card fields, group
  /// roster, last messages, idle clock, and the macro variable stores
  /// (locals ride _loreTimedEffects per chat; globals live in settings).
  /// Shared by generation, impersonation, and lore-key resolution.
  MacroContext _buildChatMacroContext(
    CharacterCard speaking, {
    String? scenario,
  }) {
    ChatMessage? lastUser;
    ChatMessage? lastChar;
    for (final m in _messages.reversed) {
      if (m.characterId == '__director__') continue;
      lastUser ??= m.isUser ? m : null;
      lastChar ??= !m.isUser ? m : null;
      if (lastUser != null && lastChar != null) break;
    }
    return MacroContext(
      userName: _userPersonaService.persona.name,
      characterName: speaking.name,
      chatId: _currentSessionId,
      characterId: speaking.dbId,
      description: speaking.description,
      personality: _getEffectivePersonality(speaking),
      scenario: scenario ?? speaking.scenario,
      userPersona: _userPersonaService.persona.persona,
      groupMemberNames: _activeGroup != null
          ? [for (final c in _groupCharacters) c.name]
          : null,
      lastMessage: _messages.isNotEmpty ? _messages.last.displayText : null,
      lastUserMessage: lastUser?.displayText,
      lastCharMessage: lastChar?.displayText,
      idleDuration: _lastUserMessageAt == null
          ? null
          : DateTime.now().difference(_lastUserMessageAt!),
      getLocalVar: (n) => _loreTimedEffects.localMacroVars[n],
      setLocalVar: (n, v) => _loreTimedEffects.localMacroVars[n] = v,
      getGlobalVar: _storageService.lorebookSettings.getGlobalMacroVar,
      setGlobalVar: _storageService.lorebookSettings.setGlobalMacroVar,
    );
  }

  AuthorNoteBuilder _buildAuthorNoteBuilder() {
    return AuthorNoteBuilder(
      // Objectives off ⇒ nothing about quests reaches the model. Reading the
      // gate here rather than clearing _activeObjectives keeps the rows intact
      // for when the switch comes back on.
      getActiveObjectives: () => objectivesActive ? _activeObjectives : const [],
      getPrimaryObjective: () => primaryObjective,
      tasksForObjective: (o) => tasksForObjective(o),
      getSecondaryObjectives: () => secondaryObjectives,
    );
  }

  RelationshipInjection _buildRelationshipInjection() {
    return RelationshipInjection(
      relationshipService: _relationshipService,
      getRealismEnabled: () => _realismEnabled,
      getIsGroupNonObserverMode: () => (_activeGroup != null && !_observerMode),
      getCurrentSpeakerIdForRealism: _getCurrentSpeakerIdForRealism,
      getGroupCharacters: () => _groupCharacters,
      getActiveCharacter: () => _activeCharacter,
      getShouldTrackInterCharacterRelationships: () =>
          _shouldTrackInterCharacterRelationships,
      getGroupInt: (charId, key, {int defaultValue = 0}) =>
          _groupIntOr(charId, key, defaultValue),
      getCharacterIdFromCard: _getCharacterIdFromCard,
      getInterCharacterRelationships:
          _relationshipService.getInterCharacterRelationships,
    );
  }

  EmotionInjection _buildEmotionInjection() {
    return EmotionInjection(
      getRealismEnabled: () => _realismEnabled,
      getCharacterEmotion: () => _characterEmotion,
      getEmotionIntensity: () => _emotionIntensity,
    );
  }

  BehavioralInjection _buildBehavioralInjection() {
    return BehavioralInjection(
      relationshipService: _relationshipService,
      getRealismEnabled: () => _realismEnabled,
      getOccupation: () =>
          _activeCharacter?.frontPorchExtensions?.occupation ?? '',
      getHours: () => _activeCharacter?.frontPorchExtensions?.hours ?? '',
      getTimeOfDay: () => _timeService.timeOfDay,
      getIsGroup: () => _activeGroup != null,
    );
  }

  TimeInjection _buildTimeInjection() =>
      TimeInjection(timeService: _timeService);

  /// Climate from the first attached world that carries one (Living Worlds).
  /// Used as the schedule default when no mid-chat span covers a day.
  /// Temperate when nothing is attached — byte-identical to pre-biome weather.
  Biome get _worldDefaultBiome {
    World? pick(String ref) => _worldRepository.resolveWorld(ref);
    // A custom climate is branded 'world:<id>' so every climate picker can
    // match the active climate to its option by id alone.
    Biome resolveFor(World w) {
      final b = Biome.resolve(biomeId: w.biomeId, biomeJson: w.biomeJson);
      return w.biomeJson != null ? b.withId('world:${w.id}') : b;
    }

    for (final id in _chatWorldIds) {
      final w = pick(id);
      if (w == null) continue;
      if (w.biomeId != null || w.biomeJson != null) {
        return resolveFor(w);
      }
    }
    final group = _activeGroup;
    if (group != null) {
      for (final ref in group.worldIds) {
        final w = pick(ref);
        if (w == null) continue;
        if (w.biomeId != null || w.biomeJson != null) {
          return resolveFor(w);
        }
      }
    }
    return Biome.temperate;
  }

  Biome _biomeAtDay(int day) => _biomeSchedule.biomeAt(day);

  /// The segment BEFORE the current one — same day for afternoon/evening/
  /// night, yesterday's night for a morning (cross-day continuity, so
  /// "the rain has eased off" can span the night). Null on day 1 mornings
  /// (nothing came before) and whenever weather is off.
  SegmentWeather? get previousSegmentWeather {
    final now = currentSegmentWeather;
    if (now == null) return null;
    final day = _timeService.dayCount;
    return switch (now.segment) {
      DaySegment.morning =>
        day <= 1
            ? null
            : WeatherSegments.segmentWeatherFor(
                sessionSeed: _currentSessionId!,
                dayCount: day - 1,
                date: _timeService.clock.subtract(const Duration(days: 1)),
                hour: 23,
                biomeAtDay: _biomeAtDay,
              ),
      DaySegment.afternoon => _segmentAt(7),
      DaySegment.evening => _segmentAt(14),
      DaySegment.night => _segmentAt(18),
    };
  }

  SegmentWeather _segmentAt(int hour) => WeatherSegments.segmentWeatherFor(
    sessionSeed: _currentSessionId!,
    dayCount: _timeService.dayCount,
    date: _timeService.clock,
    hour: hour,
    biomeAtDay: _biomeAtDay,
  );

  WeatherInjection _buildWeatherInjection() {
    return WeatherInjection(
      getWeather: () => currentSegmentWeather,
      getPreviousSegment: () => previousSegmentWeather,
      getUpcoming: () => upcomingWeather,
      suppressForeshadow: () =>
          _biomeSchedule.isSpanStart(_timeService.dayCount),
      // Condition skins (phase 2 step ④): renamed weather speaks by its new
      // name with stance-driven behavior on every prompt surface.
      getBiome: () => activeChatBiome,
    );
  }

  PlanInjection _buildPlanInjection() {
    return PlanInjection(
      getTodayLine: () => todaySentence,
      getPlannerEnabled: () =>
          _storageService.realismSettings.plannerEnabled,
      getActiveCharacter: () => _activeCharacter,
      getIsGroupNonObserverMode: () => (_activeGroup != null && !_observerMode),
      getCurrentSpeakerIdForRealism: _getCurrentSpeakerIdForRealism,
      getGroupCharacters: () => _groupCharacters,
      getCharacterIdFromCard: _getCharacterIdFromCard,
    );
  }

  AmbitionInjection _buildAmbitionInjection() {
    return AmbitionInjection(
      ambitionService: _ambitionService,
      getSessionId: () => _currentSessionId,
      getActiveCharacter: () => _activeCharacter,
      getIsGroupNonObserverMode: () => (_activeGroup != null && !_observerMode),
      getCurrentSpeakerIdForRealism: _getCurrentSpeakerIdForRealism,
      getGroupCharacters: () => _groupCharacters,
      getCharacterIdFromCard: _getCharacterIdFromCard,
    );
  }

  PreferencesInjection _buildPreferencesInjection() {
    return PreferencesInjection(
      getActiveCharacter: () => _activeCharacter,
      getIsGroupNonObserverMode: () => (_activeGroup != null && !_observerMode),
      getCurrentSpeakerIdForRealism: _getCurrentSpeakerIdForRealism,
      getGroupCharacters: () => _groupCharacters,
      getCharacterIdFromCard: _getCharacterIdFromCard,
      // The install's 18+ master switch — the SAME one that shows or hides
      // the After Dark group in Settings. A card may carry intimate
      // preferences; with 18+ off they stay out of the prompt entirely rather
      // than relying on the model's discretion.
      getNsfwEnabled: () =>
          _storageService.realismSettings.adultThemesEnabled,
      // BOTH halves resolved here, so there is exactly one place the decision
      // is made. The engine half is a HARD dependency and not the usual
      // inherited gate: the feature is a loop — she asks, the user answers,
      // and being refused moves her mood into the next reply — and the judge
      // that scores the answer IS the engine. With realism off she would ask
      // for things and nothing would ever come of it.
      getIntimateAgencyEnabled: () =>
          _storageService.realismSettings.intimateAgencyEnabled &&
          _realismEnabled,
    );
  }

  InventoryInjection _buildInventoryInjection() {
    return InventoryInjection(
      getActiveCharacter: () => _activeCharacter,
      getIsGroupNonObserverMode: () => (_activeGroup != null && !_observerMode),
      getCurrentSpeakerIdForRealism: _getCurrentSpeakerIdForRealism,
      getGroupCharacters: () => _groupCharacters,
      getCharacterIdFromCard: _getCharacterIdFromCard,
      // Off means off: with the switch down the record is never read, so the
      // fragment is absent rather than stale. The check itself now lives in
      // pocketsFor — one gate for every surface, rather than each caller
      // remembering to ask (the sidebar forgot).
      getPockets: pocketsFor,
      // Morning-anchored: the prompt's set-aside filter must agree with the
      // pass/sidebar/facade (all on storySetAside day now) or the injection
      // would hide an outfit the record still holds after midnight.
      getCurrentDay: () => _timeService.morningAnchoredDayCount,
      // Get-and-mark: a prompt that carries an intro flags it so the NEXT
      // user turn drops it (see _dropConsumedItemIntros). Marking here and
      // clearing there is what lets a regen rebuild reproduce the reaction.
      takePendingIntros: (charId) {
        // Session filter: only intros added in THIS chat fire — an add made
        // in another session stays queued for that chat (see the session
        // stamp on _PendingItemIntro). Mark included only what fired.
        final list = _pendingItemIntrosOf[this]?[charId]
            ?.where((n) => n.session == _currentSessionId)
            .toList();
        if (list == null || list.isEmpty) {
          return const <({String item, bool gift, PocketSection section})>[];
        }
        for (final n in list) {
          n.included = true;
        }
        return [
          for (final n in list)
            (item: n.item, gift: n.gift, section: n.section),
        ];
      },
      getUserName: () => _userPersonaService.persona.name,
    );
  }

  PromiseDebtInjection _buildPromiseDebtInjection() {
    return PromiseDebtInjection(
      promiseDebtService: _promiseDebtService,
      getSessionId: () => _currentSessionId,
      getActiveCharacter: () => _activeCharacter,
      getIsGroupNonObserverMode: () => (_activeGroup != null && !_observerMode),
      getCurrentSpeakerIdForRealism: _getCurrentSpeakerIdForRealism,
      getGroupCharacters: () => _groupCharacters,
      getCharacterIdFromCard: _getCharacterIdFromCard,
      getUserName: () => _userPersonaService.persona.name,
    );
  }

  NsfwInjection _buildNsfwInjection() {
    return NsfwInjection(
      nsfwService: _nsfwService,
      getRealismEnabled: () => _realismEnabled,
      getActiveCharacter: () => _activeCharacter,
      getIsGroupNonObserverMode: () => (_activeGroup != null && !_observerMode),
      getCurrentSpeakerIdForRealism: _getCurrentSpeakerIdForRealism,
      getGroupCharacters: () => _groupCharacters,
      getCharacterIdFromCard: _getCharacterIdFromCard,
    );
  }

  ChaosInjection _buildChaosInjection() {
    return ChaosInjection(
      chaosModeService: _chaosModeService,
      getActiveCharacter: () => _activeCharacter,
    );
  }

  NeedsInjection _buildNeedsInjection() {
    return NeedsInjection(
      needsSimulation: _needsSimulation,
      getNeedsSimEnabled: () => _needsSimEnabled,
      getRealismEnabled: () => _realismEnabled,
      getIsGroupNonObserverMode: () => (_activeGroup != null && !_observerMode),
      getCurrentSpeakerIdForRealism: _getCurrentSpeakerIdForRealism,
      getGroupCharacters: () => _groupCharacters,
      getEnjoysLowHygiene: () => enjoysLowHygiene,
      getGroupNeeds: _getGroupNeeds,
      getCharacterIdFromCard: _getCharacterIdFromCard,
    );
  }

  /// New central composer for the full speaker-internal realism snapshot.
  /// Replaces the previous loose concatenation of the individual builders.
  /// This gives the model one clearly grouped, number-first view of relationship,
  /// emotion, time, needs (with x/100), behavioral anchors, nsfw state, etc.
  RealismStateInjection _buildRealismStateInjection() {
    return RealismStateInjection(
      // Both independent of the Realism Engine. Promises are Journal cards, so
      // that gate also requires the Journal — without it there is nothing to
      // read.
      //
      // Ambitions additionally require OBJECTIVES (maintainer, 2026-08-07).
      // "Cost nothing" was never true — the goals are card-authored, but the
      // fragment is rebuilt into the prompt every single turn, so it is paid
      // for on every turn. And with Objectives off, finishing a quest — the
      // only thing that moves ambition progress — can never happen, so the
      // stage word ("just beginning") is frozen for the life of the chat.
      // Injecting it would bill the user, forever, for a line that cannot
      // change and describes a mechanism that is switched off.
      // Standing Mood: free (pure derivation), gated inside the leaf.
      getStandingMood: buildStandingMoodInjection,
      getAmbitionsEnabled: () =>
          _storageService.realismSettings.ambitionsEnabled && objectivesActive,
      getPromisesEnabled: () =>
          _storageService.realismSettings.promiseLedgerEnabled &&
          _storageService.memorySettings.journalEnabled,
      relationshipInjection: _relationshipInjection,
      emotionInjection: _emotionInjection,
      timeInjection: _timeInjection,
      weatherInjection: _weatherInjection,
      ambitionInjection: _ambitionInjection,
      planInjection: _planInjection,
      preferencesInjection: _preferencesInjection,
      inventoryInjection: _inventoryInjection,
      promiseDebtInjection: _promiseDebtInjection,
      behavioralInjection: _behavioralInjection,
      nsfwInjection: _nsfwInjection,
      needsInjection: _needsInjection,
      // `_realismActiveThisMode`, NOT the bare `_realismEnabled` flag, and the
      // difference became load-bearing on 2026-08-08 when the caller's blanket
      // `if (_realismActiveThisMode)` around this whole block was removed.
      //
      // That wrapper was the only thing keeping the engine's fragments out of
      // the prompt in group Director mode and during AFK auto-responses, where
      // the engine is deliberately paused (`_realismActiveThisMode` is false
      // while `_realismEnabled` stays true). Un-gating the block without moving
      // this would have started injecting bond, trust, emotion, position and
      // fixation into two modes that have never seen them — a behaviour change
      // for engine-ON users, smuggled in under a fix for engine-OFF ones.
      //
      // Wired here, the engine fragments answer to exactly the condition they
      // always did, while the fragments that are not realism features keep
      // reaching the model in every mode.
      getRealismEnabled: () => _realismActiveThisMode,
      getClockRunningOverride: () => _clockRunning,
      // One-shot, opt-in (default OFF), coarse-worded, speculation-forbidding —
      // living-time-features.md §2 "Privacy by design". Lifted here from the
      // time fragment (2026-08-07) so it answers to its own gate: the note is
      // about WALL-CLOCK absence, and inheriting the story clock's gate is why
      // it never reached the model with the clock frozen.
      getAbsenceNote: () {
        if (!_storageService.absenceAckEnabled || !_absenceAckPending) {
          return null;
        }
        final phrase = absencePhrase;
        return phrase == null ? null : AbsenceTracker.ackNote(phrase);
      },
      getIsGroupNonObserverMode: () => (_activeGroup != null && !_observerMode),
      getCurrentSpeakerIdForRealism: _getCurrentSpeakerIdForRealism,
      getGroupCharacters: () => _groupCharacters,
      getActiveCharacter: () => _activeCharacter,
      getCharacterIdFromCard: _getCharacterIdFromCard,
    );
  }
}
