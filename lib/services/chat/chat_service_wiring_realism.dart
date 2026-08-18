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

/// Builders for the core Realism Engine leaf services (time, chaos mode,
/// nsfw, needs simulation, relationship, expression). Extracted verbatim from
/// `chat_service.dart` — the god file's `late final _x = _buildX();` field
/// declarations call these; laziness (and therefore init order) is unchanged
/// because `late final` still resolves on first access. Zero behaviour
/// change: every callback closure is byte-identical to its old inline form.
extension ChatServiceWiringRealism on ChatService {
  // ── Passage of time (extracted to TimeService) ───────────────────────────
  // (Declared early among late finals for init safety because needs/others close over its getters via cbs.
  // Logically added "after the other late finals" per extraction sequence; 0 new god privates.)
  TimeService _buildTimeService() {
    return TimeService(
      onNotify: notifyListeners,
      onSaveChat: _saveChat,
      // Shared tools transport (one probe per backend identity, app-wide).
      fireToolEval: _fireToolEval,
      probe: _toolProbe,
      getBackendIdentity: () => _evalBackendIdentity,
      onSetPendingRealismMetadata: (key, value) {
        _pendingRealismMetadata ??= {};
        _pendingRealismMetadata![key] = value;
      },
      onStoryDayChanged: () {
        final held = todaySentence;
        setTodaySentence(null);
        unawaited(_journalResolvedToday(held, fate: PlannerTodayFate.dayAte));
      },
      getPlannerEnabled: () => _storageService.realismSettings.plannerEnabled,
      onTodayEval: (line) {
        if (line.isEmpty) {
          abandonToday();
        } else {
          final prev = todaySentence;
          if (prev != null && prev != line) {
            unawaited(_journalResolvedToday(prev, fate: PlannerTodayFate.done));
          }
          setTodaySentence(line);
        }
      },
      onPatchLastMessageRealismState: (tod, dc, clockIso) {
        // Patch the newest REAL message — never a narration banner. Dream /
        // chance-time messages carry only their banner flag; stamping a full
        // realism snapshot onto one corrupts it (2026-07-28) and makes a
        // banner the time authority for swipe/regen restores.
        for (final lastMsg in _messages.reversed) {
          if (lastMsg.activeMetadata?['is_dream'] == true ||
              lastMsg.activeMetadata?['is_chance_time_narration'] == true) {
            continue;
          }
          lastMsg.activeMetadata ??= {};
          final existingState = lastMsg.activeMetadata!['realism_state'];
          if (existingState is Map<String, dynamic>) {
            existingState['timeOfDay'] = tod;
            existingState['dayCount'] = dc;
            existingState['storyClock'] = clockIso;
            existingState['time_nudged'] = true;
          } else {
            lastMsg.activeMetadata!['realism_state'] = _captureRealismState();
            lastMsg.activeMetadata!['realism_state']['time_nudged'] = true;
          }
          break;
        }
      },
    );
  }

  // ── Chaos Mode (extracted; late final here for injection safety, before _chaosInjection) ──
  ChaosModeService _buildChaosModeService() {
    return ChaosModeService(
      onNotify: notifyListeners,
      onSaveChat: _saveChat,
      onSetPendingRealismMetadata: (key, value) {
        _pendingRealismMetadata ??= {};
        _pendingRealismMetadata![key] = value;
      },
    );
  }

  // ── NSFW cooldown & arousal (extracted to NsfwService) ─────────────────────
  // State (cooldown enabled/remaining/total, arousalLevel), tier calc, reset/seed/load/restore,
  // group per-speaker load/save scalars, applyClimax/decrement live in _nsfwService (plain class).
  // ChatService owns via late final + delegates. (Declared before needs for init safety because
  // needs closes over the getArousal/getNsfw/getCooldown/setArousal cbs.)
  // Reset helpers on service keep the multiple "keep reset blocks in sync" sites correct (now incl needs/chaos/... + leaves (see CLAUDE.md for full; incomplete zeroing now complete) + " ; no reset scalar) comments)
  // without god privates. 0 new private methods in god.
  // _runPostGenNeedsChecks thin (consolidated to needs_impact_evaluator); 3 group cbs only (onNotify/onSaveChat removed as dead; god owns save/notify for post-gen fidelity per plan). (cross-ref setActiveCharacter:1572 etc)
  NsfwService _buildNsfwService() {
    return NsfwService(
      getGroupInt: (charId, key, {int defaultValue = 0}) =>
          _groupIntOr(charId, key, defaultValue),
      getGroupValue: (charId, key) => _groupRealism[charId]?.valueFor(key),
      setGroupValue: (charId, key, v) =>
          _memberForWrite(charId).setValue(key, v),
    );
  }

