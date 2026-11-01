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

import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart' as drift;
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;

import 'package:front_porch_ai/database/database.dart' hide AvatarImage, World;
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/avatar_gallery.dart';
import 'package:front_porch_ai/services/chat/chat.dart';
import 'package:front_porch_ai/utils/utils.dart';

import 'session_store.dart';

/// Hydrates every session-scoped scalar the two load paths share, from one
/// [Session] row, plus the row's persona and the Porch diary import.
class SessionScalars {
  SessionScalars(this._d, this._store);

  final SessionDeps _d;
  final SessionStore _store;

  ChatSessionState get _session => _d.session;
  SessionServices get _s => _d.services;
  SessionShellHooks get _h => _d.hooks;
  RealismScope get _scope => _s.realism();
  AppDatabase get _db => _s.db();
  GroupChat? get _activeGroup => _session.activeGroup;
  RelationshipService get _relationshipService => _scope.relationship();
  NsfwService get _nsfwService => _scope.nsfw();
  TimeService get _timeService => _scope.time();
  NeedsSimulation get _needsSimulation => _scope.needs();

  /// The chat's own Realism switch, restored from the row.
  set _realismChatSwitch(bool on) => _h.setChatRealism(on);

  /// The chat's stored Needs switch: restored here, never a gate.
  bool get _needsSimEnabled => _scope.needsSimEnabled();
  set _needsSimEnabled(bool on) => _h.setNeedsSimEnabled(on);

