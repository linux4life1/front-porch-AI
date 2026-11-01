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
import 'package:front_porch_ai/services/chat/doors/cast/cast_door.dart';
import 'package:front_porch_ai/services/chat/doors/controls/controls_door.dart';
import 'package:front_porch_ai/services/chat/doors/entry/entry_door.dart';
import 'package:front_porch_ai/services/chat/doors/media/media_door.dart';
import 'package:front_porch_ai/services/chat/doors/objectives/objectives_door.dart';
import 'package:front_porch_ai/services/chat/doors/realism/realism_graph.dart';
import 'package:front_porch_ai/services/chat/doors/session/session_store.dart';
import 'package:front_porch_ai/services/chat/doors/turn/prompt_assembler.dart';
import 'package:front_porch_ai/services/chat/doors/turn/turn_engine.dart';
import 'package:front_porch_ai/services/storage_service.dart';

import 'chance_reveal.dart';
import 'group_speakers.dart';
import 'idle_stage.dart';
import 'send_deps.dart';
import 'send_gates.dart';
import 'send_handoff.dart';
import 'send_turn.dart';
import 'try_again.dart';

export 'chance_reveal.dart';
export 'group_speakers.dart';
export 'idle_stage.dart';
export 'send_deps.dart';
export 'send_gates.dart';
export 'send_handoff.dart';
export 'send_turn.dart';
export 'try_again.dart';

/// File scope, as it always was: true while [SendSpine.sendMessage] is
/// holding a typed line behind post-gen evals. The composer already
/// cleared; the bubble is not in the list yet.
bool _sendWaitingOnSettle = false;

/// The user's turn, from the composer to the reply: [sendMessage]'s guards
/// (one predicate, [SendGates.busyReason], which the composer and the web
/// relay read too), the queue behind a settling turn, the start-of-turn
/// clears and the slash command; then [SendTurn] (persist, dreams, the
/// Chaos wheel, the call-model swap, the player's time skip, the goal
/// check) and [SendHandoff] (the pre-reply score and the hand-off to the
/// turn engine). Around it: Try again on a trailing user line
/// ([TryAgain]), the group speaker pick ([GroupSpeakers]), the Chance Time
/// reveal and the Journal recap controls ([ChanceReveal], [RecapControls])
/// and the idle turn's staging ([IdleStage]).
///
/// TTS-paced auto-play, background RAG embedding and the periodic cast
/// scan run after a reply, on the turn engine ([PostGenSide],
/// [TurnEntry]).
///
/// Every body is the code the send parts held, moved verbatim. Continue
/// never enters here: it does not tick the clock or score a user line.
///
/// Not a notifier: every transition calls the service's own notify
/// ([SendDeps.notify]) at the moment the parts it replaces did.
class SendSpine {
  SendSpine(this.deps);

  final SendDeps deps;

  late final SendGates gates = SendGates(this);
  late final SendTurn sendTurn = SendTurn(this);
  late final SendHandoff handoff = SendHandoff(this);
  late final TryAgain tryAgain = TryAgain(this);
  late final GroupSpeakers speakers = GroupSpeakers(this);
  late final ChanceReveal chanceReveal = ChanceReveal(this);
  late final RecapControls recap = RecapControls(this);
  late final IdleStage idle = IdleStage(this);

  /// Serializes [sendMessage] so two composer taps during settle cannot
  /// both pass `isGenerating` and then both run after the wait.
  Future<void> _sendChain = Future.value();

  /// Typed send is queued behind post-gen evals. Composer is empty; no bubble
  /// yet. UI shows a holding banner so the wait does not look like a lost send.
  bool get isSendWaitingOnSettle => _sendWaitingOnSettle;

  ChatSessionState get session => deps.session;
  StorageService get storage => deps.services.storage;
  TurnEngine get engine => deps.doors.engine();
  PromptAssembler get prompts => deps.doors.prompts();
  RealismGraph get graph => deps.doors.graph();
  ControlsDoor get controls => deps.doors.controls();
  SessionStore get sessions => deps.doors.sessions();
  CastDoor get cast => deps.doors.cast();
  EntryDoor get entry => deps.doors.entry();
  ObjectivesDoor get objectives => deps.doors.objectives();
  MediaDoor get media => deps.doors.media();
  void notify() => deps.notify();
  String characterIdFor(CharacterCard card) => deps.hooks.characterIdFor(card);
  Future<void> saveChat({bool replaceAll = false}) =>
      sessions.save(replaceAll: replaceAll);

