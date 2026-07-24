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

import 'package:front_porch_ai/database/database.dart' show Objective;
import 'package:front_porch_ai/models/character_card.dart';
import 'package:front_porch_ai/models/chat_participant.dart';
import 'package:front_porch_ai/services/chat_service.dart';
import 'package:front_porch_ai/services/chat/growth_physics.dart';
import 'package:front_porch_ai/services/chat/growth_store.dart';
import 'package:front_porch_ai/services/chat/journal_store.dart';
import 'package:front_porch_ai/services/chat/ambition_service.dart';
import 'package:front_porch_ai/services/chat/weather_engine.dart';
import 'package:front_porch_ai/services/story/faithful_mode.dart';
import 'package:front_porch_ai/services/story_repository.dart';
import 'package:front_porch_ai/services/user_persona_service.dart';
import 'package:front_porch_ai/services/storage_service.dart';
import 'package:front_porch_ai/services/web/streaming/stream_hub.dart';

/// Thin adapter for the chat *tools* sidebar — the memory/summary/chaos/NSFW/
/// scene-time/objective sections the desktop shows beside a chat. Every read is
/// a pure getter and every mutation delegates to the existing [ChatService]/
/// [StorageService] methods the desktop sidebar calls, so 1:1↔group parity and
/// the simulation behavior are inherited (never reimplemented here).
class ChatToolsFacade {
  ChatToolsFacade(
    this._chat,
    this._storage,
    this._hub, {
    StoryRepository? storyRepo,
    UserPersonaService? personas,
  }) : _storyRepo = storyRepo,
       _personas = personas;

  final ChatService _chat;
  final StorageService _storage;
  final StreamHub? _hub;

  /// Living Time §4 "turn this chat into a story" deps — optional so hosts
  /// without Porch Stories wired keep working; the endpoint 400s without.
  final StoryRepository? _storyRepo;
  final UserPersonaService? _personas;