  /// Metadata (author note, summary, name/description, look selection,
  /// fork lineage), relationship scalars (RAW persisted values — the legacy
  /// ±150→×2 era wrappers were deleted 2026-07-27; see the era-heuristic
  /// warning atop relationship_service.dart), realism/mood/emotion, time,
  /// NSFW, needs (seed-then-overlay so a blank saved vector can't clobber
  /// defaults), the "enjoys low hygiene" re-sync, per-chat theme overrides,
  /// chaos mode, transient-flag zeroing, and the session-scoped growth-ring
  /// cache.
  ///
  /// Extracted per docs/design/session-load-refactor.md Step 2. Two fixes by
  /// construction: chaos-mode scalars now load on the history-picker path
  /// too (they only loaded on library open, so picked sessions lost Chaos
  /// Mode state), and fixation truncation now runs AFTER the relationship
  /// load on both paths (loadSession used to sanitize the PREVIOUS
  /// session's fixation before loading this one's).
  ///
  /// Callers keep what genuinely differs: group-realism/scene-guest branch,
  /// objectives zeroing (library path only), per-chat gen settings
  /// placement (must precede message hydration for the retroactive
  /// sanitizer), and the persona activation. Both load paths restore the
  /// row's persona so a hydrate save cannot stamp the previous chat's live
  /// persona onto the row. The default is still unmoved (setActivePersona
  /// is chat-scoped).
  Future<void> hydrate(Session s) async {
    _store.authorNote = s.authorNote;
    _store.authorNoteStrength = s.authorNoteDepth;
    _store.summary = s.summary ?? '';
    _store.summaryLastIndex = s.summaryLastIndex ?? 0;
    _store.recapBoundSessionId = s.id;
    _store.recapClearArmed = false;
    _store.sessionName = s.name;
    _store.sessionDescription = s.description;
    _store.selectedLooks = decodeSelectedLooks(s.selectedLookAvatarId);
    _store.parentSessionId = s.parentSession;
    _store.forkIndex = s.forkIndex;
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
    _realismChatSwitch = s.realismEnabled;
    _scope.setEmotion(s.characterEmotion);
    _scope.setIntensity(s.emotionIntensity);
    _scope.setCause(s.emotionCause);
    _scope.setHeldTurns(s.emotionHeldTurns);
    _timeService.loadTimeScalars(
      timeOfDay: s.timeOfDay,
      dayCount: s.dayCount,
      startDayOfWeek: s.startDayOfWeek,
      storyClock: s.storyClock,
      storyStartDate: s.storyStartDate,
    );
    // Leftover per-chat is not a gate. Porch Life is live. One-shot flag
    // so we log the leftover once and stop rewriting it as if it mattered.
    if (!s.passageOfTimeGateMigrated) {
      final leftover = s.passageOfTimeEnabled;
      _timeService.markClockGateLeftover(leftover);
      debugPrint(
        '[Clock] migrate leftover=$leftover ignored '
        'source=${_timeService.clockGateSource}',
      );
      unawaited(
        _db.patchSession(
          SessionsCompanion(
            id: drift.Value(s.id),
            passageOfTimeGateMigrated: const drift.Value(true),
          ),
        ),
      );
    } else {
      _timeService.markClockGateSource('porch_life');
    }
    // Freeze a synthesised story date into the row the FIRST time we invent
    // it. The v38 ladder note promised legacy rows would "synthesize on
    // first load", but nothing wrote the result back, and the synthesis is
    // anchored on the real-world calendar — so the in-story date silently
    // followed whatever day the chat was opened on (96 of 109 sessions in
    // the maintainer's library were still in that state). A full save would
    // have fixed it, but a save only happens when you send a message:
    // opening a chat, reading it and closing it left the date free to move.
    //
    // A partial patch, not a full save: we are mid-hydration, so writing the
    // whole row here would persist the half-loaded needs/pockets/chaos state
    // that the lines below have not restored yet. Unawaited for the same
    // reason the other load-path writes are — open must not block on disk.
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
    // Minutes once written; a row from before v55 reads its turns × 15.
    _nsfwService.loadNsfwScalars(
      nsfwCooldownEnabled: s.nsfwCooldownEnabled,
      arousalLevel: s.arousalLevel,
      refractory:
          Refractory.read({
            RefractoryKeys.minutes: s.refractoryMinutesRemaining,
            RefractoryKeys.total: s.refractoryMinutesTotal,
            RefractoryKeys.opened: s.refractoryOpened,
            // v59 — NULL soft / absent peaks read today's defaults.
            RefractoryKeys.soft: s.refractorySoft,
            RefractoryKeys.peaks: _peakStampsFromColumn(s.refractoryPeaks),
            // v60 — the tail reads as a nested body; NULL is no tail.
            if (s.refractoryTailMinutes != null)
              RefractoryKeys.tail: {
                RefractoryKeys.minutes: s.refractoryTailMinutes,
                RefractoryKeys.total:
                    s.refractoryTailTotal ?? s.refractoryTailMinutes,
              },
            RefractoryKeys.legacyTurns: s.cooldownTurnsRemaining,
            RefractoryKeys.legacyTotal: s.cooldownTurnsTotal,
          }) ??
          Refractory.none,
    );
    // The stored switch is the chat's Afterglow, whatever Lust or recovery
    // the row holds: off hides and keeps them, so a chat holding either can
    // be one the user switched off, and must open off. Never infer the
    // switch from them (a v1.6.1 save that wrote Porch Life's off over a
    // chat's own on is answered by the existing-chats question instead).
    final nv = s.needsVector;
    // Any saved value is the chat's own choice; only one with values is a
    // kit to restore (an empty map must not wipe the seeded defaults).
    final hasSavedNeeds = nv is String && nv.isNotEmpty;
    final savedKit = hasSavedNeeds ? jsonDecode(nv) : null;
    final hasKit = savedKit is Map && savedKit.isNotEmpty;
    // A card that says nothing asks for Needs when this chat's Realism
    // (hydrated above) is on — the seed rule, NeedsPass.seedNeedsSim. An
    // explicit card choice is read as before.
    final cardWantsNeeds =
        _activeGroup == null &&
        _s.needsPass().seedNeedsSim(
          _session.activeCharacter?.frontPorchExtensions?.needsSimChoice,
        );
    // The session flag is the chat's own switch, column default FALSE. A row
    // saved before chats recorded their choice (no vector at all) still
    // promotes ON when its card asks for Needs. Explicit OFF keeps its
    // vector (or an empty one) so it is not that stale row. ON stays ON.
    _needsSimEnabled = needsSimAfterHydrate(
      sessionEnabled: s.needsSimEnabled,
      cardEnabled: cardWantsNeeds,
      hasSavedVector: hasSavedNeeds,
      isGroup: _activeGroup != null,
    );
    _h.setObjectivesEnabled(s.objectivesEnabled);
    if (_needsSimEnabled) {
      // Seed defaults first, then overlay the saved vector ONLY when it has
      // values. A blank saved vector (e.g. needs was toggled on mid-chat
      // before it seeded) must NOT clobber the defaults, or the sidebar
      // shows no scores.
      final ext = _session.activeCharacter?.frontPorchExtensions;
      if (ext != null && _activeGroup == null) {
        _needsSimulation.initializeFreshWithDefaults(
          NeedsSimulation.baselinesFromExtensions(ext),
        );
      } else {
        _needsSimulation.initializeFresh();
      }
      if (hasKit) applyNeedsPersist(_needsSimulation, savedKit);
    } else if (hasKit) {
      applyNeedsPersist(_needsSimulation, savedKit);
    } else {
      _needsSimulation.clearVector();
    }

    // v47 — restore the 1:1 pockets record. Group members' records ride
    // groupRealismState and are restored with it; this is the half that had
    // no home and so was silently dropped on every reload.
    //
    // Restored regardless of whether Pockets is currently switched on: a
    // record only exists because it was on at the time, and rolling a chat
    // open must not be the thing that empties their hands.
    final pj = s.pockets;
    _h.setHostPockets(
      (pj is String && pj.isNotEmpty) ? Pockets.fromJson(jsonDecode(pj)) : null,
    );
    // No saved record means this chat has never run the pass, so fall back
    // to what the card starts them with — otherwise the sidebar reads empty
    // until after the first reply and an author who just set a wardrobe
    // concludes it did not save. Skipped when a record exists.
    _h.seedPocketsFromCards();

    _store.today.todayObjectiveId = s.todayObjectiveId;
    _store.today.todayObjectiveText = null;

    // Re-sync from the character's current setting so that toggling
    // "Enjoys low hygiene" on the character affects existing chats on next
    // load.
    _h.setEnjoysLowHygiene(
      _session.activeCharacter?.frontPorchExtensions?.enjoysLowHygiene ?? false,
    );

    // Load per-chat theme overrides.
    try {
      final themeJson = await _db.getThemeOverrides(s.id);
      _store.themeOverrides = ChatThemeOverrides.fromJsonString(themeJson);
    } catch (_) {
      _store.themeOverrides = ChatThemeOverrides();
    }

    // Context Budget bars from the last real send (empty on older chats).
    try {
      await _h.loadContextBudget(s.id);
    } catch (_) {
      _h.clearContextBudget();
    }

    _needsSimulation.resetBuffers();
    // Chaos scalars — the shared load is what fixed session-load-refactor.md
    // bug #1 (loadSession never loaded these, so history-picked chats lost
    // Chaos Mode state and pressure reset to defaults).
    _s.chaos().loadScalars(
      modeEnabled: s.chaosModeEnabled,
      pressure: s.chaosPressure,
      // A group's spicy switch lives on the group row (seeded on entry).
      nsfwEnabled: _activeGroup == null ? s.chaosNsfwEnabled : null,
    );
    debugPrint(
      '[Chat] session scalars hydrated: arousal=${_nsfwService.arousalLevel}, fixation=${_relationshipService.activeFixation}/${_relationshipService.fixationLifespan}',
    );

    // Transient-flag zeroing shared by both loaded paths (keep reset blocks in sync).
    _store.summaryPaused = false;
    _store.isSummaryGenerating = false;
    _h.setGrowthPassRunning(false);

    // Cache growth rings (and any not-yet-distilled legacy evolved blobs) for
    // this session so the injection layer can read them synchronously —
    // scoped to the session, not the character (1:1 + group both).
    await _s.growthDesk().refreshCache();
  }

