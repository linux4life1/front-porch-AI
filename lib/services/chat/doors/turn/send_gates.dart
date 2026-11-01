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

import 'package:front_porch_ai/services/chat/chat.dart';
import 'package:front_porch_ai/services/chat/doors/cast/cast_door.dart';
import 'package:front_porch_ai/services/chat/doors/session/session_store.dart';
import 'package:front_porch_ai/services/llm_provider.dart';

import 'send_spine.dart';

/// Whether a send may go now, in one predicate, and the "Did time pass?"
/// gate a send parks on.
///
/// [busyReason] is the guard [SendSpine.sendMessage] refuses on and the
/// guard the desktop composer and the web relay read before they let go of
/// the text, so the two can never drift apart.
class SendGates {
  SendGates(this._s);

  final SendSpine _s;

  /// The "Did time pass?" question, and whether a web client is there to
  /// answer one (see [pendingSkip]).
  final SkipConfirmGate _skipGate = SkipConfirmGate();
  bool Function() _skipWebAsker = () => false;

  ChatSessionState get _session => _s.session;
  LLMProvider? get _llmProvider => _s.deps.services.llmProvider();
  SessionStore get _sessions => _s.sessions;
  CastDoor get _cast => _s.cast;
  bool get _isLoadingSession => _sessions.isLoadingSession;
  int get _chatSwitches => _sessions.chatSwitches;
  bool get isImporting => _s.deps.doors.importer().isImporting;
  bool get _entrancesInFlight => _s.entry.entrancesInFlight;
  SceneGuestState get _sceneGuest => _cast.guests.state;
  bool get isPhotoTurnInFlight => _s.media.photoTurnInFlight;
  bool get _isGenerating => _s.engine.progress.isGenerating;
  bool get _narrating => _cast.narrating;
  bool get _callMode => _s.controls.callMode;
  bool _sceneChanged(String? token) => _cast.sceneChanged(token);

  /// Why a message cannot be sent now, in words: while the speed test has the
  /// app's KoboldCpp, with about how long is left, instead of the message
  /// waiting minutes behind it. Null when it can go, and for a slash command
  /// the app answers itself, which needs no model. The composer asks this
  /// before it lets go of the text.
  String? sendRefusal(String text, {bool withImage = false}) {
    final llm = _llmProvider;
    if (llm == null || !llm.hasManagedProcess) return null;
    final words = llm.koboldSpeedTest?.chatRefusal;
    if (words == null) return null;
    final lookup = parseLookupForce(text);
    final outbound = lookup.accepted ? lookup.userText : text;
    final command =
        !lookup.accepted &&
        !withImage &&
        outbound.trim().startsWith('/') &&
        _s.deps.services.characters() != null;
    return command ? null : words;
  }

  /// Why [SendSpine.sendMessage] would drop a message right now, or null
  /// when it would go: its early returns, in words. The desktop composer
  /// and the web relay both ask this before they let go of the text, so a
  /// line typed while a reply or the narrator is running stays in the box
  /// (or comes back to the phone) instead of being cleared and silently
  /// ignored. The send refuses on this same predicate.
  String? get busyReason {
    if (_session.activeCharacter == null && _session.activeGroup == null) {
      return 'No chat is open.';
    }
    // Overlay / picker hydrate is still in flight. A send here would
    // persist the pre-hydrate realism reset onto whichever session is
    // currently live (often the last-active chat, not the one opening).
    if (_isLoadingSession || _chatSwitches > 0) {
      return 'The chat is still opening.';
    }
    // Import clears `_session.messages` and remints the session. A Send
    // during that window appends into a list the import is about to throw
    // away.
    if (isImporting) return 'A chat import is still running.';
    // Don't let a user turn start while forked-in entrances are still
    // playing — it would race the one-shot entrance directive / turn
    // positioning. Likewise, don't race an in-flight Scene Guest
    // creation/entrance (the mint runs a separate LLM call that doesn't set
    // _isGenerating).
    if (_entrancesInFlight || _sceneGuest.busy) {
      return 'A character is still joining the scene.';
    }
    // A photo turn's captioning windows run while _isGenerating is false;
    // this guard stops a second send from interleaving them (see
    // isPhotoTurnInFlight).
    if (isPhotoTurnInFlight) return 'The last photo is still being read.';
    // No new user turn while a generation is live (streaming, draining, or
    // finalizing). A send mid-turn interleaves this method's own message
    // inserts (dream block) with the active turn's writes on one shared
    // list — the 2026-07-28 dream-corruption report. Stop first: the Stop
    // button now halts a turn promptly (see the drain cancel fix).
    //
    // Deliberately _isGenerating, NOT _isTurnBusy. Extending this to the
    // post-generation window was tried twice and CI rejected it both times:
    // post-gen evals plus background objective checks meant the composer was
    // unavailable for most of a turn, and on a slow local backend a user
    // would meet a dead send button far more often than a live one.
    // Sending APPENDS a message; it does not shift indices or rewrite state
    // under a running eval the way delete/regenerate/swipe/cast do — those
    // keep the wider _isTurnBusy guard, because that is where the race
    // actually corrupts something.
    if (_isGenerating) return 'A reply is still being written.';
    // The narrator's beat is about to append and start the reply.
    if (_narrating) return 'The narrator is still setting the scene.';
    // A send parked on "Did time pass?" owns the turn (another screen).
    if (skipAsked) return kSkipAskPending;
    return null;
  }

  /// The "Did time pass?" question the send is waiting on, or null. The
  /// desktop dialog and the web sheet show it while it is non-null.
  PendingSkip? get pendingSkip => _skipGate.pending;

  /// A send is parked on [pendingSkip]: it owns the turn, so no other send,
  /// regen, swipe, Continue or delete starts until it is answered.
  bool get skipAsked => _skipGate.pending != null;

  /// The player's answer to [pendingSkip]: a skip, [SkipVerdict.none] for
  /// "no skip", or null to keep the reader's guess.
  void answerSkip(SkipVerdict? verdict) {
    if (_skipGate.answer(verdict)) _s.notify();
  }

  /// Whether a web client is connected to answer [pendingSkip].
  set skipConfirmWebAsker(bool Function() connected) =>
      _skipWebAsker = connected;

  /// Puts a shaky skip reading to whoever is at a chat screen. Null at once
  /// in a voice call or with nobody there (pick E: Director auto-chat and
  /// AFK never send through here anyway), so the guess applies. A chat
  /// change under the question cancels it.
  Future<SkipVerdict?> askSkip(PendingSkip question, String? token) async {
    if (_callMode || (!_s.deps.hooks.chatScreenOpen() && !_skipWebAsker())) {
      return null;
    }
    final answer = _skipGate.ask(question);
    _s.notify();
    void onChange() {
      if (_sceneChanged(token) && _skipGate.cancel()) _s.notify();
    }

    _s.deps.service.addListener(onChange);
    try {
      return await answer;
    } finally {
      _s.deps.service.removeListener(onChange);
    }
  }
}