  /// Full tools snapshot mirroring the desktop sidebar sections. When
  /// [participantId] is given (a cast member's stableGroupId), the per-character
  /// blocks (objectives, NSFW arousal) are scoped to that focused participant so
  /// the whole sidebar follows the cast focus — not just the realism panel.
  Map<String, dynamic> state({String? participantId}) {
    final chaos = _chat.chaosModeService;
    final nsfw = _chat.nsfwService;
    final time = _chat.timeService;
    final weather = _chat.currentWeather;
    final focused = _focusedParticipant(participantId);
    final focusedCard = focused?.card ?? _chat.activeCharacter;
    final focusedIsMember =
        focused != null && !focused.isHost && focused.realismEnabled;
    return {
      'realismEnabled': _chat.realismEnabled,
      'needsEnabled': _chat.needsSimEnabled,
      // Global One-Shot Eval flag (fuses the multi-call realism evals into one
      // LLM call). A single StorageService flag — identical in 1:1 and group, so
      // no per-character/group branch is needed (parity inherited).
      'realismOneShotEval': _storage.realismOneShotEval,
      'focusedId': focused?.id,
      'memory': {
        'ragEnabled': _storage.ragEnabled,
        'ragRetrievalCount': _storage.ragRetrievalCount,
        'ragWindowSize': _storage.ragWindowSize,
        'journalEnabled': _storage.journalEnabled,
        'journalInterval': _storage.journalInterval,
        'growthEnabled': _storage.characterEvolutionEnabled,
        'growthInterval': _storage.growthInterval,
        'growthReviewFirst': _storage.growthReviewFirst,
      },
      // Kept under the 'summary' key for the bundled web UI: this is the
      // Journal's per-chat recap ("Where we are") — same ChatService surface
      // as before (text/paused/isGenerating/lastIndex).
      'summary': {
        'text': _chat.summary,
        'paused': _chat.summaryPaused,
        'isGenerating': _chat.isSummaryGenerating,
        'lastIndex': _chat.summaryLastIndex,
      },
      'chaos': {
        'enabled': chaos.chaosModeEnabled,
        'nsfwEnabled': chaos.chaosNsfwEnabled,
        'pressure': chaos.chaosPressure,
        'hasPendingEvent': chaos.hasPendingChaosEvent,
      },
      'nsfw': {
        // NSFW Enhancements flag. In a group the live nsfwService scalar is
        // per-speaker volatile (reloaded for whoever last evaluated), so read
        // the stable per-member group flag instead — matching the desktop
        // CharacterStateSettings split-brain. Write side (setNsfwCooldown)
        // already propagates to every member, so this stays consistent.
        'cooldownEnabled': _chat.activeGroup != null
            ? _chat.isGroupNsfwEnabled
            : nsfw.nsfwCooldownEnabled,
        'cooldownTurnsRemaining': nsfw.cooldownTurnsRemaining,
        // Arousal is per-character: scope to the focused member in a group;
        // the host scalar otherwise. (Tier name is only derivable for the host
        // scalar, so members show the raw level.)
        'arousalLevel': focusedIsMember
            ? _chat.getArousalForGroupCharacter(focusedCard!)
            : nsfw.arousalLevel,
        'arousalTier': focusedIsMember ? '' : nsfw.arousalTierName,
      },
      // Ambitions (Living Time §6) for the focused participant — additive;
      // same ChatService.ambitionsFor merge the desktop sidebar reads.
      'ambitions': focusedCard == null || (focused?.isLite ?? false)
          ? const []
          : [
              for (final a in _chat.ambitionsFor(focusedCard))
                {
                  'text': a.text,
                  'progress': a.progress,
                  'stage': AmbitionService.stageWord(a.progress),
                },
            ],
      'time': {
        'timeOfDay': time.timeOfDay,
        'dayCount': time.dayCount,
        'weekday': time.narrativeWeekday,
        'passageEnabled': time.passageOfTimeEnabled,
        // Living Time story weather (living-time-features.md §3) — additive
        // and nullable; older web bundles simply ignore it.
        'weather': weather == null
            ? null
            : {
                'condition': weather.condition.name,
                'temp': weather.temp.name,
                'season': weather.season,
                'label': WeatherEngine.label(weather),
                'emoji': WeatherEngine.emoji(weather.condition),
              },
        // Story Calendar (story-calendar.md) — additive; older web bundles
        // simply ignore these.
        'clock': time.displayClock,
        'date': time.displayShortDate,
        'dateLong': time.displayDate,
        'storyClock': time.storyClockIso,
        'storyStartDate': time.storyStartDateIso,
      },
      // Objectives are per-character; scope to the focused participant (lite
      // guests have none). getObjectivesForGroupCharacter returns the global
      // list in 1:1, so this is correct in both modes.
      'objectives': _objectivesBlock(
        (focused?.isLite ?? false) ? null : focusedCard,
      ),
      // Group-only settings (turn order / director / prompts), gated below.
      'group': _groupBlock(),
    };
  }

  /// The focused cast participant, or null when none/unknown.
  ChatParticipant? _focusedParticipant(String? id) {
    if (id == null) return null;
    for (final p in _chat.cast) {
      if (p.id == id) return p;
    }
    return null;
  }

  /// Objectives block for [card] (split primary/secondary). Empty when null.
  Map<String, dynamic> _objectivesBlock(CharacterCard? card) {
    if (card == null) {
      return {
        'primary': null,
        'secondary': const [],
        'isChecking': _chat.isCheckingCompletion,
      };
    }
    Objective? primary;
    final secondary = <Objective>[];
    for (final o in _chat.getObjectivesForGroupCharacter(card)) {
      if (o.isPrimary && primary == null) {
        primary = o;
      } else {
        secondary.add(o);
      }
    }
    return {
      'primary': _objJson(primary),
      'secondary': secondary.map(_objJson).whereType<Map>().toList(),
      'isChecking': _chat.isCheckingCompletion,
    };
  }

