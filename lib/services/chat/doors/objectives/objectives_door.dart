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

import 'package:front_porch_ai/database/database.dart'
    show AppDatabaseMemoryQueries, Objective;
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/chat/chat.dart';
import 'package:front_porch_ai/services/chat/doors/objectives/objective_completion_check.dart';
import 'package:front_porch_ai/services/chat/doors/objectives/objective_deps.dart';
import 'package:front_porch_ai/services/chat/doors/objectives/objective_task_editor.dart';
import 'package:front_porch_ai/services/chat/doors/objectives/objective_turn_ops.dart';
import 'package:front_porch_ai/services/chat/doors/objectives/objective_writer.dart';

export 'package:front_porch_ai/services/chat/doors/objectives/objective_completion_check.dart';
export 'package:front_porch_ai/services/chat/doors/objectives/objective_deps.dart';
export 'package:front_porch_ai/services/chat/doors/objectives/objective_task_editor.dart';
export 'package:front_porch_ai/services/chat/doors/objectives/objective_turn_ops.dart';
export 'package:front_porch_ai/services/chat/doors/objectives/objective_writer.dart';

/// The chat's objectives: the loaded list and tally, the completion check,
/// the turn ops a regen undoes, and the sidebar's task-generation prefs.
///
/// Rows key `character_id` by [ObjectiveDeps.characterIdFor]. In a group the
/// loaded list is one member's (the next speaker's, or the one focused);
/// in 1:1 it is the active character's. Whether objectives run at all is
/// [ObjectiveShellHooks.objectivesActive], read live at every gate.
class ObjectivesDoor extends ChangeNotifier {
  ObjectivesDoor(this._d);

  final ObjectiveDeps _d;

  late final ObjectiveTurnOps turnOps = ObjectiveTurnOps(this, _d);
  late final ObjectiveCompletionCheck completion = ObjectiveCompletionCheck(
    this,
    _d,
  );
  late final ObjectiveTaskEditor tasks = ObjectiveTaskEditor(this, _d);
  late final ObjectiveWriter writer = ObjectiveWriter(this, _d);

  /// Every active objective of the loaded character (primary and side).
  List<Objective> activeObjectives = [];

  /// The loaded character's goals won and let go in this chat.
  ObjectiveTally objectiveTally = ObjectiveTally.none;

  /// A completion check is running. Must be zeroed on every reset path, or
  /// an in-flight reset permanently skips future checks.
  bool isCheckingCompletion = false;

  /// Messages since the last completion check (the check's cadence).
  int messagesSinceLastCheck = 0;

  // Sidebar task-generation prefs. The panel's State is rebuilt every
  // realism turn, which reset the NSFW toggle each message (field report).
  // Session-held on purpose and NOT persisted: NSFW tasks default OFF on a
  // fresh launch.
  bool objectiveNsfwTasks = false;
  int objectiveTaskCount = 5;

  /// Each group member's own objectives, keyed by stable character id.
  /// Stored inside the group state JSON.
  final Map<String, List<Objective>> groupObjectives = {};

  ChatSessionState get _session => _d.session;

  Objective? get primaryObjective =>
      activeObjectives.where((o) => o.isPrimary).firstOrNull;
  List<Objective> get secondaryObjectives =>
      activeObjectives.where((o) => !o.isPrimary).toList();

  /// A turn's own objective work is running (see [ObjectiveTurnOps.inTurn]).
  bool get inObjectiveTurn => turnOps.inTurn;

  /// Undo the objective work [rejected]'s turn recorded (regen, delete).
  Future<void> revertTurn(ChatMessage rejected) => turnOps.revert(rejected);

  /// The per-chat counters every chat switch zeroes.
  void resetForChatSwitch() {
    activeObjectives = [];
    messagesSinceLastCheck = 0;
    isCheckingCompletion = false;
  }

  /// Whose goal [obj] is: the member it belongs to in a group, the host in
  /// 1:1. Steps are written in that character's voice and scenario.
  CharacterCard? ownerCard(Objective obj) {
    if (_session.activeGroup == null) return _session.activeCharacter;
    for (final c in _session.groupCharacters) {
      if (_d.characterIdFor(c) == obj.characterId) return c;
    }
    return null;
  }

