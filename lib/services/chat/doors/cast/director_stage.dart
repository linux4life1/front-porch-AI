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
import 'package:front_porch_ai/services/chat/doors/cast/cast_door.dart';
import 'package:front_porch_ai/services/chat/doors/realism/realism_graph.dart';
import 'package:front_porch_ai/services/chat/doors/turn/turn_engine.dart';

/// {{user}} on and off a group's stage (Director Mode), the director's
/// goal and whispers, narrator beats, and the narrator's bridge over a
/// long time skip.
class DirectorStage {
  DirectorStage(this._door, this._d);

  final CastDoor _door;
  final CastDeps _d;

  ChatSessionState get _session => _d.session;
  CastShellHooks get _h => _d.hooks;
  TurnEngine get _turn => _d.turn();
  SceneGuestState get _state => _door.guests.state;
  GuestFlow get _guests => _door.guests;
  DirectorScene get _scene => _door.directorScene;

  /// `/director`: {{user}} steps out of a group scene to direct it, with the
  /// same narrated departure and UNDO as a full member's `/exit`. The next
  /// character reacts to them leaving, then Director Mode comes on. The
  /// goodbye scores nothing (skipSpeakerEval): nobody said anything new.
  Future<bool> stepUserOffStage() async {
    if (_session.activeGroup == null ||
        (_session.groupManager?.observerMode ?? false) ||
        _turn.isTurnBusy) {
      return false;
    }
    // An open member-exit undo window closes here, as a send would close it.
    await _door.roster.commitPendingMemberExit();
    _guests.clearExitUndo();
    if (_session.activeGroup == null) return false;
    final name = _d.personas.persona.name;
    final before = _session.messages.length;
    _door.entranceDirective = userStepsOutDirective(name);
    try {
      await _turn.generate(GenerationMode.normal, skipSpeakerEval: true);
    } catch (e) {
      debugPrint('[Director] step-out narration failed: $e');
      _door.entranceDirective = null; // don't leak into a later turn
    }
    await dropSilentStagedTurn(before);
    _h.setObserverMode(true);
    final last = _session.messages.lastOrNull;
    _state.exitUndoUserStep = true;
    _state.exitUndoMessage =
        (_session.messages.length > before &&
            last != null &&
            !last.isUser &&
            last.sender != 'System')
        ? last
        : null;
    _state.exitUndoOfferName = name;
    await _d.saveChat();
    _d.notify();
    return true;
  }

  /// `/director off`: {{user}} walks back in. Director Mode goes off first,
  /// so the next character sees the user present and greets them. The
  /// greeting scores nothing: the last user-side line is a director's note.
  Future<bool> stepUserOnStage() async {
    if (!_h.directing() || _turn.isTurnBusy) return false;
    _guests.clearExitUndo();
    _h.setObserverMode(false);
    _door.entranceDirective = userReturnsDirective(_d.personas.persona.name);
    final before = _session.messages.length;
    try {
      await _turn.generate(GenerationMode.normal, skipSpeakerEval: true);
    } catch (e) {
      debugPrint('[Director] step-in narration failed: $e');
      _door.entranceDirective = null;
    }
    await dropSilentStagedTurn(before);
    await _d.saveChat();
    _d.notify();
    return true;
  }

  /// Undo for `/director`: delete the goodbye turn (rewinding what it
  /// applied) and put {{user}} back on stage. False when the open undo is
  /// someone else's exit.
  Future<bool> undoUserStepOut() async {
    if (!_state.exitUndoUserStep) return false;
    final goodbye = _state.exitUndoMessage;
    _guests.clearExitUndo();
    if (goodbye != null) {
      final idx = _session.messages.indexOf(goodbye);
      if (idx >= 0) _h.deleteMessage(idx); // removes + reverts + saves
    }
    _h.setObserverMode(false);
    await _d.saveChat();
    _guests.setStatus('You are back in the scene.');
    _d.notify();
    return true;
  }

  /// The director's pinned scene goal, or empty.
  String get directorGoal => _scene.goal;