  /// The voice call's fast model, parked before the pre-generation work
  /// ([CallModelSwap.enter]); the request phase adopts it into the turn.
  void enterCallModelSwap() => prompts.callSwap.enter();

  /// Puts the main model back when a swapped turn never reaches the request
  /// phase, or the call ends with a swap parked ([CallModelSwap.exit]).
  void exitCallModelSwap() => prompts.callSwap.exit();

  MediaDoor get mediaDoor => media;
  bool get _isGenerating => engine.progress.isGenerating;
  set _realismEvalCancelled(bool v) => graph.evalStatus.cancelled = v;
  bool get _absenceAckPending => sessions.absenceAckPending;
  set _absenceAckPending(bool v) => sessions.absenceAckPending = v;
  bool get _absenceAckConsumed => sessions.absenceAckConsumed;
  set _absenceAckConsumed(bool v) => sessions.absenceAckConsumed = v;
  set _pendingIdleCue(String? v) => cast.idle.pendingIdleCue = v;
  TimeService get _timeService => graph.time;
  bool get _clockRunning => controls.clockRunning;
  ToolTransportProbe get _toolProbe => graph.transport.probe;
  String get _evalBackendIdentity => graph.transport.backendIdentity;
  UserTurnHold get _userTurn => controls.userTurn;
  Future<void> _waitForTurnToSettle() => entry.cover.waitForTurnToSettle();
  void _setGuestStatus(
    String? msg, {
    bool isError = false,
    bool sticky = false,
  }) => cast.guests.setStatus(msg, isError: isError, sticky: sticky);
  Future<void> setStoryClock(DateTime clock) =>
      controls.clock.setStoryClock(clock);

  /// Seed every speaker's card kit unless the chat already has one (the
  /// realism bridge's `seedPocketsFromCards`, behind the same switch).
  void seedPocketsFromCards() {
    if (!storage.realismSettings.pocketsEnabled) return;
    graph.pocketsLedger.seedPocketsFromCards();
  }

