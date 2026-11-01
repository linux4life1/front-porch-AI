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
//
// Prompt-injection leaf builders. The lore enumerator is chat_lore.dart and
// the places and weather are chat_places.dart. objectivesActive stays the
// live AND.

import 'package:front_porch_ai/database/database.dart' show Objective;
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/chat/chat.dart';
import 'package:front_porch_ai/services/chat/doors/realism/realism_graph.dart';
import 'package:front_porch_ai/services/chat/prompt_injection/prompt_injection.dart';
import 'package:front_porch_ai/services/storage_service.dart';

extension RealismInjectionWiring on RealismGraph {
  AuthorNoteBuilder buildAuthorNotes() {
    final objectives = deps.doors.objectives;
    return AuthorNoteBuilder(
      // Objectives off ⇒ nothing about quests reaches the model. Reading the
      // gate here rather than clearing the loaded list keeps the rows intact
      // for when the switch comes back on.
      getActiveObjectives: () =>
          controls.objectivesActive ? objectives().activeObjectives : const [],
      getPrimaryObjective: () => objectives().primaryObjective,
      tasksForObjective: (o) => objectives().tasks.tasksFor(o),
      getSecondaryObjectives: () => objectives().secondaryObjectives,
      getStreakLine: () => controls.objectivesActive
          ? objectiveStreakLine(objectives().objectiveTally.recent)
          : null,
      // In a group only the goal owner's replies count; the ids match because
      // both are the stable id.
      isResting: (o) =>
          o is Objective &&
          objectiveFixated(
            messages: session.messages,
            questTexts: openQuestMentionTexts(
              o.objective,
              objectives().tasks.tasksFor(o),
            ),
            speakerId: session.activeGroup != null ? o.characterId : null,
            ignore: objectives().objectiveIgnoreTokens(),
          ),
    );
  }

  RelationshipInjection buildRelationshipInjection() {
    return RelationshipInjection(
      relationshipService: relationship,
      getRealismEnabled: () => controls.realismEnabled,
      getIsGroupNonObserverMode: () => session.activeGroup != null,
      getCurrentSpeakerIdForRealism: groups.currentSpeakerId,
      getGroupCharacters: () => session.groupCharacters,
      getActiveCharacter: () => session.activeCharacter,
      getShouldTrackInterCharacterRelationships: () =>
          deps.doors.entry().reads.shouldTrackInterCharacterRelationships,
      getGroupInt: (charId, key, {int defaultValue = 0}) =>
          groups.intOr(charId, key, defaultValue),
      getCharacterIdFromCard: session.characterIdFor,
      getInterCharacterRelationships:
          relationship.getInterCharacterRelationships,
    );
  }

  EmotionInjection buildEmotionInjection() {
    return EmotionInjection(
      getRealismEnabled: () => controls.realismEnabled,
      getCharacterEmotion: () => registers.emotion,
      getEmotionIntensity: () => registers.intensity,
      getEmotionCause: () => registers.cause,
      getEmotionHeldTurns: () => registers.heldTurns,
    );
  }

  BehavioralInjection buildBehavioralInjection() {
    return BehavioralInjection(
      relationshipService: relationship,
      getRealismEnabled: () => controls.realismEnabled,
      getOccupation: () => groups.workFieldsForCurrentSpeaker().occupation,
      getHours: () => groups.workFieldsForCurrentSpeaker().hours,
      getOccupationBrief: () =>
          groups.workFieldsForCurrentSpeaker().occupationBrief,
      getWorkDays: () => groups.workFieldsForCurrentSpeaker().workDays,
      getClockMinutes: () => time.clockMinutes,
      getWeekday: () => time.clock.weekday,
      getIsGroup: () => session.activeGroup != null,
    );
  }

  WeatherInjection buildWeatherInjection() {
    return WeatherInjection(
      getWeather: () => weather.currentSegmentWeather,
      getPreviousSegment: () => weather.previousSegmentWeather,
      getUpcoming: () => weather.upcomingWeather,
      suppressForeshadow: () => places.biomes.isSpanStart(time.dayCount),
      // Condition skins (phase 2 step ④): renamed weather speaks by its new
      // name with stance-driven behavior on every prompt surface.
      getBiome: () => weather.activeChatBiome,
    );
  }

  PlanInjection buildPlanInjection() {
    return PlanInjection(
      getTodayLine: () => deps.doors.sessions().today.todaySentence,
      getPlannerEnabled: () => _storageService.realismSettings.plannerEnabled,
      getClockMinutes: () => time.clockMinutes,
      getWeekday: () => time.clock.weekday,
      getActiveCharacter: () => session.activeCharacter,
      getIsGroupNonObserverMode: () => session.activeGroup != null,
      getCurrentSpeakerIdForRealism: groups.currentSpeakerId,
      getGroupCharacters: () => session.groupCharacters,
      getCharacterIdFromCard: session.characterIdFor,
    );
  }

