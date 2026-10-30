// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Prompt-injection leaf builders. Lore/world helpers stay
// on chat_service_wiring_injection.dart.
// objectivesActive stays the live AND.

part of '../chat_service.dart';

extension ChatServiceWiringInjectionLeaves on ChatService {
  AuthorNoteBuilder _buildAuthorNoteBuilder() {
    return AuthorNoteBuilder(
      // Objectives off ⇒ nothing about quests reaches the model. Reading the
      // gate here rather than clearing _activeObjectives keeps the rows intact
      // for when the switch comes back on.
      getActiveObjectives: () =>
          objectivesActive ? _activeObjectives : const [],
      getPrimaryObjective: () => primaryObjective,
      tasksForObjective: (o) => tasksForObjective(o),
      getSecondaryObjectives: () => secondaryObjectives,
      getStreakLine: () =>
          objectivesActive ? objectiveStreakLine(_objectiveTally.recent) : null,
      // In a group only the goal owner's replies count; the ids match because
      // both are _getCharacterIdFromCard.
      isResting: (o) =>
          o is Objective &&
          objectiveFixated(
            messages: _messages,
            questTexts: openQuestMentionTexts(
              o.objective,
              tasksForObjective(o),
            ),
            speakerId: _activeGroup != null ? o.characterId : null,
            ignore: _objectiveIgnoreTokens(),
          ),
    );
  }

  RelationshipInjection _buildRelationshipInjection() {
    return RelationshipInjection(
      relationshipService: _relationshipService,
      getRealismEnabled: () => _realismEnabled,
      getIsGroupNonObserverMode: () => _activeGroup != null,
      getCurrentSpeakerIdForRealism: _groupStore.currentSpeakerId,
      getGroupCharacters: () => _groupCharacters,
      getActiveCharacter: () => _activeCharacter,
      getShouldTrackInterCharacterRelationships: () =>
          _shouldTrackInterCharacterRelationships,
      getGroupInt: (charId, key, {int defaultValue = 0}) =>
          _groupStore.intOr(charId, key, defaultValue),
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
      getEmotionCause: () => _emotionCause,
      getEmotionHeldTurns: () => _emotionHeldTurns,
    );
  }

  BehavioralInjection _buildBehavioralInjection() {
    return BehavioralInjection(
      relationshipService: _relationshipService,
      getRealismEnabled: () => _realismEnabled,
      getOccupation: () => _groupStore.workFieldsForCurrentSpeaker().occupation,
      getHours: () => _groupStore.workFieldsForCurrentSpeaker().hours,
      getOccupationBrief: () =>
          _groupStore.workFieldsForCurrentSpeaker().occupationBrief,
      getWorkDays: () => _groupStore.workFieldsForCurrentSpeaker().workDays,
      getClockMinutes: () => _timeService.clockMinutes,
      getWeekday: () => _timeService.clock.weekday,
      getIsGroup: () => _activeGroup != null,
    );
  }

  TimeInjection _buildTimeInjection() =>
      TimeInjection(timeService: _timeService);

  /// Climate from the Setting's chain author (Living Worlds, locations
  /// slice 2): a location inherits the nearest climate-enabled ancestor;
  /// the custom-climate dropdown id is `world:<climate-author-id>`. Lore
  /// attachments never author the schedule default. Group.worldIds ghost
  /// removed — decided empty stays empty. Temperate is a schedule
  /// placeholder only; the weather gate stays off when the chain has no
  /// climate author.
  /// The full biome an authoring world speaks: built-in id, custom JSON
  /// renamed `world:<id>`, or temperate when it carries no climate data.
  /// One definition for the schedule default and for the changeover spans
  /// a Setting swap records, so the two can never disagree.
  Biome _biomeOfAuthor(World w) {
    if (w.biomeId == null && w.biomeJson == null) return Biome.temperate;
    final b = Biome.resolve(biomeId: w.biomeId, biomeJson: w.biomeJson);
    return w.biomeJson != null ? b.withId('world:${w.id}') : b;
  }