  /// The director's private whispers, by member id.
  Map<String, String> get directorWhispers => _scene.whispers;

  /// The whispers for members still in the scene, in cast order.
  List<({String id, String name, String text})> get directorWhisperRows => [
    for (final c in _session.groupCharacters)
      if (_scene.whispers[_d.characterIdFor(c)] case final w?)
        (id: _d.characterIdFor(c), name: c.name, text: w),
  ];

  /// Pins [text] as the scene goal; empty clears it. Saved per chat.
  Future<void> setDirectorGoal(String text) async {
    if (_session.activeGroup == null) return;
    _scene.setGoal(text);
    await _d.saveChat();
    _d.notify();
  }

  /// Sets the private whisper for the member with [memberId]; empty clears.
  Future<void> setDirectorWhisper(String memberId, String text) async {
    if (_session.activeGroup == null) return;
    final known = _session.groupCharacters.any(
      (c) => _d.characterIdFor(c) == memberId,
    );
    // A stale id can only be cleared; it never gains a whisper.
    if (!known && text.trim().isNotEmpty) return;
    _scene.setWhisper(memberId, text);
    await _d.saveChat();
    _d.notify();
  }

  /// `/narrate`: one narrator beat lands as a scene card, then the next
  /// character reacts to it as they would to a note. False when a turn is
  /// already running, or the user isn't directing. The narrator's call
  /// counts as a running turn, so a note, a cue, an auto-chat tick or a chat
  /// switch waits for it; a beat that returns to another chat is dropped.
  Future<bool> narrateScene(String hint) async {
    if (!_h.directing() || _turn.isTurnBusy) return false;
    final token = _session.currentSessionId;
    // The beat closes the undo window the way a note does.
    await _door.roster.commitPendingMemberExit();
    _guests.clearExitUndo();
    if (_door.sceneChanged(token) || !_h.directing() || _turn.isTurnBusy) {
      return false;
    }
    _door.narrating = true;
    var landed = '';
    try {
      _guests.setStatus('The narrator sets the scene…', sticky: true);
      final recent = _session.messages.length > kNarrationHistoryLines
          ? _session.messages.sublist(
              _session.messages.length - kNarrationHistoryLines,
            )
          : _session.messages;
      final engine = _d.evalEngine();
      final raw = await engine.fireLLMEval(
        narrationPrompt(
          recentLines: [
            for (final m in recent)
              if (!m.isStatusBanner && m.sender != 'System')
                m.toPromptHistoryLine(),
          ],
          castNames: [for (final c in _session.groupCharacters) c.name],
          hint: hint,
        ),
        label: 'narration',
      );
      if (_door.sceneChanged(token)) {
        _guests.setStatus(null);
        return true;
      }
      final beat = raw == null
          ? ''
          : cleanNarration(engine.stripThinkBlocks(raw));
      if (beat.isEmpty || !_h.directing()) {
        _guests.setStatus(
          '⚠ The narrator had nothing to add. Try again.',
          isError: true,
        );
        return true;
      }
      _guests.setStatus(null);
      _session.messages.add(narrationMessage(beat));
      await _d.saveChat();
      landed = beat;
    } catch (e) {
      debugPrint('[Director] narration failed: $e');
      _guests.setStatus(
        '⚠ The narrator could not set the scene.',
        isError: true,
      );
      return true;
    } finally {
      _door.narrating = false;
      _d.notify();
    }
    // No await since the flag dropped: the reply raises the generating
    // flag first.
    if (landed.isNotEmpty && !_door.sceneChanged(token)) {
      await _skipNarratedTime(landed, token);
      await _turn.generate(GenerationMode.normal);
    }
    return true;
  }

