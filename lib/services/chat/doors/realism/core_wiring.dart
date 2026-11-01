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

import 'package:flutter/foundation.dart';

import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/chat/chat.dart';
import 'package:front_porch_ai/services/chat/doors/realism/realism_graph.dart';
import 'package:front_porch_ai/services/chat/doors/session/today_sentence.dart';
import 'package:front_porch_ai/services/storage_service.dart';

/// Builders for the core Realism leaves: the clock, the group store and the
/// scope, Needs, mood, chaos, Afterglow's body state and expression.
/// `late final` on the graph still resolves each on first access, so init
/// order is the one the leaves always had.
extension RealismCoreWiring on RealismGraph {
  // Time first: needs and others close over its getters.
  TimeService buildTime() {
    return TimeService(
      onNotify: notifyListeners,
      onSaveChat: _saveChat,
      // Shared tools transport (one probe per backend identity, app-wide).
      fireToolEval: transport.fireToolEval,
      probe: transport.probe,
      getBackendIdentity: () => transport.backendIdentity,
      onSetPendingRealismMetadata: (key, value) {
        registers.pending ??= {};
        registers.pending![key] = value;
        growthDesk.requestSalienceKick(onlyIf: registers.pending);
      },
      onStoryDayChanged: () {
        _h.recordTodayPointerOp();
        final held = _today.todaySentence;
        _today.setTodaySentence(null);
        return () async {
          await _h.journalResolvedToday(held, fate: PlannerTodayFate.dayAte);
          await _h.deactivateTodayObjective();
        }();
      },
      // A story day crossed eases the mood one step (mood-with-bite.md):
      // the live registers AND every group member's record, since the day
      // is the chat's, not the loaded speaker's. The post-reply restamp then
      // writes the eased mood onto the reply so a swipe back shows it.
      onStoryDaysCrossed: (days, {manual = false}) {
        mood.easeForDays(days);
        mood.easeMembersForDays(days);
        // Only a chevron or calendar roll, made by hand outside any turn,
        // writes the eased mood onto the latest replies: no restamp follows
        // it, and a swipe back would otherwise restore the mood from before
        // the roll. A reply's own clock pass is restamped afterwards, and an
        // OOC skip at the start of a send belongs to the reply being written:
        // the previous reply keeps the mood it ended with, so deleting the
        // new one puts the pre-skip mood back. (The busy flags cannot tell
        // these apart: the generating flag rises after the skip is applied.)
        if (manual) mood.patchLatestReplyStamps();
      },
      getPorchLifePassageOfTime: () =>
          _storageService.realismSettings.passageOfTimeDefault,
      getPlannerEnabled: () => _storageService.realismSettings.plannerEnabled,
      // Slice 6: which places the judge may suggest — the reach law and
      // labels live in buildScenePlaceOffer (scene_place_offer.dart).
      getScenePlaceOffer: () => buildScenePlaceOffer(
        enabled: _storageService.realismSettings.sceneSuggestionsEnabled,
        primaryId: places.primaryId,
        repo: deps.services.worlds,
        isDeclined: places.sceneMoves.isDeclined,
      ),
      onScenePlace: (id) {
        debugPrint('[Realism:Scene] suggested move pending: $id');
        places.flagSuggestedPlaceMove(id);
      },
      // Slice 7: the 'new' arrival — the same tap-to-confirm law. An
      // ignored name is refused HERE, before the flag, so a dismissed
      // side street never re-dialogs this chat (design §3).
      onNewPlace: (name, descriptor) {
        if (places.sceneMoves.mints.isIgnored(name)) {
          debugPrint('[Realism:Mint] "$name" is ignored in this chat');
          return;
        }
        places.flagSuggestedPlaceMint(name, descriptor);
      },
      onTodayEval: (line) {
        _h.recordTodayPointerOp();
        if (line.isEmpty) {
          _today.abandonToday();
          return Future<void>.value();
        }
        final prev = _today.todaySentence;
        _today.setTodaySentence(line);
        return () async {
          if (prev != null && prev != line) {
            await _h.journalResolvedToday(prev, fate: PlannerTodayFate.done);
          }
          await _h.upsertTodayObjective(line);
        }();
      },
      onPatchLastMessageRealismState: (_, _, _) {
        // Clock stamps are written only by StoryClockWriter.writeSlotClock.
        // This hook must not insert a snapshot or mark user messages.
      },
    );
  }

  /// The open chat as the story clock reads it — live getters only.
  StoryClockScope buildClockScope() => StoryClockScope(
    session: session,
    history: _doors.sessions().history,
    time: () => time,
    clockRunning: _h.clockRunning,
  );

