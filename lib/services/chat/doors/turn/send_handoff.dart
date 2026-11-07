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
import 'package:front_porch_ai/services/chat/doors/media/media_door.dart';
import 'package:front_porch_ai/services/chat/doors/realism/realism_graph.dart';
import 'package:front_porch_ai/services/chat/doors/turn/turn_engine.dart';
import 'package:front_porch_ai/services/storage_service.dart';

import 'send_spine.dart';

/// The hand-off from a user line to the turn engine: the pre-reply score
/// (needs baseline, decay, the 1:1 host eval), the engine's reply, the idle
/// timer, the Scene Guest chime-ins and the vision caption. Also the
/// per-turn baselines a later rewind reads: [stampUserTurnBaseline] (1:1)
/// and [stampGroupUserTurnBaseline] (group, per speaker).
///
/// preTurnVector is captured before the reply. Wear happens after the
/// clock. Continue does not wear.
class SendHandoff {
  SendHandoff(this._s);

  final SendSpine _s;

  ChatSessionState get _session => _s.session;
  StorageService get _storageService => _s.storage;
  RealismGraph get realism => _s.graph;
  TurnEngine get turnEngine => _s.engine;
  MediaDoor get mediaDoor => _s.media;
  CastDoor get _cast => _s.cast;
  GroupChat? get _activeGroup => _session.activeGroup;
  SceneGuestState get _sceneGuest => _cast.guests.state;
  bool get _realismEvalCancelled => realism.evalStatus.cancelled;
  set _realismEvalCancelled(bool v) => realism.evalStatus.cancelled = v;
  NeedsSimulation get _needsSimulation => realism.needs;
  NeedsPass get _needsPass => realism.needsPass;
  RealismSnapshot get _realismSnapshot => realism.snapshot;
  RealismDance get _realismDance => realism.dance;
  TimeService get _timeService => realism.time;
  bool get _realismActiveThisMode => realism.realismActiveThisMode;
  bool get _clockRunning => _s.controls.clockRunning;
  bool get _isTurnBusy => turnEngine.isTurnBusy;
  bool get _entrancesInFlight => _s.entry.entrancesInFlight;
  set _hasCompletedExchange(bool v) => _cast.idle.hasCompletedExchange = v;
  void _resetIdleTimer() => _cast.idle.resetIdleTimer();
  void _applyMoodDecay() => realism.restores.applyMoodDecay();
  void _exitCallEvalModelSwap() => _s.exitCallModelSwap();
  Future<void> _saveChat() => _s.saveChat();
  void notifyListeners() => _s.notify();
  bool _sceneChanged(String? token) => _cast.sceneChanged(token);
  Future<void> generateGuestTurn(CharacterCard guest) =>
      _cast.guests.generateGuestTurn(guest);
  Future<void> _runAwayPulse({
    required String userText,
    required bool fromUserSend,
  }) => _cast.away.runAwayPulse(userText: userText, fromUserSend: fromUserSend);

