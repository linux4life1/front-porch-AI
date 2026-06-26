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

  /// Full tools snapshot mirroring the desktop sidebar sections.
  Map<String, dynamic> state() {
    final chaos = _chat.chaosModeService;
    final nsfw = _chat.nsfwService;
    final time = _chat.timeService;
    return {
      'realismEnabled': _chat.realismEnabled,
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
        'arousalLevel': nsfw.arousalLevel,
        'arousalTier': nsfw.arousalTierName,
      },
      'time': {
        'timeOfDay': time.timeOfDay,
        'dayCount': time.dayCount,
        'weekday': time.narrativeWeekday,
        'passageEnabled': time.passageOfTimeEnabled,
      },
      'objectives': {
        'primary': _objJson(_chat.primaryObjective),
        'secondary':
            _chat.secondaryObjectives.map(_objJson).whereType<Map>().toList(),
        'isChecking': _chat.isCheckingCompletion,
      },
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

  // ── Objectives (per-character; default to the active character, matching the
  //    desktop sidebar — no targetCharacter override) ────────────────────────
  Future<void> setObjective(String goal, {bool isPrimary = true}) async {
    await _chat.setObjective(goal, isPrimary: isPrimary);
    _notify();
  }

  /// Generate tasks for the objective with [id]. Returns false if unknown.
  Future<bool> generateTasks(String id, {int taskCount = 5, bool nsfw = false}) {
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

  /// Resolve an objective by id across primary+secondary, run [action], notify.
  /// The single objective lookup helper — keeps the task ops above one-liners.
  Future<bool> _withObjective(
    String id,
    Future<void> Function(Objective) action,
  ) async {
    final all = <Objective>[
      if (_chat.primaryObjective != null) _chat.primaryObjective!,
      ..._chat.secondaryObjectives,
    ];
    Objective? match;
    for (final o in all) {
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