  /// Chat-scoped only — never moves [UserPersonaService.defaultPersonaId].
  Future<void> activateSessionPersona(Session session) async {
    final personas = _s.personas;
    final sessionPersonaId = session.userPersonaId;
    final knownPersona =
        sessionPersonaId != null &&
        personas.personas.any((p) => p.id == sessionPersonaId);
    await personas.setActivePersona(
      knownPersona ? sessionPersonaId : personas.defaultPersonaId,
    );
  }

  /// Diary targets for LLMerta porch import: library stableGroupId (match) +
  /// journal characterId (plant key). 1:1 uses the same id for both; group
  /// members match on originStableId and plant under the live card id.
  Future<List<PorchDiaryTarget>> _buildPorchDiaryTargets() async {
    final idFor = _h.characterIdFor;
    if (_activeGroup == null && _session.activeCharacter != null) {
      final id = idFor(_session.activeCharacter!);
      return [PorchDiaryTarget(libraryStableGroupId: id, diaryCharacterId: id)];
    }
    if (_activeGroup == null) return const [];

    final repo = _s.groupRepository();
    if (repo == null) {
      // Fall back to live roster stable ids (origin may equal library for
      // many members whose avatar stem matches the library basename).
      return [
        for (final c in _session.groupCharacters)
          PorchDiaryTarget(
            libraryStableGroupId: idFor(c),
            diaryCharacterId: idFor(c),
          ),
      ];
    }

    final rows = await repo.getMembersForGroup(_activeGroup!.id);
    final library = _s.characters()?.characters ?? const <CharacterCard>[];
    final targets = <PorchDiaryTarget>[];
    for (final m in rows) {
      if (m.avatarFilename == null) continue;
      final resolvedPath = path.join(
        _s.storage.groupsDir.path,
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
  Future<void> maybeImportPorchMemories() async {
    final sessionId = _session.currentSessionId;
    if (sessionId == null) return;
    final personaId = _s.personas.persona.id;
    if (personaId.isEmpty) return;
    try {
      final targets = await _buildPorchDiaryTargets();
      if (targets.isEmpty) return;
      await _s.porchImport().tryImportForSession(
        sessionId: sessionId,
        userPersonaId: personaId,
        targets: targets,
      );
    } catch (e) {
      debugPrint('[PorchMemories] session hook failed: $e');
    }
  }
}

/// Reads the v59 peak-stamp column: JSON text written by this app; NULL or
/// junk decodes to "no peaks", matching every body saved before PR 3.
List<int> _peakStampsFromColumn(String? raw) {
  if (raw == null || raw.isEmpty) return const [];
  try {
    return Refractory.readPeakStamps(jsonDecode(raw));
  } catch (_) {
    return const [];
  }
}