  /// [imageBytes] optionally attaches a photo (already downscaled+PNG-encoded
  /// by the composer) to this user turn. The bytes are saved to disk HERE,
  /// after all guards pass, so a guard bail can never orphan a file. The photo
  /// renders inline in the bubble, rides along as pixels on this turn's
  /// generation when the model can see (see [buildTurnImages]), and is
  /// described in the flattened history for later turns.
  Future<void> sendMessage(String text, {Uint8List? imageBytes}) async {
    if (text.trim().isEmpty && imageBytes == null) return;
    // The composer's guard and this one are the same predicate: the desktop
    // composer and the web relay read [SendGates.busyReason] before they
    // let go of the text, and the send refuses on exactly those reads (each
    // reason is explained there). Only "Did time pass?" says so here: a
    // send parked on it owns the turn (another screen).
    final busy = gates.busyReason;
    if (busy != null) {
      if (busy == kSkipAskPending) {
        _setGuestStatus(kSkipAskPending, isError: true);
      }
      return;
    }
    final testing = gates.sendRefusal(text, withImage: imageBytes != null);
    if (testing != null) {
      _setGuestStatus(testing, isError: true);
      return;
    }
    // `/skip 8h` at the end is the exact skip; the line goes without it.
    final skipTag = SkipTag.parse(text);
    if (skipTag.error != null) {
      _setGuestStatus(skipTag.error, isError: true);
      return;
    }
    final lookup = parseLookupForce(skipTag.body);
    if (lookup.attempted) {
      final block =
          lookup.error ??
          lookupForceUnavailable(
            webQuery: lookup.webQuery,
            wikiQuery: lookup.wikiQuery,
            webEnabled: storage.webSearchSettings.webSearchDefault,
            hasWiki: mediaDoor.wikiLookupAvailable,
          );
      if (block != null) {
        mediaDoor.announceLookupForce(block);
        return;
      }
    }
    final outbound = lookup.accepted ? lookup.userText : skipTag.body;
    final trimmed = outbound.trim();
    final command =
        !lookup.accepted &&
        imageBytes == null &&
        trimmed.startsWith('/') &&
        deps.services.characters() != null;
    if (command && skipTag.present) {
      _setGuestStatus(kSkipAfterCommand, isError: true);
      return;
    }
    final previousSend = _sendChain;
    final sendGate = Completer<void>();
    _sendChain = sendGate.future;
    try {
      await previousSend;
    } catch (_) {}
    if (_isGenerating) {
      sendGate.complete();
      return;
    }
    // A send that lands in the previous turn's SETTLING window must QUEUE
    // behind it, not race it: the new turn's pre-gen work (mood decay, needs
    // tick, the group per-speaker scalar re-point) otherwise runs before the
    // old turn's RealismDance.saveScalarsIntoGroup / snapshot restamp / chip
    // attach, cross-writing speaker A's realism state with speaker B's.
    // Bounded (15s deadline) and drains the save chain — the same
    // serialization point setActiveCharacter/setActiveGroup/loadSession
    // already use. The composer deliberately stays LIVE during settling
    // (greying it was rejected twice); this waits instead of refusing.
    // Also closes the _isPostGenerating latch: a turn started mid-settle
    // captured callerHeldSettling=true and wedged _isTurnBusy for the
    // session.
    try {
      if (engine.progress.isPostGenerating) {
        _sendWaitingOnSettle = true;
        notify();
      }
      await _waitForTurnToSettle();
    } finally {
      if (_sendWaitingOnSettle) {
        _sendWaitingOnSettle = false;
        notify();
      }
      if (!sendGate.isCompleted) sendGate.complete();
    }
    if (_isGenerating) return;
    // [EvalTraffic]: whatever the fire-and-forget passes (journal, growth,
    // promises, cast…) spent since the last turn's print, reported now so
    // the turn's own line stays a clean measure of the turn.
    final backgroundTraffic = EvalTraffic.current.flushBackground();
    if (backgroundTraffic != null) debugPrint(backgroundTraffic);
    // One-shot absence acknowledgment: pending survives exactly the first
    // user turn after load (all of that turn's prompt builds see it); the
    // second turn clears it for good.
    if (_absenceAckPending) {
      if (_absenceAckConsumed) {
        _absenceAckPending = false;
      } else {
        _absenceAckConsumed = true;
      }
    }
    // Start-of-turn clear: cancelRealismEval only sets this while an eval is
    // live, and each turn's consumers clear it — but this guarantees a stray
    // set flag can never bleed into THIS turn and abort a reply the user did
    // not cancel.
    _realismEvalCancelled = false;
    deps.doors.actions().clearSuggestions();
    // Before ANY prompt is built for this turn. Counting the greeting as
    // turn 0, this is what puts an authored wardrobe into turn 1's prompt —
    // the pass that used to do it runs after the reply exists, so the first
    // real answer was generated blind to what they were wearing.
    seedPocketsFromCards();
    // Hand-added item reactions the previous reply already played out are
    // done; ones still pending (never made it into a prompt) stay queued for
    // THIS turn. Cleared here, not at prompt build, so a regenerate of the
    // reacting reply reproduces the reaction.
    graph.pocketsLedger.dropConsumedItemIntros();

    // A new message while an /image prompt review is parked cancels it —
    // the desktop dialog is modal, but the web modal can be typed around.
    mediaDoor.resolveImagePromptReview(null);

    // User is interacting — clear any pending auto-response state
    _pendingIdleCue = null;

    // A message that is only `/skip …` moves the clock and sends nothing,
    // like the calendar does.
    if (skipTag.present && trimmed.isEmpty && imageBytes == null) {
      final to = skipTag.verdict!.landing(_timeService.clock);
      if (!_clockRunning || to == null) {
        _setGuestStatus(kSkipNeedsClock, isError: true);
        return;
      }
      await setStoryClock(to);
      _setGuestStatus('Skipped ahead to ${_timeService.displayClock}.');
      return;
    }

    // ── Slash Command Handling (delegated to leaf) ──────────────────────
    // Skipped when a photo is attached: an attach makes the intent "send a
    // message" unambiguous, and consuming the text as a command would drop
    // the attachment silently.
    if (command) {
      final handled = await engine.entry.commandHandler().handle(trimmed);
      if (handled) return;
      // Unknown command — fall through and send as a normal message.
    }

    _toolProbe.beginUserSend();
    mediaDoor.beginUserSend();
    try {
      _userTurn.open(); // Porch Life's Realism waits for the whole turn.
      await sendTurn.run(
        outbound: outbound,
        imageBytes: imageBytes,
        skipTag: skipTag,
        lookup: lookup,
      );
    } finally {
      _toolProbe.endUserSend(_evalBackendIdentity);
      _userTurn.close();
    }
  }
}
