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
import 'package:front_porch_ai/services/storage_service.dart';
import 'package:front_porch_ai/services/web/streaming/stream_hub.dart';

/// Thin adapter for the chat *tools* sidebar — the memory/summary/chaos/NSFW/
/// scene-time/objective sections the desktop shows beside a chat. Every read is
/// a pure getter and every mutation delegates to the existing [ChatService]/
/// [StorageService] methods the desktop sidebar calls, so 1:1↔group parity and
/// the simulation behavior are inherited (never reimplemented here).
class ChatToolsFacade {
  ChatToolsFacade(this._chat, this._storage, this._hub);

  final ChatService _chat;
  final StorageService _storage;
  final StreamHub? _hub;

  /// Full tools snapshot mirroring the desktop sidebar sections. When
  /// [participantId] is given (a cast member's stableGroupId), the per-character
  /// blocks (objectives, NSFW arousal) are scoped to that focused participant so
  /// the whole sidebar follows the cast focus — not just the realism panel.
  Map<String, dynamic> state({String? participantId}) {
    final chaos = _chat.chaosModeService;
    final nsfw = _chat.nsfwService;
    final time = _chat.timeService;
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
        'autoPersonaEnabled': _storage.autoPersonaEnabled,
        'autoPersonaInterval': _storage.autoPersonaInterval,
        'evolutionEnabled': _storage.characterEvolutionEnabled,
        'evolutionInterval': _storage.evolutionInterval,
        'evolutionCount': _chat.characterEvolutionCount,
      },
      'summary': {
        'text': _chat.summary,
        'paused': _chat.summaryPaused,
        'isGenerating': _chat.isSummaryGenerating,
        'lastIndex': _chat.summaryLastIndex,
        'interval': _storage.summaryInterval,
        'maxWords': _storage.summaryMaxWords,
        'prompt': _storage.summaryPrompt,
      },
      'chaos': {
        'enabled': chaos.chaosModeEnabled,
        'nsfwEnabled': chaos.chaosNsfwEnabled,
        'pressure': chaos.chaosPressure,
        'hasPendingEvent': chaos.hasPendingChaosEvent,
      },
      'nsfw': {
        'cooldownEnabled': nsfw.nsfwCooldownEnabled,
        'cooldownTurnsRemaining': nsfw.cooldownTurnsRemaining,
        // Arousal is per-character: scope to the focused member in a group;
        // the host scalar otherwise. (Tier name is only derivable for the host
        // scalar, so members show the raw level.)
        'arousalLevel': focusedIsMember
            ? _chat.getArousalForGroupCharacter(focusedCard!)
            : nsfw.arousalLevel,
        'arousalTier': focusedIsMember ? '' : nsfw.arousalTierName,
      },
      'time': {
        'timeOfDay': time.timeOfDay,
        'dayCount': time.dayCount,
        'weekday': time.narrativeWeekday,
        'passageEnabled': time.passageOfTimeEnabled,
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

  /// Character-evolution review payload for the focused participant. Group-aware
  /// via the same per-card accessors the desktop dialog uses
  /// ([ChatService.getEvolvedPersonalityFor]/[getEvolvedScenarioFor]/
  /// [getEvolutionCountFor]), so a member's review in a group is identical to a
  /// 1:1 review — never the host-only [getEffectivePersonality] getter (null for
  /// members). Originals come straight from the focused card.
  Map<String, dynamic> evolution(String? participantId) {
    final card =
        _focusedParticipant(participantId)?.card ?? _chat.activeCharacter;
    if (card == null) {
      return {
        'name': '',
        'originalPersonality': '',
        'originalScenario': '',
        'evolvedPersonality': '',
        'evolvedScenario': '',
        'count': 0,
      };
    }
    return {
      'name': card.name,
      'originalPersonality': card.personality,
      'originalScenario': card.scenario,
      'evolvedPersonality': _chat.getEvolvedPersonalityFor(card) ?? '',
      'evolvedScenario': _chat.getEvolvedScenarioFor(card) ?? '',
      'count': _chat.getEvolutionCountFor(card),
    };
  }

  /// Save manually-edited evolved personality/scenario for the focused
  /// participant. Always targets the resolved card so a group member is updated
  /// per-character (1:1↔group parity).
  Future<void> saveEvolution(
    String? participantId,
    String personality,
    String scenario,
  ) async {
    final card =
        _focusedParticipant(participantId)?.card ?? _chat.activeCharacter;
    if (card == null) return;
    await _chat.updateEvolvedPersonality(personality, target: card);
    await _chat.updateEvolvedScenario(scenario, target: card);
    _notify();
  }

  /// Reset the focused participant's evolution back to the original card values
  /// (and zero the count). Targets the resolved card so a group member resets
  /// per-character — mirrors the desktop reset confirm.
  Future<void> resetEvolution(String? participantId) async {
    final card =
        _focusedParticipant(participantId)?.card ?? _chat.activeCharacter;
    await _chat.resetCharacterEvolution(target: card);
    _notify();
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
    await ifBool('autoPersonaEnabled', _storage.setAutoPersonaEnabled);
    await ifInt('autoPersonaInterval', _storage.setAutoPersonaInterval);
    await ifBool('evolutionEnabled', _storage.setCharacterEvolutionEnabled);
    await ifInt('evolutionInterval', _storage.setEvolutionInterval);
    await ifInt('summaryInterval', _storage.setSummaryInterval);
    await ifInt('summaryMaxWords', _storage.setSummaryMaxWords);
    if (f['summaryPrompt'] is String) {
      await _storage.setSummaryPrompt(f['summaryPrompt'] as String);
    }
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