  StoryClockWriter buildClockWriter() => StoryClockWriter(
    clockScope,
    clockReader,
    currentSessionId: () => session.currentSessionId,
    saveChat: _saveChat,
    notify: notifyListeners,
    setGuestStatus: (status) => _doors.cast().guests.setStatus(status),
  );

  EpisodeCrumbMinter buildEpisodeCrumbs() => EpisodeCrumbMinter(
    clockRunning: _h.clockRunning,
    memorySettings: () => _storageService.memorySettings,
    currentSessionId: () => session.currentSessionId,
    cast: clockCast,
    time: () => time,
    history: _doors.sessions().history,
    messageCount: () => session.messages.length,
    workFieldsFor: workFieldsFor,
    characterIdFor: _h.characterIdFor,
    journalStore: () => journalStore,
  );

  BirthdaySync buildBirthdays() => BirthdaySync(
    currentSessionId: () => session.currentSessionId,
    memorySettings: () => _storageService.memorySettings,
    time: () => time,
    persona: () => deps.services.personas.persona,
    cast: clockCast,
    characterIdFor: _h.characterIdFor,
    journalStore: () => journalStore,
    objectivesActive: _h.objectivesActive,
    db: deps.services.db,
    reloadActiveObjectives: () => _doors.objectives().loadActiveObjectives(),
    maxSecondaryObjectives: deps.services.maxSecondaryObjectives,
  );

  GroupRealismStore buildGroups() => GroupRealismStore(
    isGroup: () => session.activeGroup != null,
    groupCharacters: () => session.groupCharacters,
    characterIdFor: _h.characterIdFor,
    hostId: _h.ragCharacterId,
    activeCharacter: () => session.activeCharacter,
    isGenerating: _h.isGenerating,
    nextCharacter: () => _doors.entry().director.nextCharacter,
    workFieldsFor: workFieldsFor,
  );

  /// A member's occupation and hours, read from their library card.
  WorkFields workFieldsFor(CharacterCard card) => workFieldsForMember(
    card,
    deps.services.characters()?.characters ?? const <CharacterCard>[],
  );

  /// The open chat as Realism and Needs read and write it — live only.
  RealismScope buildScope() => RealismScope.of(
    session: session,
    observerMode: () => _doors.entry().director.observerMode,
    realismEnabled: _h.realismEnabled,
    needsSimEnabled: _h.needsSimEnabled,
    realismSettings: () => _storageService.realismSettings,
    clockRunning: _h.clockRunning,
    characterIdFor: _h.characterIdFor,
    groups: groups,
    needs: () => needs,
    relationship: () => relationship,
    nsfw: () => nsfw,
    time: () => time,
    pending: () => registers.pending,
    setPending: (v) => registers.pending = v,
    emotion: () => registers.emotion,
    setEmotion: (v) => registers.emotion = v,
    intensity: () => registers.intensity,
    setIntensity: (v) => registers.intensity = v,
    cause: () => registers.cause,
    setCause: (v) => registers.cause = v,
    heldTurns: () => registers.heldTurns,
    setHeldTurns: (v) => registers.heldTurns = v,
    saveChat: _saveChat,
    notify: notifyListeners,
  );

  NeedsPass buildNeedsPass() => NeedsPass(
    scope,
    loadIntoScalars: (id) => dance.loadIntoScalars(id),
    chatRealism: () => _realismChatSwitch,
  );

  NeedsRewinds buildNeedsRewinds() => NeedsRewinds(
    scope,
    restoreRefractoryAfterBeat: (msg, id) =>
        afterglow.restoreAfterBeat(msg, id),
  );

  StandingMood buildStandingMood() => StandingMood(
    scope,
    weather: () => weather.currentWeather,
    needsActive: () => needsPass.active,
  );

  // The pre-reply quest check runs before the generating flag rises, so the
  // objective-turn window counts as busy too: a mood the planner moves there
  // rides the reply's capture, never a patch of the previous reply.
  MoodRegisters buildMood() => MoodRegisters(
    scope,
    isTurnBusy: () => _h.isTurnBusy() || _doors.objectives().inObjectiveTurn,
  );

  RealismSnapshot buildSnapshot() => RealismSnapshot(
    scope,
    needsActive: () => needsPass.active,
    pocketsFor: (id) => pocketsLedger.pocketsFor(id),
    wearBeatOn: (msg) => needsPass.wearBeatOn(msg),
  );

