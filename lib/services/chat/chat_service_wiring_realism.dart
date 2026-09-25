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
/// nsfw, needs simulation, relationship, expression). `late final` still
/// resolves on first access, so init order is unchanged.
extension ChatServiceWiringRealism on ChatService {
  // Time first: needs and others close over its getters.
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
        _requestSalienceKick(onlyIf: _pendingRealismMetadata);
      },
      onStoryDayChanged: () {
        final held = todaySentence;
        setTodaySentence(null);
        return () async {
          await _journalResolvedToday(held, fate: PlannerTodayFate.dayAte);
          await _deactivateTodayObjective();
        }();
      },
      getPorchLifePassageOfTime: () =>
          _storageService.realismSettings.passageOfTimeDefault,
      getPlannerEnabled: () => _storageService.realismSettings.plannerEnabled,
      onTodayEval: (line) {
        if (line.isEmpty) {
          abandonToday();
          return Future<void>.value();
        }
        final prev = todaySentence;
        setTodaySentence(line);
        return () async {
          if (prev != null && prev != line) {
            await _journalResolvedToday(prev, fate: PlannerTodayFate.done);
          }
          await _upsertTodayObjective(line);
        }();
      },
      onPatchLastMessageRealismState: (_, _, _) {
        // Clock stamps are written only by
        // _syncActiveSlotClockAfterManualSet. This hook must not
        // insert a snapshot or mark user messages.
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
        _requestSalienceKick(onlyIf: _pendingRealismMetadata);
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
    );
  }

  RelationshipService _buildRelationshipService() {
    return RelationshipService(
      onNotify: notifyListeners,
      onSaveChat: _saveChat,
      getIsGroupActive: () => _activeGroup != null,
      getObserverMode: () => _observerMode,
      getGroupCharacterCount: () =>
          fullGroupCharacters(_groupCharacters).length,
      getShouldTrackInterCharacterRelationships: () =>
          _shouldTrackInterCharacterRelationships,
      getCurrentSpeakerIdForRealism: _getCurrentSpeakerIdForRealism,
      getCurrentGroupMemberIds: () => fullGroupCharacters(
        _groupCharacters,
      ).map(_getCharacterIdFromCard).toSet(),
      getOtherGroupMemberIds: (selfId) => fullGroupCharacters(
        _groupCharacters,
      ).map(_getCharacterIdFromCard).where((id) => id != selfId).toList(),
      getOtherGroupMemberIdToLowerName: (selfId) {
        final m = <String, String>{};
        for (final other in fullGroupCharacters(_groupCharacters)) {
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
      getGroupWithUser: (charId) => _groupRealism[charId]?.withUser,
      setGroupWithUser: (charId, v) => _memberForWrite(charId).withUser = v,
      getGroupInterCharacterRelationships: (charId) =>
          _groupRealism[charId]?.relationships ?? const <String, int>{},
      setGroupInterCharacterRelationships: (charId, rels) =>
          _memberForWrite(charId).relationships = rels,
      getGroupCounter: (charId, key, {int defaultValue = 0}) =>
          _groupIntOr(charId, key, defaultValue),
      setGroupCounter: (charId, key, v) =>
          _memberForWrite(charId).setValue(key, v),
      // Living Time §7 v1.5: bond/trust tier crossings → "Our Story" cards.
      // Fire-and-forget; plant never throws. Owner is the current speaker.
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
            sourcePositions: persistTipCite(
              base: _history.basePosition,
              length: _messages.length,
            ),
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
      getLlmServiceForReclass: () => _sideLaneLlm,
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