  NeedsSimulation _buildNeedsSimulation() {
    return NeedsSimulation(
      onNotify: notifyListeners,
      onSaveChat: _saveChat,
      getTimeOfDay: () => _timeService.timeOfDay,
      getRealismEnabled: () => _realismEnabled,
      getObserverMode: () => _observerMode,
      getCurrentSpeakerIdForRealism: _getCurrentSpeakerIdForRealism,
      getIsGroupNonObserverMode: () => (_activeGroup != null && !_observerMode),
      getGroupNeeds: _getGroupNeeds,
      setGroupNeeds: _setGroupNeeds,
      getEnjoysLowHygiene: () => enjoysLowHygiene,
      getNeedsSimEnabled: () => _needsSimEnabled,
      getCustomDecayRates: () => _activeDecayRates(),
      // Same source the needs-impact eval reads for its prompt scaling, so the
      // bound and the instruction can never disagree about what "5x" means.
      getNeedsSimStrength: () =>
          (_activeCharacter?.frontPorchExtensions?.needsSimStrength ?? 1),
      // Needs modifiers sample the CURRENT DAY-PART (v3): an afternoon storm
      // speeds comfort decay even on a day whose headline is "cloudy", and a
      // clear evening earns the fun bonus after a rainy morning. Same
      // DailyWeather view the modifiers always took — condition swapped for
      // the segment's, band/season stay the day's — so NeedsSimulation is
      // untouched and 1:1/group parity is inherited (weather is per-chat
      // shared; both paths tick through these same modifiers).
      getWeather: () {
        final seg = currentSegmentWeather;
        if (seg == null) return null;
        return DailyWeather(
          condition: seg.condition,
          temp: seg.day.temp,
          season: seg.day.season,
        );
      },
    );
  }

  RelationshipService _buildRelationshipService() {
    return RelationshipService(
      onNotify: notifyListeners,
      onSaveChat: _saveChat,
      getIsGroupActive: () => _activeGroup != null,
      getObserverMode: () => _observerMode,
      getGroupCharacterCount: () => _groupCharacters.length,
      getShouldTrackInterCharacterRelationships: () =>
          _shouldTrackInterCharacterRelationships,
      getCurrentSpeakerIdForRealism: _getCurrentSpeakerIdForRealism,
      getCurrentGroupMemberIds: () =>
          _groupCharacters.map(_getCharacterIdFromCard).toSet(),
      getOtherGroupMemberIds: (selfId) => _groupCharacters
          .map(_getCharacterIdFromCard)
          .where((id) => id != selfId)
          .toList(),
      getOtherGroupMemberIdToLowerName: (selfId) {
        final m = <String, String>{};
        for (final other in _groupCharacters) {
          final oid = _getCharacterIdFromCard(other);
          if (oid == selfId) continue;
          m[oid] = other.name.toLowerCase();
        }
        return m;
      },
      getRecentExchangeLowerText: () {
        if (_messages.length < 2) return '';
        return _messages.reversed
            .take(2)
            .map((m) => m.displayText.toLowerCase())
            .join(' ');
      },
      getMessageCount: () => _messages.length,
      getIsGroupRealismActive: () => isGroupRealismActive,
      getGroupAffectionScore: (charId, {int defaultValue = 0}) =>
          _groupRealism[charId]?.affection ?? defaultValue,
      setGroupAffectionScore: (charId, v) =>
          _memberForWrite(charId).affection = v,
      getGroupLongTermScore: (charId, {int defaultValue = 0}) =>
          _groupRealism[charId]?.longTermScore ?? defaultValue,
      setGroupLongTermScore: (charId, v) =>
          _memberForWrite(charId).longTermScore = v,
      getGroupTrustLevel: (charId, {int defaultValue = 0}) =>
          _groupRealism[charId]?.trust ?? defaultValue,
      setGroupTrustLevel: (charId, v) => _memberForWrite(charId).trust = v,
      getGroupFixation: (charId, {String defaultValue = ''}) =>
          _groupRealism[charId]?.fixation ?? defaultValue,
      setGroupFixation: (charId, v) => _memberForWrite(charId).fixation = v,
      getGroupFixationLifespan: (charId, {int defaultValue = 0}) =>
          _groupRealism[charId]?.fixationLifespan ?? defaultValue,
      setGroupFixationLifespan: (charId, v) =>
          _memberForWrite(charId).fixationLifespan = v,
      getGroupRelationshipTier: (charId, {int defaultValue = 0}) =>
          _groupRealism[charId]?.relationshipTier ?? defaultValue,
      setGroupRelationshipTier: (charId, v) =>
          _memberForWrite(charId).relationshipTier = v,
      getGroupLongTermTier: (charId, {int defaultValue = 0}) =>
          _groupRealism[charId]?.longTermTier ?? defaultValue,
      setGroupLongTermTier: (charId, v) =>
          _memberForWrite(charId).longTermTier = v,
      getGroupSpatialStance: (charId, {String defaultValue = ''}) =>
          _groupRealism[charId]?.spatialStance ?? defaultValue,
      setGroupSpatialStance: (charId, v) =>
          _memberForWrite(charId).spatialStance = v,
      getGroupInterCharacterRelationships: (charId) =>
          _groupRealism[charId]?.relationships ?? const <String, int>{},
      setGroupInterCharacterRelationships: (charId, rels) =>
          _memberForWrite(charId).relationships = rels,
      getGroupCounter: (charId, key, {int defaultValue = 0}) =>
          _groupIntOr(charId, key, defaultValue),
      setGroupCounter: (charId, key, v) =>
          _memberForWrite(charId).setValue(key, v),
      // Living Time §7 v1.5: bond/trust tier crossings → "Our Story" cards.
      // Fire-and-forget; plant never throws into the eval path. Diary owner is
      // the current speaker (1:1 host or group speaker whose scalars just moved).
      onTierCrossing: (crossing) {
        final sessionId = _currentSessionId;
        if (sessionId == null) return;
        final charId = _getCurrentSpeakerIdForRealism();
        if (charId.isEmpty) return;
        unawaited(
          RelationshipMilestones.plant(
            store: _journalStore,
            sessionId: sessionId,
            characterId: charId,
            crossing: crossing,
            sourcePositions: _messages.isEmpty
                ? const <int>[]
                : <int>[_messages.length - 1],
            storyDay: _timeService.dayCount,
            storyClock: _timeService.storyClockIso,
            maxCards: _storageService.memorySettings.journalMaxCards,
          ),
        );
      },
    );
  }