  /// Pre-turn needs capture, generate, chips baseline, guest chime-ins,
  /// and vision caption. Called from [SendTurn.run] after
  /// chaos/call-model/task-completion. Capture stays first so
  /// [preTurnVector] is the body before this beat's wear.
  Future<void> sendDecayAndGenerate({
    required CharacterCard? addressedGuest,
    required ChatMessage userMsg,
    required String? imagePath,
    required String? sessionToken,
    String? forcedWebQuery,
    String? forcedWikiQuery,
  }) async {
    await scoreUserTurnBeforeReply(
      userMsg: userMsg,
      addressedGuest: addressedGuest,
    );

    // If cancellation was requested during realism evaluation, abort generation
    if (_realismEvalCancelled) {
      // The turn dies before the request phase can adopt the call-model
      // swap — put the main model back ourselves. Lookup flags are not
      // armed yet; the generate call below is what consumes them.
      _exitCallEvalModelSwap();
      _needsSimulation.consumePendingCatastrophe();
      await _saveChat();
      _realismEvalCancelled = false;
      notifyListeners();
      return;
    }

    if (addressedGuest != null) {
      mediaDoor.armForcedLookup(
        webQuery: forcedWebQuery,
        wikiQuery: forcedWikiQuery,
      );
      await generateGuestTurn(addressedGuest);
    } else {
      if (_activeGroup != null) {
        await _runAwayPulse(
          userText: AtMentionText.routingText(userMsg),
          fromUserSend: true,
        );
      }
      // This is the sole web-search allow-list entry: a newly appended user
      // message receiving its first host/group response. Every follow-up,
      // guest, cast, regen, idle, and command generation keeps the default
      // false and therefore cannot advertise or reach search HTTP.
      // A named /search or /wiki is armed for this first reply only.
      mediaDoor.armForcedLookup(
        webQuery: forcedWebQuery,
        wikiQuery: forcedWikiQuery,
      );
      await turnEngine.generate(GenerationMode.normal, directUserSend: true);
    }
    // Backend-down abort: no response was generated, so none of the
    // post-turn work below may run — no idle-timer arming, no chip attach,
    // no guest chime-ins against the notice text (pre-move parity: the old
    // in-sendMessage guard returned before all of this).
    if (_session.messages.isNotEmpty &&
        _session.messages.last.text == kBackendDownNotice) {
      return;
    }
    // First exchange complete — arm idle timer
    _hasCompletedExchange = true;
    if (_storageService.generationSettings.dynamicResponses) {
      debugPrint(
        '[DynamicResponses] First exchange done, arming idle timer (interval=${_storageService.generationSettings.dynamicResponseInterval}s)',
      );
      _resetIdleTimer();
    }

    // Long-gen decay removed with buffers (decay via tick only now; model deltas via impact).
    // Compute needs_deltas AFTER generation so the post-generation checks
    // (climax, sexual activity, daily activities, fulfillment) are reflected.
    // This ensures UI chips show accurate deltas.
    // Per-message needs-delta chips are attached inside _generateResponse (via
    // NeedsPass.attachDeltaChipToLastMessage) so EVERY speaker gets them — group
    // auto-advance, /speak and chime-ins reach _generateResponse but never this
    // sendMessage scope, which is why only the first responder used to show
    // chips. preTurnVector is stamped in scoreUserTurnBeforeReply.

    // ── Scene Guests: auto chime-in ─────────────────────────────────────────
    // The primary 1:1 turn is now 100% finalized (response + chip/realism block
    // above). Let the director decide which guest(s) speak next. Shared with
    // regenerateMainCharacter() so the re-chime gate is identical after a regen.
    // promptText (not raw text) so a photo-only turn feeds the director a
    // "[shared a photo]" marker instead of an empty user message. A routed
    // direct-address speaker is excluded — they already answered this turn.
    // The typed line too, so a guest named by `@` still gets the name match.
    await maybeRunSceneGuestChimeIns(
      userText: userMsg.promptText,
      typedText: AtMentionText.routingText(userMsg),
      exclude: addressedGuest,
    );

    // ── Auto-caption the attached photo for future-turn history ─────────────
    // Vision path only (blind models were captioned pre-gen). Runs LAST so the
    // eval never delays the response or guest turns; this turn already saw the
    // pixels, so the caption just lets later turns' history describe the photo.
    if (imagePath != null) {
      await mediaDoor.runVisionPhotoCaption(userMsg, imagePath, sessionToken);
    }
  }

  /// Pre-reply scoring of a user turn: needs baseline, decay, and the 1:1
  /// host eval (groups score inside the dance). Shared by
  /// [SendSpine.sendMessage] and Generate reply on a trailing user message
  /// ([TryAgain]) so both score alike.
  Future<void> scoreUserTurnBeforeReply({
    required ChatMessage userMsg,
    CharacterCard? addressedGuest,
  }) async {
    if (addressedGuest == null && _activeGroup == null) {
      stampUserTurnBaseline(userMsg);
    }
    // Evaluate realism systems before generating response
    // Capture pre-turn needs vector (before decay + fulfillment) so that
    // regenerateLastMessage() and the post-generation delta computation
    // can use the same delta-revert mechanism the classic realism fields
    // (bond/trust/arousal) use.
    // The Needs pass stamps the body before this beat (and nothing, with
    // Needs off); regen and the chip read the stamp from the reply.
    if (addressedGuest == null && _activeGroup == null) {
      _needsPass.stampPreTurn();
    }
    if (_realismActiveThisMode && addressedGuest == null) {
      // 1:1 only. Group per-speaker stamp lives in the realism dance —
      // writing it here used the last loaded (full) member's vector, then
      // a soft turn skipped the dance and attached that leftover to the
      // guest bubble.

      // Short-term bond decay: 1:1 host only. In group mode the speaker isn't
      // picked yet — the old call here fell back to the FIRST member under
      // random turn order, so member #1 absorbed everyone's decay. The group
      // tick now lives per-speaker inside RealismDance.evaluateForUpcomingSpeaker,
      // on the pinned speaker's own cadence counter (mirrors needs + nsfw).
      if (_activeGroup == null) {
        _applyMoodDecay();
      }
      // Wear waits until the clock commits, after this reply. A send is
      // not a unit of time.
      // Clock off: the reply's refractory quarter hour, 1:1 host only. In a
      // group the speaker isn't picked yet (ticking here hit whichever
      // member was still loaded); theirs runs in
      // RealismDance.evaluateForUpcomingSpeaker once their scalars load. Clock on,
      // the beat's own minutes tick after the clock instead.
      if (_activeGroup == null) {
        realism.afterglow.tickPerReply();
      }

      // Single-path bridge: realism evaluation now runs inside _generateResponse
      // for EVERY speaker (1:1 host or group member) via
      // RealismDance.evaluateForUpcomingSpeaker.
      //
      // No cast-store mirror for the 1:1 host: its scalar fields are already the
      // canonical realism store (loaded by loadSession, decayed just above), and the
      // per-character _groupRealism map is group-only — its writes no-op when
      // _activeGroup == null. Mirroring was a no-op, and the eval path deliberately
      // does NOT reload the host from that empty map (doing so reset
      // bond/trust/emotion/needs to defaults). See RealismDance.evaluateForUpcomingSpeaker.
      if (_activeGroup == null && _session.activeCharacter != null) {
        // Run the SINGLE eval path for the host now — on a user turn only.
        // (Regen of a reply and Continue bypass this. Generate reply on a
        // trailing user message rewinds to the stamp first, then re-enters
        // here. Each caller checks cancellation before generating.)
        await _realismDance.evaluateForUpcomingSpeaker(
          _session.activeCharacter!,
        );
      }
    } else if (_clockRunning && addressedGuest == null) {
      // PoT is on and the engine did not run this turn. Stamp the user
      // turn's story day so RAG can ground retrieved lines. The post-reply
      // decide still lives in _finalizeGenerationTurn.
      if (_session.messages.isNotEmpty) {
        final last = _session.messages.last;
        if (last.isUser) {
          last.metadata = {
            ...?last.metadata,
            'story_day': _timeService.dayCount,
          };
        }
      }
      await _saveChat();
      notifyListeners();
    }
  }

