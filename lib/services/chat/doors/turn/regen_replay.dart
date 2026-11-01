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

import 'package:flutter/foundation.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/chat/chat.dart';
import 'package:front_porch_ai/services/chat/doors/realism/realism_graph.dart';
import 'package:front_porch_ai/services/chat/doors/session/session_store.dart';
import 'package:front_porch_ai/services/chat/doors/turn/turn_engine.dart';
import 'package:front_porch_ai/services/chat/group_speaker_resolution.dart'
    as speakers;

/// The regen pieces of a turn: which cast member said a message, and 1:1
/// regen's decay and judge replay (trust_repair_regen_latch_test reads the
/// shared dispatch here). The regen itself is the edits door's
/// RegenController; groups replay inside the generation via the
/// per-speaker dance.
class RegenReplay {
  RegenReplay(this._e);

  final TurnEngine _e;

  TurnDeps get _d => _e.deps;
  ChatSessionState get _session => _d.session;
  RealismGraph get _g => _d.doors.graph();
  SessionStore get _sessions => _d.doors.sessions();

  AfterglowPass get _afterglow => _g.afterglow;
  void _applyMoodDecay() => _g.restores.applyMoodDecay();
  StoryClockReader get _clockReader => _g.clockReader;
  Timer? get _evalChunkTimer => _g.evalStatus.chunkTimer;
  set _evalChunkTimer(Timer? t) => _g.evalStatus.chunkTimer = t;
  List<CharacterCard> get _groupCharacters => _session.groupCharacters;
  set _isEvaluatingRealism(bool v) => _g.evalStatus.evaluating = v;
  NeedsPass get _needsPass => _g.needsPass;
  NeedsSimulation get _needsSimulation => _g.needs;
  Map<String, dynamic>? get _pendingRealismMetadata => _g.registers.pending;
  set _pendingRealismMetadata(Map<String, dynamic>? v) =>
      _g.registers.pending = v;
  PocketsRewinds get _pocketsRewinds => _g.pocketsRewinds;
  bool get _realismEvalCancelled => _g.evalStatus.cancelled;
  set _realismEvalCancelled(bool v) => _g.evalStatus.cancelled = v;
  String get _realismEvalStreamText => _g.evalStatus.streamText;
  set _realismEvalStreamText(String v) => _g.evalStatus.streamText = v;
  RealismJudges get _realismJudges => _g.judges;
  void _restoreRealismStateForSpeaker(
    ChatMessage msg, {
    bool restoreClock = false,
  }) => _g.restores.forSpeaker(msg, restoreClock: restoreClock);
  Future<void> _saveChat({bool replaceAll = false}) =>
      _sessions.save(replaceAll: replaceAll);

  /// Which cast member said [msg]. See [resolveGroupSpeakerForMessage].
  CharacterCard? resolveGroupSpeakerForMessage(ChatMessage msg) =>
      speakers.resolveGroupSpeakerForMessage(_groupCharacters, msg);

  /// 1:1 regen: replay decay + the realism eval for the popped reply's user
  /// line, from the baseline the revert restored. Groups replay inside the
  /// generation via the per-speaker dance. False when the user cancelled:
  /// the popped reply is then back, with the state it was accepted under.
  Future<bool> replayRegenJudges(ChatMessage lastMsg) async {
    // Set UI streaming state
    _isEvaluatingRealism = true;
    _realismEvalStreamText = '';
    _d.notify();

    void handleChunk(String chunk) {
      _realismEvalStreamText += chunk;
      // Debounce: coalesce rapid token arrivals into one rebuild per 150 ms
      _evalChunkTimer?.cancel();
      _evalChunkTimer = Timer(const Duration(milliseconds: 150), () {
        try {
          _d.notify();
        } catch (_) {
          // Widget was deactivated — timer fired after navigation
        }
      });
    }

    // Record the (restored) needs baseline as the pre-turn vector BEFORE
    // the decay tick below — sendMessage stamps pre-tick and the group
    // dance stamps preDecay, so a regen's chips must count the decay the
    // same way or they understate the turn by exactly the decay component
    // (and deleting the regenerated reply under-refunds by it — caught by
    // regen_chip_attach_test: the original showed a hygiene chip, the
    // regen didn't).
    if (_needsPass.active && _needsSimulation.vector.isNotEmpty) {
      _pendingRealismMetadata ??= {};
      _pendingRealismMetadata!['needs_pre_turn_vector'] = Map<String, int>.from(
        _needsSimulation.vector,
      );
      _pendingRealismMetadata![kNeedsPreTurnCarry] = Map<String, double>.from(
        _needsSimulation.wearCarry,
      );
    }

    // Wear waits until the clock commits on the replayed reply.
    _applyMoodDecay();
    _afterglow.tickPerReply();

    await _realismJudges.runPreGenJudges(
      onChunk: handleChunk,
      logSpeakerName: _session.activeCharacter?.name,
    );

    // Check for cancellation after evals complete
    if (_realismEvalCancelled) {
      debugPrint('[Realism] Evaluation cancelled during regenerate, aborting');
      // Put the popped reply back BEFORE bailing. The regen removed it at
      // the top so the outbound prompt wouldn't contain it, and
      // generate — the thing that appends the replacement — is
      // still below us. Returning without this destroys the message and
      // every swipe it carried. It is the same hazard the backend gate
      // further up already guards ("aborting after removeLast would drop
      // the popped reply"); the cancel path just never learned it.
      //
      // Putting the TEXT back is only half of it. Everything above already
      // un-applied the accepted turn — bond/trust/arousal reverted, needs
      // restored from needs_pre_turn_vector, the baseline pulled from the
      // PREVIOUS accepted message, the stance rewound, pockets rolled to
      // the pre-turn record — and then charged a fresh decay tick. Bailing
      // here without the same restore the two success paths run (see
      // `if (regenGuest == null) _restoreRealismStateForSpeaker(lastMsg)`
      // below) left the message displaying chips the sidebar and the
      // session row no longer agreed with, and `_saveChat()` persisted the
      // wrong scalars. 1:1-only branch, host-only (guests never get here).
      _session.messages.add(lastMsg);
      _clockReader.applyTipClock();
      _restoreRealismStateForSpeaker(lastMsg);
      _pocketsRewinds.restoreFromStamp(lastMsg, after: true);
      _pendingRealismMetadata = null;
      _realismEvalCancelled = false;
      _evalChunkTimer?.cancel();
      _evalChunkTimer = null;
      _isEvaluatingRealism = false;
      _d.notify();
      await _saveChat();
      return false;
    }

    // Cancel any pending debounce notify before closing the overlay
    _evalChunkTimer?.cancel();
    _evalChunkTimer = null;
    _isEvaluatingRealism = false;
    _d.notify();
    return true;
  }
}