  /// Group-only settings for the sidebar's group section (null in 1:1). The web
  /// gates this block on `group != null`. Per-member prompt overrides are keyed
  /// by stableGroupId (== ChatParticipant.id).
  Map<String, dynamic>? _groupBlock() {
    final g = _chat.activeGroup;
    if (g == null) return null;
    return {
      'name': g.name,
      'turnOrder': g.turnOrder.name,
      'directorMode': _chat.observerMode,
      'systemPrompt': g.systemPrompt,
      'scenario': g.scenario,
      'firstMessage': g.firstMessage,
      'members': _chat.cast
          .map(
            (p) => {
              'id': p.id,
              'name': p.name,
              'prompt': g.characterSystemPrompts[p.id] ?? '',
            },
          )
          .toList(),
    };
  }

  Map<String, dynamic>? _objJson(Objective? o) {
    if (o == null) return null;
    return {
      'id': o.id,
      'objective': o.objective,
      'isPrimary': o.isPrimary,
      'checkFrequency': o.checkFrequency,
      'tasks': _chat.tasksForObjective(o),
    };
  }

  // ── Toggles (chat-scoped; delegate to the same ChatService methods the
  //    desktop sidebar calls, which persist + handle group parity) ──────────
  Future<void> setRealismEnabled(bool v) async {
    await _chat.setRealismEnabled(v);
    _notify();
  }

  /// Live in-chat Needs Simulation toggle. Delegates to the same
  /// [ChatService.setNeedsSimEnabled] the desktop sidebar calls, so decay /
  /// scene-impact behavior and 1:1↔group parity are inherited.
  Future<void> setNeedsEnabled(bool v) async {
    await _chat.setNeedsSimEnabled(v);
    _notify();
  }

  /// Global One-Shot Eval toggle (experimental). Flips the same
  /// [StorageService.realismOneShotEval] flag the desktop realism sidebar drives.
  /// One-shot must produce 1:1-equivalent realism/needs deltas to the multi-call
  /// path (engine contract), so the web only flips the flag — never branches.
  Future<void> setOneShotEval(bool v) async {
    await _storage.setRealismOneShotEval(v);
    _notify();
  }

  /// Growth Rings payload for the focused participant (group-aware via the
  /// same owner-id keying the desktop GrowthPanel uses; 1:1 falls back to the
  /// host). Rings ship with derived tier + decoded receipts so the web
  /// renders without re-implementing the physics.
  Map<String, dynamic> growth(String? participantId) {
    final owner = _growthOwner(participantId);
    if (owner == null) {
      return {'name': '', 'ownerId': '', 'rings': const [], 'passRunning': false};
    }
    final rings = _chat.growthRingsForOwner(owner.id);
    return {
      'name': owner.name,
      'ownerId': owner.id,
      'passRunning': _chat.isGrowthPassRunning,
      'hasLegacyBlob': _chat.hasLegacyGrowthBlobFor(owner.id),
      'reviewPending': _chat.growthReview.hasPendingFor(_chat.currentSessionId)
          ? _chat.growthReview.pending!.totalProposals
          : 0,
      'rings': [
        for (final r in rings)
          {
            'id': r.id,
            'content': r.content,
            'category': r.category,
            'tier': GrowthPhysics.tierOf(r),
            'strength': r.strength,
            'pinned': r.pinned,
            'retired': r.retired,
            'receipts': GrowthStore.receiptsOf(r),
          },
      ],
    };
  }

  /// One growth mutation from the web timeline — same ChatService surface the
  /// desktop panel uses, so behavior can't diverge. Unknown ids no-op.
  Future<void> growthAction(
    String? participantId,
    String action,
    Map<String, dynamic> body,
  ) async {
    final owner = _growthOwner(participantId);
    if (owner == null) return;
    final ringId = body['ringId'] as String? ?? '';
    final rings = _chat.growthRingsForOwner(owner.id);
    final ring = rings.where((r) => r.id == ringId).firstOrNull;
    switch (action) {
      case 'plant':
        await _chat.plantGrowthRingFor(
          owner.id,
          body['text'] as String? ?? '',
          category: body['category'] as String? ?? 'trait',
        );
        break;
      case 'edit':
        if (ring == null) return;
        await _chat.editGrowthRing(
          ring,
          text: body['text'] as String? ?? ring.content,
          category: body['category'] as String?,
        );
        break;
      case 'pin':
        if (ring == null) return;
        await _chat.setGrowthRingPinned(ring.id, !(ring.pinned));
        break;
      case 'retire':
        if (ring == null) return;
        await _chat.retireGrowthRing(ring.id);
        break;
      case 'restore':
        if (ring == null) return;
        await _chat.unretireGrowthRing(ring);
        break;
      case 'delete':
        if (ring == null) return;
        await _chat.deleteGrowthRing(ring.id);
        break;
      case 'reset':
        await _chat.resetGrowthFor(owner.id);
        break;
      case 'check':
        await _chat.forceGrowthPass();
        break;
    }
    _notify();
  }