  AmbitionInjection buildAmbitionInjection() {
    return AmbitionInjection(
      ambitionService: ambitions,
      getSessionId: () => session.currentSessionId,
      getActiveCharacter: () => session.activeCharacter,
      getIsGroupNonObserverMode: () => session.activeGroup != null,
      getCurrentSpeakerIdForRealism: groups.currentSpeakerId,
      getGroupCharacters: () => session.groupCharacters,
      getCharacterIdFromCard: session.characterIdFor,
    );
  }

  PreferencesInjection buildPreferencesInjection() {
    return PreferencesInjection(
      getActiveCharacter: () => session.activeCharacter,
      getIsGroupNonObserverMode: () => session.activeGroup != null,
      getCurrentSpeakerIdForRealism: groups.currentSpeakerId,
      getGroupCharacters: () => session.groupCharacters,
      getCharacterIdFromCard: session.characterIdFor,
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
          controls.realismEnabled,
    );
  }

  InventoryInjection buildInventoryInjection() {
    return InventoryInjection(
      getActiveCharacter: () => session.activeCharacter,
      getIsGroupNonObserverMode: () => session.activeGroup != null,
      getCurrentSpeakerIdForRealism: groups.currentSpeakerId,
      getGroupCharacters: () => session.groupCharacters,
      getCharacterIdFromCard: session.characterIdFor,
      // Off means off: with the switch down the record is never read, so the
      // fragment is absent rather than stale. The check itself now lives in
      // pocketsFor — one gate for every surface, rather than each caller
      // remembering to ask (the sidebar forgot).
      getPockets: (id) => pocketsLedger.pocketsFor(id),
      // Morning-anchored: the prompt's set-aside filter must agree with the
      // pass/sidebar/facade (all on storySetAside day now) or the injection
      // would hide an outfit the record still holds after midnight.
      getCurrentDay: () => time.morningAnchoredDayCount,
      // Get-and-mark, session-filtered; see PocketsLedger.takePendingIntros.
      takePendingIntros: (charId) => pocketsLedger.takePendingIntros(charId),
      getUserName: () => deps.services.personas.persona.name,
    );
  }

  PromiseDebtInjection buildPromiseDebtInjection() {
    return PromiseDebtInjection(
      getCurrentStoryDay: () => controls.clockRunning ? time.dayCount : null,
      promiseDebtService: promiseDebt,
      getSessionId: () => session.currentSessionId,
      getActiveCharacter: () => session.activeCharacter,
      getIsGroupNonObserverMode: () => session.activeGroup != null,
      getCurrentSpeakerIdForRealism: groups.currentSpeakerId,
      getGroupCharacters: () => session.groupCharacters,
      getCharacterIdFromCard: session.characterIdFor,
      getUserName: () => deps.services.personas.persona.name,
    );
  }

  NsfwInjection buildNsfwInjection() {
    return NsfwInjection(
      nsfwService: nsfw,
      getRealismEnabled: () => controls.realismEnabled,
      getActiveCharacter: () => session.activeCharacter,
      getIsGroupNonObserverMode: () => session.activeGroup != null,
      getCurrentSpeakerIdForRealism: groups.currentSpeakerId,
      getGroupCharacters: () => session.groupCharacters,
      getCharacterIdFromCard: session.characterIdFor,
      getMutualOpening: mutualAfterglowOpening,
      getPcdActive: pcdActive,
    );
  }

  /// PR 8: is this body's grey-drift window open — the opening turn plus
  /// their next two replies, counted from message history so regen and
  /// delete rewind it for free. One stamp-backed truth feeds both the
  /// ladder rung (opening branch only) and the emotion-eval note (the
  /// full window). Guests and roster-mates are excluded the way the
  /// mutual scan already excludes them.
  bool pcdActive() {
    return pcdWindowActive(
      messages: session.messages,
      speakerId: session.activeGroup != null ? groups.currentSpeakerId() : null,
      isUser: (m) => m.isUser || _isGuestAuthored(m),
      climaxStamped: (m) => m.activeMetadata?['climax_triggered'] == true,
      pcdStamped: (m) => m.activeMetadata?['pcd'] == true,
      speakerOf: (m) {
        final card = speakerFor(m);
        return card == null ? null : session.characterIdFor(card);
      },
    );
  }

  /// PR 5: the mutual afterglow opening — the SAME beat's climax verdict
  /// said {{user}} came too. True only while the afterglow opening turn runs
  /// AND this speaker's latest climax-stamped reply carries `user_climaxed`.
  /// Never inferred: pre-PR-5 replies simply have no stamp, and a
  /// roster-mate's mutual beat is not this body's warmth.
  bool mutualAfterglowOpening() {
    if (!nsfw.isOpeningAfterglowTurn) return false;
    final group = session.activeGroup != null;
    for (final m in session.messages.reversed) {
      if (m.isUser) continue;
      // A scene guest's prose is not the host's body (M7 review): the
      // mutual beat belongs to the character the lock is counting.
      if (_isGuestAuthored(m)) continue;
      final meta = m.activeMetadata;
      if (meta?['climax_triggered'] != true) continue;
      if (group) {
        final card = speakerFor(m);
        if (card == null ||
            session.characterIdFor(card) != groups.currentSpeakerId()) {
          continue;
        }
      }
      return meta?['user_climaxed'] == true;
    }
    return false;
  }