  /// Run the Scene Guest director's chime-in gate after a finalized primary/host
  /// turn: it decides which present guest(s) (if any) speak next, each via the
  /// parity-safe [generateGuestTurn]. Shared by the normal send path and the
  /// "regenerate the main character beneath a guest reply" path so the re-chime
  /// decision (mention / relevance) is byte-for-byte identical in both.
  ///
  /// No-op in group chats, mid-generation, during entrances, or with no guests
  /// present. Each gate eval + guest turn is a slow LLM call, so it bails if the
  /// user switches chats / the scene changes (so guests never speak into the
  /// wrong conversation).
  Future<void> maybeRunSceneGuestChimeIns({
    required String userText,
    String? typedText,
    CharacterCard? exclude,
  }) async {
    if (_activeGroup != null ||
        _sceneGuest.cards.isEmpty ||
        _isTurnBusy ||
        _entrancesInFlight) {
      return;
    }
    final primaryResponse =
        _session.messages.isNotEmpty && !_session.messages.last.isUser
        ? _session.messages.last.displayText
        : '';
    final token = _session.currentSessionId;
    await turnEngine.entry.sceneGuestDirector().runChimeIns(
      userText: userText,
      typedText: typedText,
      primaryResponse: primaryResponse,
      isContextValid: () => !_sceneChanged(token) && _activeGroup == null,
      exclude: exclude,
    );
  }

  /// Record where 1:1 realism stood before [userMsg] was first scored. A
  /// later re-score (Generate reply after a rewind) keeps the first record.
  /// Mutated in place: a user bubble's swipeMetadata[0] aliases [metadata].
  void stampUserTurnBaseline(ChatMessage userMsg) {
    if (!userMsg.isUser) return;
    if (!_realismActiveThisMode && !_needsPass.active) return;
    final meta = userMsg.metadata ??= <String, dynamic>{};
    if (meta[kRealismPreTurn] is Map) return;
    meta[kRealismPreTurn] = _realismSnapshot.capture(
      preTurn: Map<String, int>.from(_needsSimulation.vector),
    );
  }

  /// Group twin of [stampUserTurnBaseline], per speaker. Runs inside the
  /// dance before decay, while [charId] is impersonated. Every member who
  /// scores the latest user line is stamped on it — an auto-advance or Next
  /// responder too, or deleting both replies would re-score that one twice.
  void stampGroupUserTurnBaseline(String charId) {
    final i = _session.messages.lastIndexWhere((m) => m.isUser);
    if (i < 0) return;
    final meta = _session.messages[i].metadata ??= <String, dynamic>{};
    final raw = meta[kRealismPreTurnBySpeaker];
    final bySpeaker = raw is Map
        ? Map<String, dynamic>.from(raw)
        : <String, dynamic>{};
    if (bySpeaker[charId] is Map) return;
    _realismDance.loadIntoScalars(charId);
    bySpeaker[charId] = _realismSnapshot.capture(
      preTurn: Map<String, int>.from(_needsSimulation.vector),
    );
    meta[kRealismPreTurnBySpeaker] = bySpeaker;
  }
}