  /// Load the active objectives for the current session from DB.
  Future<void> loadActiveObjectives() async {
    if (_session.activeCharacter == null &&
        _session.activeGroup != null &&
        _session.currentSessionId != null) {
      // A group has no active character between turns. Its lists load per
      // speaker, and the today line belongs to the chat: never "no chat".
      await loadObjectivesForCurrentSpeaker();
      return;
    }
    if (_session.activeCharacter == null || _session.currentSessionId == null) {
      activeObjectives = [];
      objectiveTally = ObjectiveTally.none;
      messagesSinceLastCheck = 0;
      isCheckingCompletion = false;
      _d.hooks.zeroSessionFlags();
      _d.hooks.clearToday();
      return;
    }
    final charId = _d.characterIdFor(_session.activeCharacter!);
    try {
      activeObjectives = await _d.db.getActiveObjectives(
        charId,
        chatId: _session.currentSessionId!,
      );
      objectiveTally = objectiveTallyFrom(
        charId,
        await _d.db.getObjectivesForCharacter(
          charId,
          chatId: _session.currentSessionId,
        ),
      );
      for (final obj in activeObjectives) {
        debugPrint(
          '[Objective] Loaded: ${obj.objective} (Primary: ${obj.isPrimary})',
        );
      }
    } catch (e) {
      debugPrint(
        '[Objective] Failed to load (will run without objectives this session): $e',
      );
      activeObjectives = [];
    }
    await _d.hooks.rebindToday();
    notifyListeners();
  }

  /// Loads the current/next speaker's own objectives in group mode, so the
  /// objective UI, generation and injection work per character in groups.
  Future<void> loadObjectivesForCurrentSpeaker() async {
    if (_session.activeGroup == null || _session.currentSessionId == null) {
      return;
    }
    final speaker =
        _d.hooks.nextSpeaker() ?? _session.groupCharacters.firstOrNull;
    if (speaker == null) {
      activeObjectives = [];
      objectiveTally = ObjectiveTally.none;
      messagesSinceLastCheck = 0;
      isCheckingCompletion = false;
      _d.hooks.zeroSessionFlags();
      notifyListeners();
      return;
    }
    await _loadAllFor(_d.characterIdFor(speaker));
  }

  /// Focus a group member's objectives so the objective management UI and
  /// generation operate on them. Does nothing in 1:1 mode.
  Future<void> focusObjectivesForGroupCharacter(CharacterCard character) async {
    if (_session.activeGroup == null) return;
    await _loadAllFor(_d.characterIdFor(character));
  }

  Future<void> _loadAllFor(String charId) async {
    final objs = await _d.db.getObjectivesForCharacter(
      charId,
      chatId: _session.currentSessionId,
    );
    activeObjectives = objs.where((o) => o.active).toList();
    objectiveTally = objectiveTallyFrom(charId, objs);
    await _d.hooks.rebindToday();
    notifyListeners();
  }

  /// A group member's personal objectives; the loaded list in 1:1.
  List<Objective> getObjectivesForGroupCharacter(CharacterCard character) {
    if (_session.activeGroup == null) return activeObjectives;
    final id = _d.characterIdFor(character);
    return groupObjectives[id] ?? const <Objective>[];
  }

  /// [character]'s active objectives in the current session. Safe from the
  /// group objective UIs: it does not touch [activeObjectives].
  Future<List<Objective>> getActiveObjectivesFor(
    CharacterCard character,
  ) async {
    if (_session.currentSessionId == null) return const [];
    final charId = _d.characterIdFor(character);
    try {
      return await _d.db.getActiveObjectives(
        charId,
        chatId: _session.currentSessionId!,
      );
    } catch (e) {
      debugPrint('[Objective] Failed to load for ${character.name}: $e');
      return const [];
    }
  }

  /// The UI's "Check now". Runs the same check as the turn path, unarmed, so
  /// a regen never undoes it. Continue and Regen do not run it.
  void forceCheckCompletion() {
    if (!_d.hooks.objectivesActive() || activeObjectives.isEmpty) return;
    completion.checkInBackground();
    notifyListeners(); // trigger UI to show spinner
  }

  /// Cast and user name tokens: they appear in most goals AND most lines,
  /// so counting them would make the mention gate always-on and make every
  /// goal about the same person look like a duplicate to the proposal gate.
  Set<String> objectiveIgnoreTokens() => <String>{
    for (final c in [?_session.activeCharacter, ..._session.groupCharacters])
      ...c.name.toLowerCase().split(RegExp(r'[^a-z0-9]+')),
    ..._d.personas().persona.name.toLowerCase().split(RegExp(r'[^a-z0-9]+')),
  }..remove('');

  /// The last few goals this character finished or let go in this chat, for
  /// the narrative judge ("finished: X", "let go: Y").
  Future<List<String>> recentEndedLines() async {
    final sid = _session.currentSessionId;
    final card = _session.activeCharacter;
    if (sid == null || card == null) return const [];
    try {
      final rows = await _d.db.getObjectivesForCharacter(
        _d.characterIdFor(card),
        chatId: sid,
      );
      return recentEndedObjectiveLines(rows);
    } catch (e) {
      debugPrint('[Objective] Could not read finished goals: $e');
      return const [];
    }
  }
}