  /// A beat that skips time moves the clock the way a user's skip line
  /// does: same turn ownership and regen replay, same settle for a day or
  /// more. No bridge card: the beat already narrated the gap.
  Future<void> _skipNarratedTime(String beat, String? token) async {
    final scope = _d.realism();
    if (!scope.clockRunning()) return;
    final before = scope.time().clock;
    final skipped = await _d.graph().playerSkip().apply(
      beat,
      stale: () => _door.sceneChanged(token),
    );
    await _d.graph().episodeCrumbs.maybeMint(before, scope.time().clock);
    if (skipped >= kLongSkipMinutes) LongSkipSettle(scope).settle();
  }

  /// A skip of a day or more ([skipped] minutes from [from]): the narrator
  /// fills in the gap as a card, then the reply follows it. A failed or
  /// empty bridge is logged and the turn goes on without one. False only
  /// when the chat changed under the call, so the send stops.
  Future<bool> bridgeLongSkip({
    required DateTime from,
    required int skipped,
    required ChatMessage skipLine,
    required String? token,
  }) async {
    if (!_d.storage.realismSettings.timeSkipBridgeEnabled) return true;
    _guests.setStatus('The narrator fills in the time skip…', sticky: true);
    try {
      final engine = _d.evalEngine();
      final time = _d.realism().time();
      final scene = [
        for (final m in _session.messages)
          if (!identical(m, skipLine)) m,
      ];
      final recent = scene.length > kNarrationHistoryLines
          ? scene.sublist(scene.length - kNarrationHistoryLines)
          : scene;
      final raw = await engine.fireLLMEval(
        timeSkipBridgePrompt(
          recentLines: [
            for (final m in recent)
              if (!m.isStatusBanner && m.sender != 'System')
                m.toPromptHistoryLine(),
          ],
          castNames: _session.activeGroup != null
              ? [for (final c in _session.groupCharacters) c.name]
              : [?_session.activeCharacter?.name],
          userName: _d.personas.persona.name,
          skipLine: skipLine.text,
          from: '${skipMomentWords(from)} (${StoryClock.formatClock(from)})',
          to:
              '${skipMomentWords(time.clock)} '
              '(${time.displayClock})',
          minutes: skipped,
          context: _d.prompts().blocks.timeSkipBridgeContext(),
        ),
        label: 'time_skip_bridge',
      );
      if (_door.sceneChanged(token)) return false;
      final beat = raw == null
          ? ''
          : cleanNarration(engine.stripThinkBlocks(raw));
      if (beat.isEmpty) {
        debugPrint('[TimeSkip] bridge came back empty; replying without it');
        return true;
      }
      // The clock is the truth: a bridge claiming more time than it moved
      // would be one more disagreement for the reply to reconcile.
      if (bridgeOverstatesSpan(beat, skipped)) {
        debugPrint(
          '[TimeSkip] bridge names a longer span than '
          '${skipSpanWords(skipped)}; replying without it',
        );
        return true;
      }
      // Stored before the skip line, so the line that skipped stays the
      // user's turn for every pass that looks for it. The prompt reads it
      // after that line (bridgesAfterSkipLines).
      final at = _session.messages.indexOf(skipLine);
      _session.messages.insert(
        at < 0 ? _session.messages.length : at,
        timeSkipBridgeMessage(beat),
      );
      await _d.saveChat();
      return true;
    } catch (e) {
      debugPrint('[TimeSkip] bridge failed, replying without it: $e');
      return !_door.sceneChanged(token);
    } finally {
      if (!_door.sceneChanged(token)) _guests.setStatus(null);
      _d.notify();
    }
  }

  /// A goodbye or greeting stopped before it said a word (or only thought)
  /// is not a turn: it goes, rather than staying as an empty "only
  /// thoughts" bubble. [before] is the transcript length before it.
  Future<void> dropSilentStagedTurn(int before) async {
    final last = _session.messages.lastOrNull;
    if (_session.messages.length <= before || last == null || last.isUser) {
      return;
    }
    if (last.displayText.trim().isNotEmpty) return;
    await _turn.waitForTurnToSettle();
    final idx = _session.messages.indexOf(last);
    if (idx >= 0) await _h.deleteMessage(idx); // + reverts realism, saves
  }
}