  // ── Expression label selection / manual / avatar resolve / reclass / ONNX (extracted) ────
  // currentExpressionLabel (manual priority + LLM map + ONNX debounce/cache/stability),
  // resolveExpressionAvatar (random + lastId reroll), setManual, reclassifyEmotion,
  // init/set for classifier service, _reclassify/_classifyOnnx async, caches, Random,
  // lastAvatarId now owned by ExpressionService (plain class).
  // ChatService owns via late final + delegates. Prompt injection (label lists) + command
  // coordination kept in god (step 8). Reset/invalidate helpers on service keep the
  // multiple "keep reset blocks in sync" + regen sites correct without god privates (needs/chaos/... + leaves (see CLAUDE.md for full; incomplete zeroing now complete) + " ; thin/legacy in evaluator; no god reset scalar)" ). (cross-ref setActiveCharacter:1572 etc)
  ExpressionService _buildExpressionService() {
    return ExpressionService(
      onNotify: notifyListeners,
      onSaveChat: _saveChat,
      // Shared tools transport (one probe per backend identity, app-wide).
      fireToolEval: _fireToolEval,
      probe: _toolProbe,
      getBackendIdentity: () => _evalBackendIdentity,
      getIsEvaluatingRealism: () => _isEvaluatingRealism,
      getStorageService: () => _storageService,
      getLlmServiceForReclass: () =>
          testLlmServiceOverride ??
          _llmProvider?.activeService ??
          _koboldService,
      getIsGenerating: () => _isGenerating,
      getCharacterEmotion: () => _characterEmotion,
      getMessages: () => _messages,
      getIsThinkingModelForReclass: () {
        // Preserve original expression reclass isThinking logic (ignores testLlmOverride for isLocal,
        // consistent with pre-extraction).
        final llmP = _llmProvider;
        if (llmP != null && llmP.isLocal) {
          return _storageService.backendSettings.koboldThinkingModel;
        }
        if (llmP != null) {
          return _storageService.backendSettings.reasoningEnabled;
        }
        return false;
      },
      getRealismEvalCancelled: () => _realismEvalCancelled,
      setRealismEvalCancelled: (v) => _realismEvalCancelled = v,
      setIsEvaluatingRealism: (v) => _isEvaluatingRealism = v,
      onHandleRealismEvalCancelledDuringOnnx: () async {
        // Transient banner only — never a persisted chat message. (The old
        // 'Interruption' line rode chat history, prompts, RAG, and journal
        // windows forever; same fix as cancelRealismEval.) This fires during
        // post-generation ONNX avatar classification, so the reply already
        // exists — consuming the flag here is correct (nothing to abort).
        _setGuestStatus('Realism classification interrupted.');
        _realismEvalCancelled = false;
        _isEvaluatingRealism = false;
        notifyListeners();
      },
    );
  }
}