  ChaosInjection buildChaosInjection() {
    return ChaosInjection(
      chaosModeService: chaos,
      // The member pinned for the turn in a group, the host in 1:1.
      getActiveCharacter: () => groups.workSpeakerCard(),
    );
  }

  NeedsInjection buildNeedsInjection() {
    return NeedsInjection(
      needsSimulation: needs,
      getNeedsSimEnabled: () => needsPass.active,
      getRealismEnabled: () => controls.realismEnabled,
      getIsGroupNonObserverMode: () => session.activeGroup != null,
      getCurrentSpeakerIdForRealism: groups.currentSpeakerId,
      getGroupCharacters: () => session.groupCharacters,
      getEnjoysLowHygiene: () => controls.enjoysLowHygiene,
      getGroupNeeds: groups.needsOf,
      getCharacterIdFromCard: session.characterIdFor,
      getNeedsOff: () =>
          session.activeCharacter?.frontPorchExtensions?.needsOff ?? const [],
    );
  }

  /// The central composer for the full speaker-internal realism snapshot:
  /// one clearly grouped, number-first view of relationship, emotion, time,
  /// needs (with x/100), behavioral anchors, nsfw state, etc.
  RealismStateInjection buildRealismStateInjection() {
    final sessions = deps.doors.sessions;
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
      getStandingMood: () => standingMood.injection,
      getAmbitionsEnabled: () =>
          _storageService.realismSettings.ambitionsEnabled &&
          controls.objectivesActive,
      getPromisesEnabled: () =>
          _storageService.realismSettings.promiseLedgerEnabled &&
          _storageService.memorySettings.journalEnabled,
      relationshipInjection: relationshipInjection,
      emotionInjection: emotionInjection,
      timeInjection: timeInjection,
      weatherInjection: weatherInjection,
      ambitionInjection: ambitionInjection,
      planInjection: planInjection,
      preferencesInjection: preferencesInjection,
      inventoryInjection: inventoryInjection,
      promiseDebtInjection: promiseDebtInjection,
      behavioralInjection: behavioralInjection,
      nsfwInjection: nsfwInjection,
      needsInjection: needsInjection,
      // realismActiveThisMode, NOT the bare realism gate, and the
      // difference became load-bearing on 2026-08-08 when the caller's blanket
      // `if (realismActiveThisMode)` around this whole block was removed.
      //
      // That wrapper was the only thing keeping the engine's fragments out of
      // the prompt in group Director mode and during AFK auto-responses, where
      // the engine is deliberately paused (realismActiveThisMode is false
      // while the gate stays true). Un-gating the block without moving
      // this would have started injecting bond, trust, emotion, position and
      // fixation into two modes that have never seen them — a behaviour change
      // for engine-ON users, smuggled in under a fix for engine-OFF ones.
      //
      // Wired here, the engine fragments answer to exactly the condition they
      // always did, while the fragments that are not realism features keep
      // reaching the model in every mode.
      getRealismEnabled: () => realismActiveThisMode,
      getOffStageLive: () =>
          deps.doors.entry().director.directing &&
          controls.realismEnabled &&
          !deps.doors.cast().idle.autoResponseInProgress,
      getClockRunningOverride: () => controls.clockRunning,
      // One-shot, opt-in (default OFF), coarse-worded, speculation-forbidding —
      // living-time-features.md §2 "Privacy by design". Lifted here from the
      // time fragment (2026-08-07) so it answers to its own gate: the note is
      // about WALL-CLOCK absence, and inheriting the story clock's gate is why
      // it never reached the model with the clock frozen.
      getAbsenceNote: () {
        if (!_storageService.realismSettings.absenceAckEnabled ||
            !sessions().absenceAckPending) {
          return null;
        }
        final phrase = sessions().absencePhrase;
        return phrase == null ? null : AbsenceTracker.ackNote(phrase);
      },
      getIsGroupNonObserverMode: () => session.activeGroup != null,
      getCurrentSpeakerIdForRealism: groups.currentSpeakerId,
      getGroupCharacters: () => session.groupCharacters,
      getActiveCharacter: () => session.activeCharacter,
      getCharacterIdFromCard: session.characterIdFor,
    );
  }
}

extension on RealismGraph {
  StorageService get _storageService => deps.services.storage;
  bool _isGuestAuthored(ChatMessage m) =>
      deps.doors.cast().guests.isGuestAuthoredMessage(m);
}