  /// The parked growth-review batch (review-first mode, default OFF) in a
  /// flat, index-addressed shape for the web modal.
  Map<String, dynamic> growthReviewBatch() {
    final batch = _chat.growthReview.pending;
    if (batch == null || batch.sessionId != _chat.currentSessionId) {
      return {'pending': false, 'owners': const []};
    }
    return {
      'pending': true,
      'owners': [
        for (final owner in batch.owners)
          {
            'ownerName': owner.ownerName,
            'ops': [
              for (final op in owner.ops)
                {
                  'action': op.action.name,
                  'text': op.text,
                  'oldContent': op.oldContent ?? '',
                },
            ],
          },
      ],
    };
  }

  /// Settle the parked batch: [rejected] is a list of "ownerIdx:opIdx" keys
  /// to uncheck; the rest applies (or everything discards).
  Future<void> settleGrowthReview({
    required bool apply,
    List<String> rejected = const [],
  }) async {
    final batch = _chat.growthReview.pending;
    if (batch != null) {
      for (var o = 0; o < batch.owners.length; o++) {
        final ops = batch.owners[o].ops;
        for (var i = 0; i < ops.length; i++) {
          if (rejected.contains('$o:$i')) ops[i].accepted = false;
        }
      }
    }
    if (apply) {
      await _chat.growthReview.apply();
    } else {
      await _chat.growthReview.discard();
    }
    _notify();
  }

  /// The growth owner behind [participantId]: the focused participant, or the
  /// host (1:1) / first member as fallback — mirrors the desktop's focused
  /// default.
  ChatParticipant? _growthOwner(String? participantId) {
    final focused = _focusedParticipant(participantId);
    if (focused != null) return focused;
    for (final p in _chat.cast) {
      if (p.isHost) return p;
    }
    return _chat.cast.firstOrNull;
  }


  Future<void> setChaosEnabled(bool v) async {
    await _chat.setChaosModeEnabled(v);
    _notify();
  }

  Future<void> setChaosNsfw(bool v) async {
    await _chat.setChaosNsfwEnabled(v);
    _notify();
  }

  Future<void> setNsfwCooldown(bool v) async {
    await _chat.setNsfwCooldownEnabled(v);
    _notify();
  }

  Future<void> setPassageOfTime(bool v) async {
    await _chat.setPassageOfTimeEnabled(v);
    _notify();
  }

  /// Group director (observer) mode — group-only; the web gates the control.
  void setDirectorMode(bool v) {
    _chat.setObserverMode(v);
    _notify();
  }

  /// Story Calendar writes (story-calendar.md §6): set the current story
  /// moment / re-anchor Day 1. Mirrors the desktop dialog's two gear actions.
  Future<void> setStoryClock(DateTime clock) async {
    await _chat.setStoryClock(clock);
    _notify();
  }

  Future<void> setStoryStartDate(DateTime date) async {
    await _chat.setStoryStartDate(date);
    _notify();
  }

