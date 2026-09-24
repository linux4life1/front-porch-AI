// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

part of '../chat_service.dart';

/// Phase 0 import seed + session head for `.fpchat` (kept separate so the
/// package I/O file stays under the 500-line cap).
extension ChatServiceImportSeed on ChatService {
  // ── Phase 0: live-state seed for imported sessions ──────────────────────

  /// Full import seed: clear session lineage/guests/summary and reseed live
  /// Realism/Needs from the card/group so `_saveChat()` does not persist the
  /// previous open chat's bond/trust/arousal into the new row.
  ///
  /// Does **not** set `_isNewChat` (importer sets it after messages land).
  /// Does **not** call `_importAuthoredTask` (card currentTask is for fresh chats).
  Future<void> _seedLiveRealismForImportedSession() async {
    _cancelIdleTimer();

    _hasCompletedExchange = false;
    _awayPulse.reset();
    _greetingIndex = 0;

    _summary = '';
    // Caught-up blank journal for transcript-only imports; full packages
    // overwrite summary/cursor after this when restoring the suitcase.
    _summaryLastIndex = 0;
    _parentSessionId = null;
    _forkIndex = null;
    _selectedLooks.clear();
    _sessionGenSettings = ChatGenerationSettings();
    _clearContextBudget();
    _summaryPaused = false;
    _isSummaryGenerating = false;
    _isGrowthPassRunning = false;
    _activeObjectives = [];
    _messagesSinceLastCheck = 0;
    _isCheckingCompletion = false;
    _sceneGuest.ids.clear();
    _sceneGuest.cards.clear();
    _sceneGuest.pendingDeparture = null;
    _sceneGuest.pendingPickerFilter = null;
    _resetGuestActivityState();
    _sceneGuest.turnsSinceCastScan = 0;
    _sceneGuest.pendingDetection = null;
    _sceneGuest.offeredOrIgnoredNames.clear();

    if (_activeCharacter != null && _activeGroup == null) {
      final extSeed =
          _activeCharacter!.frontPorchExtensions ?? FrontPorchExtensions();
      _realismEnabled =
          extSeed.realismEnabled ||
          _storageService.realismSettings.realismDefault;
      _relationshipService.resetForFreshChat();
      _relationshipService.seedFromCardV2OrExt(
        shortTermBond: extSeed.shortTermBond,
        longTermBond: extSeed.longTermBond,
        trustLevel: extSeed.trustLevel,
      );
      _expressionService.resetForFreshChat();
      _lorebookScanner.resetLorebookTriggerState();
      _timeService.seedFromV2OrExt(
        dayCount: extSeed.dayCount.clamp(1, 9999),
        timeOfDay: extSeed.timeOfDay,
        storyStartDate: extSeed.storyStartDate,
        storyStartTime: extSeed.storyStartTime,
      );
      _applySeededPassageOfTime();
      _characterEmotion = extSeed.characterEmotion;
      _emotionIntensity = extSeed.emotionIntensity;
      // seedFromV2OrExt only sets the *enabled* flag — runtime arousal and
      // cooldown are zeroed explicitly on every other fresh path
      // (startNewChat). Without this, ST/.json import bleeds them.
      _nsfwService.seedFromV2OrExt(
        nsfwCooldownEnabled:
            extSeed.nsfwCooldownEnabled ||
            _storageService.realismSettings.nsfwCooldownDefault,
      );
      _nsfwService.resetRuntimeArousalAndCooldown();
      _chaosModeService.seedFromGroupOrExt(
        extSeed.chaosModeEnabled ||
            _storageService.realismSettings.chaosModeDefault,
        false,
      );
      _needsSimEnabled =
          extSeed.needsSimEnabled &&
          _storageService.realismSettings.needsSimDefault;
      _objectivesEnabled = _storageService.realismSettings.objectivesEnabled;
      _enjoysLowHygiene = extSeed.enjoysLowHygiene;
      if (_needsSimEnabled) {
        _needsSimulation.initializeFreshWithDefaults({
          'hunger': extSeed.needsBaselineHunger,
          'bladder': extSeed.needsBaselineBladder,
          'energy': extSeed.needsBaselineEnergy,
          'social': extSeed.needsBaselineSocial,
          'fun': extSeed.needsBaselineFun,
          'hygiene': extSeed.needsBaselineHygiene,
          'comfort': extSeed.needsBaselineComfort,
        });
      } else {
        _needsSimulation.clearVector();
      }
      _needsSimulation.resetBuffers();
      // Bleed guard for the prior open chat. Suitcase put-back is in
      // [_applySessionHeadFromPackage] — it must write even when this
      // card authored Pockets off (HIDES≠erase). Do not skip the null
      // when restore is gated: transcript-only import would keep the
      // previous hidden kit.
      _pockets = null;
    } else {
      _relationshipService.resetForFreshChat();
      _expressionService.resetForFreshChat();
      _timeService.resetForFreshChat();
      if (_activeGroup != null) {
        final timeSeed = parseGroupTimeSeed(
          _activeGroup!.defaultMemberRealismState,
          _activeGroup!.baselineRealismState,
        );
        if (timeSeed != null) {
          _timeService.seedFromV2OrExt(
            dayCount: timeSeed.dayCount,
            timeOfDay: timeSeed.timeOfDay,
            storyStartDate: timeSeed.storyStartDate,
            storyStartTime: timeSeed.storyStartTime,
          );
          _applySeededPassageOfTime();
        }
        _groupRealism = parseGroupRealismSeeds(
          _activeGroup!.defaultMemberRealismState,
        ).map((k, v) => MapEntry(k, GroupMemberRealism.fromJson(v)));
        _chaosModeService.seedFromGroupOrExt(
          _activeGroup!.chaosModeEnabled ||
              _storageService.realismSettings.chaosModeDefault,
          _activeGroup!.chaosNsfwEnabled,
        );
      }
      _nsfwService.resetForFreshChat();
      _lorebookScanner.resetLorebookTriggerState();
      _needsSimEnabled = false;
      _enjoysLowHygiene = false;
      _needsSimulation.clearVector();
      _needsSimulation.resetBuffers();
      _pockets = null;
      if (_activeGroup != null) {
        // The zeroing above is the right starting point for the no-group path
        // but was the FINAL word for a group: an imported group transcript
        // landed with Needs hard-off and saved false onto its new session row,
        // so the rest of that conversation had blank needs grids and no decay.
        // Re-derive from the member seeds exactly as fresh group entry and the
        // startNewChat group branch do (presence-inference: the creator omits
        // the per-member 'needs' sub-map when Needs was off in the wizard),
        // AND-gated by the Porch Life global like every other seed site.
        _needsSimEnabled =
            _storageService.realismSettings.needsSimDefault &&
            _groupRealism.values.any((state) {
              final n = state.needs;
              return n != null && n.isNotEmpty;
            });
        if (_needsSimEnabled) {
          // Placeholder vector only — the first per-speaker
          // _loadGroupRealismIntoScalars replaces it with that member's own
          // needs. Same flat baseline both group twins use.
          _needsSimulation.initializeFreshWithDefaults(const {
            'hunger': 80,
            'bladder': 80,
            'energy': 80,
            'social': 80,
            'fun': 80,
            'hygiene': 80,
            'comfort': 80,
          });
        }
      }
    }
    seedPocketsFromCards();
    _growthStore.invalidate();
  }