  Biome get _worldDefaultBiome {
    final id = _chatPlaceSlots.primaryId;
    if (id == null) return Biome.temperate;
    final w = _worldRepository.climateAuthorFor(id);
    if (w == null) return Biome.temperate;
    return _biomeOfAuthor(w);
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
      getPlannerEnabled: () => _storageService.realismSettings.plannerEnabled,
      getClockMinutes: () => _timeService.clockMinutes,
      getWeekday: () => _timeService.clock.weekday,
      getActiveCharacter: () => _activeCharacter,
      getIsGroupNonObserverMode: () => _activeGroup != null,
      getCurrentSpeakerIdForRealism: _groupStore.currentSpeakerId,
      getGroupCharacters: () => _groupCharacters,
      getCharacterIdFromCard: _getCharacterIdFromCard,
    );
  }

  AmbitionInjection _buildAmbitionInjection() {
    return AmbitionInjection(
      ambitionService: _ambitionService,
      getSessionId: () => _currentSessionId,
      getActiveCharacter: () => _activeCharacter,
      getIsGroupNonObserverMode: () => _activeGroup != null,
      getCurrentSpeakerIdForRealism: _groupStore.currentSpeakerId,
      getGroupCharacters: () => _groupCharacters,
      getCharacterIdFromCard: _getCharacterIdFromCard,
    );
  }

  PreferencesInjection _buildPreferencesInjection() {
    return PreferencesInjection(
      getActiveCharacter: () => _activeCharacter,
      getIsGroupNonObserverMode: () => _activeGroup != null,
      getCurrentSpeakerIdForRealism: _groupStore.currentSpeakerId,
      getGroupCharacters: () => _groupCharacters,
      getCharacterIdFromCard: _getCharacterIdFromCard,
      // The install's 18+ master switch — the SAME one that shows or hides
      // the After Dark group in Settings. A card may carry intimate
      // preferences; with 18+ off they stay out of the prompt entirely rather
      // than relying on the model's discretion.
      getNsfwEnabled: () => _storageService.realismSettings.adultThemesEnabled,
      // BOTH halves resolved here, so there is exactly one place the decision
      // is made. The engine half is a HARD dependency and not the usual
      // inherited gate: the feature is a loop — they ask, the user answers,
      // and being refused moves their mood into the next reply — and the judge
      // that scores the answer IS the engine. With realism off they would ask
      // for things and nothing would ever come of it.
      getIntimateAgencyEnabled: () =>
          _storageService.realismSettings.intimateAgencyEnabled &&
          _realismEnabled,
    );
  }

  InventoryInjection _buildInventoryInjection() {
    return InventoryInjection(
      getActiveCharacter: () => _activeCharacter,
      getIsGroupNonObserverMode: () => _activeGroup != null,
      getCurrentSpeakerIdForRealism: _groupStore.currentSpeakerId,
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
      // Get-and-mark, session-filtered; see PocketsLedger.takePendingIntros.
      takePendingIntros: (charId) => _pocketsLedger.takePendingIntros(charId),
      getUserName: () => _userPersonaService.persona.name,
    );
  }

  PromiseDebtInjection _buildPromiseDebtInjection() {
    return PromiseDebtInjection(
      getCurrentStoryDay: () => _clockRunning ? _timeService.dayCount : null,
      promiseDebtService: _promiseDebtService,
      getSessionId: () => _currentSessionId,
      getActiveCharacter: () => _activeCharacter,
      getIsGroupNonObserverMode: () => _activeGroup != null,
      getCurrentSpeakerIdForRealism: _groupStore.currentSpeakerId,
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
      getIsGroupNonObserverMode: () => _activeGroup != null,
      getCurrentSpeakerIdForRealism: _groupStore.currentSpeakerId,
      getGroupCharacters: () => _groupCharacters,
      getCharacterIdFromCard: _getCharacterIdFromCard,
      getMutualOpening: _mutualAfterglowOpening,
      getPcdActive: _pcdActive,
    );
  }

  /// PR 8: is this body's grey-drift window open — the opening turn plus
  /// their next two replies, counted from message history so regen and
  /// delete rewind it for free. One stamp-backed truth feeds both the
  /// ladder rung (opening branch only) and the emotion-eval note (the
  /// full window). Guests and roster-mates are excluded the way the
  /// mutual scan already excludes them.
  bool _pcdActive() {
    return pcdWindowActive(
      messages: _messages,
      speakerId: _activeGroup != null ? _groupStore.currentSpeakerId() : null,
      isUser: (m) => m.isUser || _isGuestAuthoredMessage(m),
      climaxStamped: (m) => m.activeMetadata?['climax_triggered'] == true,
      pcdStamped: (m) => m.activeMetadata?['pcd'] == true,
      speakerOf: (m) {
        final card = _resolveGroupSpeakerForMessage(m);
        return card == null ? null : _getCharacterIdFromCard(card);
      },
    );
  }

  /// PR 5: the mutual afterglow opening — the SAME beat's climax verdict
  /// said {{user}} came too. True only while the afterglow opening turn runs
  /// AND this speaker's latest climax-stamped reply carries `user_climaxed`.
  /// Never inferred: pre-PR-5 replies simply have no stamp, and a
  /// roster-mate's mutual beat is not this body's warmth.
  bool _mutualAfterglowOpening() {
    if (!_nsfwService.isOpeningAfterglowTurn) return false;
    final group = _activeGroup != null;
    for (final m in _messages.reversed) {
      if (m.isUser) continue;
      // A scene guest's prose is not the host's body (M7 review): the
      // mutual beat belongs to the character the lock is counting.
      if (_isGuestAuthoredMessage(m)) continue;
      final meta = m.activeMetadata;
      if (meta?['climax_triggered'] != true) continue;
      if (group) {
        final card = _resolveGroupSpeakerForMessage(m);
        if (card == null ||
            _getCharacterIdFromCard(card) != _groupStore.currentSpeakerId()) {
          continue;
        }
      }
      return meta?['user_climaxed'] == true;
    }
    return false;
  }

  ChaosInjection _buildChaosInjection() {
    return ChaosInjection(
      chaosModeService: _chaosModeService,
      // The member pinned for the turn in a group, the host in 1:1.
      getActiveCharacter: () => _groupStore.workSpeakerCard(),
    );
  }

  NeedsInjection _buildNeedsInjection() {
    return NeedsInjection(
      needsSimulation: _needsSimulation,
      getNeedsSimEnabled: () => _needsPass.active,
      getRealismEnabled: () => _realismEnabled,
      getIsGroupNonObserverMode: () => _activeGroup != null,
      getCurrentSpeakerIdForRealism: _groupStore.currentSpeakerId,
      getGroupCharacters: () => _groupCharacters,
      getEnjoysLowHygiene: () => enjoysLowHygiene,
      getGroupNeeds: _groupStore.needsOf,
      getCharacterIdFromCard: _getCharacterIdFromCard,
      getNeedsOff: () =>
          _activeCharacter?.frontPorchExtensions?.needsOff ?? const [],
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
      getStandingMood: () => _standingMood.injection,
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
      getOffStageLive: () =>
          _directing && _realismEnabled && !_autoResponseInProgress,
      getClockRunningOverride: () => _clockRunning,
      // One-shot, opt-in (default OFF), coarse-worded, speculation-forbidding —
      // living-time-features.md §2 "Privacy by design". Lifted here from the
      // time fragment (2026-08-07) so it answers to its own gate: the note is
      // about WALL-CLOCK absence, and inheriting the story clock's gate is why
      // it never reached the model with the clock frozen.
      getAbsenceNote: () {
        if (!_storageService.realismSettings.absenceAckEnabled ||
            !_absenceAckPending) {
          return null;
        }
        final phrase = absencePhrase;
        return phrase == null ? null : AbsenceTracker.ackNote(phrase);
      },
      getIsGroupNonObserverMode: () => _activeGroup != null,
      getCurrentSpeakerIdForRealism: _groupStore.currentSpeakerId,
      getGroupCharacters: () => _groupCharacters,
      getActiveCharacter: () => _activeCharacter,
      getCharacterIdFromCard: _getCharacterIdFromCard,
    );
  }
}