  /// The calendar read payload: diary owners + every stamped memory grouped
  /// by story day for [ownerId] (defaults to the first owner). One cardsFor
  /// read per call — cards are capped per owner.
  Future<Map<String, dynamic>> calendar(String? ownerId) async {
    final sessionId = _chat.currentSessionId;
    final time = _chat.timeService;
    final owners = _chat.cast.where((p) => !p.isLite).toList();
    final owner = owners.where((p) => p.id == ownerId).firstOrNull ??
        owners.firstOrNull;
    final days = <Map<String, dynamic>>[];
    if (sessionId != null && owner != null) {
      final cards = await _chat.journalStore.cardsFor(sessionId, owner.id);
      final byDay = <int, List<Map<String, dynamic>>>{};
      for (final card in cards) {
        final (day, _) = JournalStore.stampOf(card);
        if (day == null) continue;
        byDay.putIfAbsent(day, () => []).add({
          'content': card.content,
          'category': card.category,
          'feeling': card.emotionLabel,
          'intensity': card.emotionIntensity,
          'pinned': card.pinned,
        });
      }
      for (final entry in byDay.entries) {
        days.add({'day': entry.key, 'cards': entry.value});
      }
      days.sort((a, b) => (a['day'] as int).compareTo(b['day'] as int));
    }
    return {
      'storyStartDate': time.storyStartDateIso,
      'storyClock': time.storyClockIso,
      'currentDay': time.dayCount,
      'owner': owner?.id,
      'owners': [
        for (final p in owners) {'id': p.id, 'name': p.name},
      ],
      'days': days,
    };
  }

  /// "Our Story" milestones timeline (Living Time §7) — the same read-model
  /// the desktop journal dialog's timeline tab uses (ChatService.milestoneFeed),
  /// so the two surfaces cannot drift. Additive endpoint; owner defaults to
  /// the first diary owner like [calendar].
  Future<Map<String, dynamic>> timeline(String? ownerId) async {
    final sessionId = _chat.currentSessionId;
    final owners = _chat.cast.where((p) => !p.isLite).toList();
    final owner = owners.where((p) => p.id == ownerId).firstOrNull ??
        owners.firstOrNull;
    final entries = <Map<String, dynamic>>[];
    if (sessionId != null && owner != null) {
      for (final e in await _chat.milestoneFeed.entriesFor(
        sessionId: sessionId,
        characterId: owner.id,
        messages: _chat.messages,
      )) {
        entries.add({
          'kind': e.kind,
          'text': e.text,
          'day': ?e.storyDay,
          'position': ?e.position,
          'emotion': ?e.emotion,
        });
      }
    }
    return {
      'owner': owner?.id,
      'owners': [
        for (final p in owners) {'id': p.id, 'name': p.name},
      ],
      'entries': entries,
    };
  }

  /// Living Time §4: create the pre-configured "this chat as a story"
  /// project — same shared builder as the desktop dialog (faithful_mode.dart)
  /// so the entries cannot drift. Returns {id,title} or an {error}.
  Future<Map<String, dynamic>> toStory({
    required bool faithful,
    required String length,
    required String pov,
  }) async {
    final repo = _storyRepo;
    final character = _chat.activeCharacter;
    final sessionId = _chat.currentSessionId;
    if (repo == null) return {'error': 'stories unavailable'};
    if (character == null || sessionId == null || _chat.isGroupMode) {
      return {'error': '1:1 chat with a character required'};
    }
    final project = buildChatStoryProject(
      sessionId: sessionId,
      character: character,
      characterId: character.dbId ?? character.name,
      userName: _personas?.persona.name ?? 'User',
      recap: _chat.summary,
      faithful: faithful,
      length: length,
      pov: pov,
    );
    await repo.saveProject(project);
    return {'id': project.dbId, 'title': project.title};
  }

  /// Manually nudge the scene clock forward/back one period (desktop chevrons).
  Future<void> nudgeTime(int delta) async {
    await _chat.nudgeTimePeriod(delta);
    _notify();
  }

  // ── Summary controls ─────────────────────────────────────────────────────
  Future<void> regenerateSummary() async {
    await _chat.forceSummaryUpdate();
    _notify();
  }

  void setSummaryPaused(bool v) {
    _chat.setSummaryPaused(v);
    _notify();
  }

  void setSummaryText(String text) {
    _chat.setSummary(text);
    _notify();
  }