  // ── Phase 1: session snapshot ───────────────────────────────────────────

  Map<String, dynamic> _captureSessionHeadForPackage() {
    final head = <String, dynamic>{
      'realism_enabled': _realismEnabled,
      'needs_sim_enabled': _needsSimEnabled,
      'enjoys_low_hygiene': _enjoysLowHygiene,
      'objectives_enabled': _objectivesEnabled,
      'summary': _summary,
      'summary_last_index': _summaryLastIndex,
      'affection_score': _relationshipService.affectionScore,
      'long_term_score': _relationshipService.longTermScore,
      'trust_level': _relationshipService.trustLevel,
      'relationship_tier': _relationshipService.relationshipTier,
      'long_term_tier': _relationshipService.longTermTier,
      'turns_since_long_term_check':
          _relationshipService.turnsSinceLongTermCheck,
      'short_term_deltas_summary': _relationshipService.shortTermDeltasSummary,
      // 1:1 only — captureCadenceAndFeelings is TURN PATH; group speakers
      // already ride group_realism_state (Opus b32789fd finding 3).
      if (_activeGroup == null)
        ..._relationshipService.captureCadenceAndFeelings(),
      'character_emotion': _characterEmotion,
      'emotion_intensity': _emotionIntensity,
      'active_fixation': _relationshipService.activeFixation,
      'fixation_lifespan': _relationshipService.fixationLifespan,
      'spatial_stance': _relationshipService.spatialStance,
      'arousal_level': _nsfwService.arousalLevel,
      'cooldown_turns_remaining': _nsfwService.cooldownTurnsRemaining,
      'cooldown_turns_total': _nsfwService.cooldownTurnsTotal,
      'time_of_day': _timeService.timeOfDay,
      'day_count': _timeService.dayCount,
      'start_day_of_week': _timeService.startDayOfWeekAnchor,
      'story_clock': _timeService.storyClockIso,
      'story_start_date': _timeService.storyStartDateIso,
      'chaos_mode_enabled': _chaosModeService.chaosModeEnabled,
      'chaos_pressure': _chaosModeService.chaosPressure,
      'needs_vector': Map<String, int>.from(_needsSimulation.vector),
      if (_pockets != null) 'pockets': _pockets!.toJson(),
      if (_activeGroup != null)
        'group_realism_state': {
          for (final e in _groupRealism.entries) e.key: e.value.toJson(),
        },
    };
    return head;
  }