  // ── Chaos Mode (before the chaos injection that reads it) ──
  ChaosModeService buildChaos() {
    return ChaosModeService(
      onNotify: notifyListeners,
      onSaveChat: _saveChat,
      onSetPendingRealismMetadata: (key, value) {
        registers.pending ??= {};
        registers.pending![key] = value;
        growthDesk.requestSalienceKick(onlyIf: registers.pending);
      },
      isAdultAllowed: () => _storageService.realismSettings.adultThemesEnabled,
      getFrequency: () => _storageService.realismSettings.chaosFrequency,
      // PR 6: the hard-lock truth lives in one lookup next to
      // applyChanceTimeResult — spin AND accept re-gate through it, so the
      // two chokepoints cannot drift.
      isHardLockActive: () => _h.hardLockFor(_h.chanceTimeSpeaker()),
    );
  }

  // ── NSFW cooldown & arousal (NsfwService owns the state). Declared before
  // needs, which closes over its arousal and cooldown callbacks. ──
  NsfwService buildNsfw() {
    return NsfwService(
      getGroupInt: (charId, key, {int defaultValue = 0}) =>
          groups.intOr(charId, key, defaultValue),
      getGroupValue: (charId, key) => groups.members[charId]?.valueFor(key),
      setGroupValue: (charId, key, v) =>
          groups.memberForWrite(charId).setValue(key, v),
      isClockRunning: _h.clockRunning,
      // Porch Life (with 18+) allows it AND this chat's own switch is on.
      afterglowOn: () =>
          _storageService.realismSettings.afterglowEnabled &&
          _h.afterglowSwitch(),
      chatSwitchOn: _h.afterglowSwitch,
    );
  }

  NeedsSimulation buildNeeds() {
    return NeedsSimulation(
      onNotify: notifyListeners,
      onSaveChat: _saveChat,
      getTimeOfDay: () => time.timeOfDay,
      getRealismEnabled: _h.realismEnabled,
      getObserverMode: () => _doors.entry().director.observerMode,
      getCurrentSpeakerIdForRealism: groups.currentSpeakerId,
      getIsGroupNonObserverMode: () => session.activeGroup != null,
      getGroupNeeds: groups.needsOf,
      setGroupNeeds: groups.setNeeds,
      getEnjoysLowHygiene: _h.enjoysLowHygiene,
      getNeedsSimEnabled: () => needsPass.active,
    );
  }

  // ── Expression: label selection, manual pick, avatar resolve, reclass and
  // ONNX live on ExpressionService; the prompt label lists stay with the
  // prompt and the command handler.
  ExpressionService buildExpression() {
    return ExpressionService(
      onNotify: notifyListeners,
      onSaveChat: _saveChat,
      // Shared tools transport (one probe per backend identity, app-wide).
      fireToolEval: transport.fireToolEval,
      probe: transport.probe,
      getBackendIdentity: () => transport.backendIdentity,
      getIsEvaluatingRealism: () => evalStatus.evaluating,
      getStorageService: () => _storageService,
      getLlmServiceForReclass: _h.sideLaneLlm,
      getIsGenerating: _h.isGenerating,
      getCharacterEmotion: () => registers.emotion,
      getMessages: () => session.messages,
      getIsThinkingModelForReclass: () {
        // Preserve original expression reclass isThinking logic (ignores
        // testLlmOverride for isLocal, consistent with pre-extraction).
        final llmP = deps.services.llmProvider();
        if (llmP != null && llmP.isLocal) {
          return _storageService.backendSettings.koboldThinkingModel;
        }
        if (llmP != null) {
          return _storageService.backendSettings.reasoningEnabled;
        }
        return false;
      },
      getRealismEvalCancelled: _h.evalCancelled,
      setRealismEvalCancelled: _h.setEvalCancelled,
      setIsEvaluatingRealism: (v) => evalStatus.evaluating = v,
      onHandleRealismEvalCancelledDuringOnnx: () async {
        // Transient banner only — never a persisted chat message. (The old
        // 'Interruption' line rode chat history, prompts, RAG, and journal
        // windows forever; same fix as cancelRealismEval.) This fires during
        // post-generation ONNX avatar classification, so the reply already
        // exists — consuming the flag here is correct (nothing to abort).
        _doors.cast().guests.setStatus('Realism classification interrupted.');
        _h.setEvalCancelled(false);
        evalStatus.evaluating = false;
        notifyListeners();
      },
    );
  }
}

extension on RealismGraph {
  StorageService get _storageService => deps.services.storage;
  RealismShellHooks get _h => deps.hooks;
  RealismDoors get _doors => deps.doors;
  TodaySentence get _today => _doors.sessions().today;

  /// The chat's own Realism switch, for the one leaf input that is it.
  bool get _realismChatSwitch => _h.chatRealism();

  void notifyListeners() => deps.notify();
  Future<void> _saveChat() => _doors.sessions().save();
}