  /// Apply any subset of the global memory/summary numeric+text settings. Keys
  /// mirror the [state] `memory`/`summary` blocks; absent keys are unchanged.
  Future<void> applySettings(Map<String, dynamic> f) async {
    Future<void> ifBool(String k, Future<void> Function(bool) set) async {
      if (f[k] is bool) await set(f[k] as bool);
    }

    Future<void> ifInt(String k, Future<void> Function(int) set) async {
      final v = f[k];
      if (v is int) await set(v);
    }

    await ifBool('ragEnabled', _storage.setRagEnabled);
    await ifInt('ragRetrievalCount', _storage.setRagRetrievalCount);
    await ifInt('ragWindowSize', _storage.setRagWindowSize);
    await ifBool('journalEnabled', _storage.setJournalEnabled);
    await ifInt('journalInterval', _storage.setJournalInterval);
    await ifInt('journalMaxCards', _storage.setJournalMaxCards);
    await ifBool('growthEnabled', _storage.setCharacterEvolutionEnabled);
    await ifInt('growthInterval', _storage.setGrowthInterval);
    await ifBool('growthReviewFirst', _storage.setGrowthReviewFirst);
    _notify();
  }

  // ── Objectives (per-character; scoped to the focused cast participant so a
  //    new goal attaches to whoever the sidebar is focused on) ───────────────
  Future<void> setObjective(
    String goal, {
    bool isPrimary = true,
    String? participantId,
  }) async {
    await _chat.setObjective(
      goal,
      isPrimary: isPrimary,
      targetCharacter: _focusedParticipant(participantId)?.card,
    );
    _notify();
  }

  /// Generate tasks for the objective with [id]. Returns false if unknown.
  Future<bool> generateTasks(
    String id, {
    int taskCount = 5,
    bool nsfw = false,
  }) {
    return _withObjective(id, (o) async {
      await _chat.generateObjectiveTasks(o, taskCount: taskCount, nsfw: nsfw);
    });
  }

  Future<bool> addTask(String id, String description) {
    return _withObjective(id, (o) => _chat.addManualTask(o, description));
  }

  Future<bool> toggleTask(String id, int taskIndex) {
    return _withObjective(id, (o) => _chat.toggleTask(o, taskIndex));
  }

  Future<bool> updateTask(String id, int taskIndex, String description) {
    return _withObjective(
      id,
      (o) => _chat.updateTask(o, taskIndex, description),
    );
  }

  Future<bool> removeTask(String id, int taskIndex) {
    return _withObjective(id, (o) => _chat.removeTask(o, taskIndex));
  }

  Future<bool> setCheckFrequency(String id, int frequency) {
    return _withObjective(id, (o) => _chat.updateCheckFrequency(o, frequency));
  }

  Future<bool> clearObjective(String id) {
    return _withObjective(id, (o) => _chat.clearObjective(o));
  }

  /// Promote a side quest to the primary quest in place (same
  /// [ChatService.promoteObjective] the desktop sidebar uses — keeps tasks,
  /// demotes any existing primary).
  Future<bool> promoteObjective(String id) {
    return _withObjective(id, (o) => _chat.promoteObjective(o));
  }

  void checkCompletion() {
    _chat.forceCheckCompletion();
    _notify();
  }

  /// Resolve an objective by id, run [action], notify. Searches every cast
  /// participant's objectives (not just the host's) so task ops work on whoever
  /// the sidebar is focused on, in 1:1 or group.
  Future<bool> _withObjective(
    String id,
    Future<void> Function(Objective) action,
  ) async {
    final seen = <String>{};
    final all = <Objective>[
      if (_chat.primaryObjective != null) _chat.primaryObjective!,
      ..._chat.secondaryObjectives,
      for (final p in _chat.cast)
        ..._chat.getObjectivesForGroupCharacter(p.card),
    ];
    Objective? match;
    for (final o in all) {
      if (!seen.add(o.id)) continue;
      if (o.id == id) {
        match = o;
        break;
      }
    }
    if (match == null) return false;
    await action(match);
    _notify();
    return true;
  }

  void _notify() => _hub?.broadcastChatUpdate();
}