  Future<void> _applySessionHeadFromPackage(Map<String, dynamic> head) async {
    if (head['realism_enabled'] is bool) {
      _realismEnabled = head['realism_enabled'] as bool;
    }
    if (head['needs_sim_enabled'] is bool) {
      _needsSimEnabled = head['needs_sim_enabled'] as bool;
    }
    if (head['enjoys_low_hygiene'] is bool) {
      _enjoysLowHygiene = head['enjoys_low_hygiene'] as bool;
    }
    if (head['objectives_enabled'] is bool) {
      _objectivesEnabled = head['objectives_enabled'] as bool;
    }
    _summary = head['summary'] as String? ?? _summary;
    _summaryLastIndex =
        (head['summary_last_index'] as num?)?.toInt() ?? _summaryLastIndex;

    final state = <String, dynamic>{
      if (head['affection_score'] != null)
        'affectionScore': head['affection_score'],
      if (head['long_term_score'] != null)
        'longTermScore': head['long_term_score'],
      if (head['trust_level'] != null) 'trustLevel': head['trust_level'],
      if (head['relationship_tier'] != null)
        'relationshipTier': head['relationship_tier'],
      if (head['long_term_tier'] != null)
        'longTermTier': head['long_term_tier'],
      if (head['turns_since_long_term_check'] != null)
        'turnsSinceLongTermCheck': head['turns_since_long_term_check'],
      if (head['short_term_deltas_summary'] != null)
        'shortTermDeltasSummary': head['short_term_deltas_summary'],
      if (head['turnsSinceDecayCheck'] != null)
        'turnsSinceDecayCheck': head['turnsSinceDecayCheck'],
      if (head['interCharacterRelationships'] is Map)
        'interCharacterRelationships': head['interCharacterRelationships'],
      if (head['character_emotion'] != null)
        'characterEmotion': head['character_emotion'],
      if (head['emotion_intensity'] != null)
        'emotionIntensity': head['emotion_intensity'],
      if (head['active_fixation'] != null)
        'activeFixation': head['active_fixation'],
      if (head['fixation_lifespan'] != null)
        'fixationLifespan': head['fixation_lifespan'],
      if (head['spatial_stance'] != null)
        'spatialStance': head['spatial_stance'],
      if (head['arousal_level'] != null) 'arousalLevel': head['arousal_level'],
      if (head['cooldown_turns_remaining'] != null)
        'cooldownTurnsRemaining': head['cooldown_turns_remaining'],
      if (head['cooldown_turns_total'] != null)
        'cooldownTurnsTotal': head['cooldown_turns_total'],
      if (head['time_of_day'] != null) 'timeOfDay': head['time_of_day'],
      if (head['day_count'] != null) 'dayCount': head['day_count'],
      if (head['start_day_of_week'] != null)
        'startDayOfWeek': head['start_day_of_week'],
      if (head['story_clock'] != null) 'storyClock': head['story_clock'],
      if (head['story_start_date'] != null)
        'storyStartDate': head['story_start_date'],
      if (head['pockets'] is Map) 'pockets': head['pockets'],
      if (head['needs_vector'] is Map)
        'needs': {
          'vector': Map<String, int>.from(
            (head['needs_vector'] as Map).map(
              (k, v) => MapEntry(k.toString(), (v as num).toInt()),
            ),
          ),
        },
    };
    if (state.isNotEmpty) {
      // Synthetic message to reuse restore path
      final synth = ChatMessage(
        text: '',
        sender: _activeCharacter?.name ?? '',
        isUser: false,
        metadata: {'realism_state': state},
      );
      _restoreRealismStateFromMessage(synth);
    }

    // 1:1 suitcase kit is captured from raw `_pockets` (HIDES≠erase).
    // Phase-0 nulled it so the prior open chat cannot bleed; the gated
    // realism_state restore then refuses put-back when this card authored
    // Pockets off. Write the captured record anyway — restore, not invent.
    if (_activeGroup == null && head['pockets'] is Map) {
      final id = _activeCharacter != null
          ? _getCharacterIdFromCard(_activeCharacter!)
          : '';
      if (id.isNotEmpty) {
        setPocketsFor(id, Pockets.fromJson(head['pockets']));
      }
    }

    if (head['chaos_mode_enabled'] is bool) {
      _chaosModeService.seedFromGroupOrExt(
        head['chaos_mode_enabled'] as bool,
        false,
      );
    }
    final pressure = (head['chaos_pressure'] as num?)?.toInt();
    if (pressure != null) {
      _chaosModeService.setPressure(pressure.clamp(0, 100));
    }
    if (head['group_realism_state'] is Map && _activeGroup != null) {
      final raw = Map<String, dynamic>.from(head['group_realism_state'] as Map);
      _groupRealism = {
        for (final e in raw.entries)
          if (e.value is Map)
            e.key: GroupMemberRealism.fromJson(
              Map<String, dynamic>.from(e.value as Map),
            ),
      };
    }
  }

  /// Thin `fpai.cast`: group roster (lite marked) or live 1:1 scene guests.
  /// Ids + name + tier only — no card blobs. 1:1 guests never rode
  /// `group_realism_state` in the package (that key is group-only).
  List<Map<String, dynamic>> _captureCastForPackage() {
    if (_activeGroup != null) {
      return [
        for (final c in _groupCharacters)
          encodeFpchatCastMember(
            id: _getCharacterIdFromCard(c),
            name: c.name,
            lite: c.isLite,
          ),
      ];
    }
    return [
      for (final g in _sceneGuest.cards)
        encodeFpchatCastMember(
          id: _getCharacterIdFromCard(g),
          name: g.name,
          lite: true,
        ),
    ];
  }

  /// Restore [fpai.cast] after Phase 0 seed wiped guests. Missing/empty
  /// is a no-op (legacy packages). Unknown ids are skipped — no invented
  /// cards. Dialogue-only imports never call this.
  Future<void> _applyCastFromPackage(dynamic raw) async {
    final cast = parseFpchatCast(raw);
    if (cast.isEmpty) return;
    if (_activeGroup != null) {
      var changed = false;
      for (final entry in cast) {
        if (!entry.lite) continue;
        final live = matchFpchatCastMember(_groupCharacters, entry);
        if (live == null || live.isLite) continue;
        final stamped = cloneFrontPorchTier(
          live.frontPorchExtensions,
          lite: true,
        );
        live.frontPorchExtensions = stamped;
        if (live.dbId != null) {
          await _db.updateGroupMember(
            GroupMembersCompanion(
              id: drift.Value(live.dbId!),
              frontPorchExtensions: drift.Value(
                encodeMemberFrontPorch(stamped),
              ),
            ),
          );
        }
        changed = true;
      }
      if (changed) await _reloadGroupRoster();
      return;
    }
    final hostId = _activeCharacter != null
        ? _getCharacterIdFromCard(_activeCharacter!)
        : '';
    final library = _characterRepository?.characters ?? const <CharacterCard>[];
    for (final entry in cast) {
      if (!entry.lite) continue;
      final lib = matchFpchatCastMember(library, entry);
      if (lib == null || lib.dbId == null) continue;
      if (_getCharacterIdFromCard(lib) == hostId) continue;
      if (_sceneGuest.ids.contains(lib.dbId)) continue;
      await _enterSceneGuest(lib, speak: false);
    }
  }

  /// Register a 1:1 Scene Guest without an entrance turn (import + tests).
  @visibleForTesting
  Future<void> debugEnterSceneGuestSilent(CharacterCard guest) =>
      _enterSceneGuest(guest, speak: false);

  /// Seed a transcript so [exportToFpchat] has something to pack.
  @visibleForTesting
  void debugSeedTranscriptForFpchat(List<ChatMessage> msgs) {
    _messages
      ..clear()
      ..addAll(msgs);
  }
}
