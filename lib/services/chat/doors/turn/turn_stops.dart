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
import 'package:front_porch_ai/services/chat/doors/realism/realism_graph.dart';
import 'package:front_porch_ai/services/chat/doors/session/session_store.dart';
import 'package:front_porch_ai/services/chat/doors/turn/prompt_assembler.dart';
import 'package:front_porch_ai/services/chat/doors/turn/turn_engine.dart';
import 'package:front_porch_ai/services/chat/llm_lanes.dart';
import 'package:front_porch_ai/services/llm_provider.dart';
import 'package:front_porch_ai/services/storage_service.dart';
import 'package:front_porch_ai/utils/utils.dart';

/// Turn stops and the delete rewinds: Continue's entry, the settling
/// yield, [stopGeneration], [cancelAndWaitForGeneration], delete's Pockets
/// rewind and Needs baseline, [cancelRealismEval], and the stopped turn's
/// halt the stream and the catch path share. Every stop discards an armed
/// Needs catastrophe before anything else
/// (catastrophe_clear_on_cancel_test reads this file).
class TurnStops {
  TurnStops(this._e);

  final TurnEngine _e;

  TurnDeps get _d => _e.deps;
  ChatSessionState get _session => _d.session;
  TurnProgress get _p => _e.progress;
  RealismGraph get _g => _d.doors.graph();
  SessionStore get _sessions => _d.doors.sessions();
  ControlsDoor get _controls => _d.doors.controls();
  CastDoor get _cast => _d.doors.cast();
  StorageService get _storageService => _d.services.storage;
  LLMProvider? get _llmProvider => _d.services.llmProvider();
  LlmLanes get _lanes => _d.services.lanes;
  String _getCharacterIdFromCard(CharacterCard card) => _d.characterIdFor(card);
  bool get _skipAsked => _d.doors.send().gates.skipAsked;
  bool get _isImporting => _d.doors.importer().isImporting;

  GroupChat? get _activeGroup => _session.activeGroup;
  List<CharacterCard> get _groupCharacters => _session.groupCharacters;
  GroupRealismStore get _groupStore => _g.groups;
  set _isCancellingRealismEval(bool v) => _g.evalStatus.cancelling = v;
  bool get _isEvaluatingRealism => _g.evalStatus.evaluating;
  set _isEvaluatingRealism(bool v) => _g.evalStatus.evaluating = v;
  bool get _isProcessingGreeting => _cast.baseline.isProcessingGreeting;
  set _isProcessingGreeting(bool v) => _cast.baseline.isProcessingGreeting = v;
  ItemCardJournal get _itemCards => _g.itemCards;
  bool get _needsSimEnabled => _controls.needsSimEnabled;
  NeedsSimulation get _needsSimulation => _g.needs;
  void _noteStoppedReply({required bool replyKept}) =>
      _cast.guests.noteStoppedReply(replyKept: replyKept);
  set _pendingRealismMetadata(Map<String, dynamic>? v) =>
      _g.registers.pending = v;
  PocketsLedger get _pocketsLedger => _g.pocketsLedger;
  PocketsRewinds get _pocketsRewinds => _g.pocketsRewinds;
  set _realismEvalCancelled(bool v) => _g.evalStatus.cancelled = v;
  set _realismEvalStreamText(String v) => _g.evalStatus.streamText = v;
  Future<void> _saveChat({bool replaceAll = false}) =>
      _sessions.save(replaceAll: replaceAll);
  SceneGuestState get _sceneGuest => _cast.guests.state;

  /// Abort in-flight post-gen evals so a mutation (regen/continue) can
  /// start. Streaming (`isGenerating`) and import still refuse — those
  /// are not "I already have the reply and I don't want it scored."
  void clearPostGenAbortFlags() {
    _p.postGenAbortRequested = false;
    _isCancellingRealismEval = false;
    _realismEvalCancelled = false;
  }

  Future<bool> yieldSettlingTurn() async {
    if (_p.isGenerating || _isImporting || _skipAsked) return false;
    if (!_p.isPostGenerating) {
      // Fast path used to return without touching the flags, so a leftover
      // latch from a prior yield survived into the next regen.
      clearPostGenAbortFlags();
      return true;
    }
    _p.postGenAbortRequested = true;
    _isCancellingRealismEval = true;
    _realismEvalCancelled = true;
    _lanes.abortAll();
    final deadline = DateTime.now().add(const Duration(seconds: 5));
    while (_p.isPostGenerating && DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 16));
    }
    // Timeout: post-gen is still running and must keep skipping applies.
    // Success: the next turn starts clean so regen can tick the clock.
    final done = !_p.isPostGenerating;
    if (done) clearPostGenAbortFlags();
    return done;
  }

  Future<void> continueGeneration() async {
    if (_session.messages.isEmpty || _sceneGuest.busy) return;
    // Continue KEEPS the reply. Aborting its scoring would leave the first
    // half unbookkept and only score the new fragment. Wait like Send.
    if (_p.isGenerating || _isImporting || _skipAsked) return;
    if (_p.isPostGenerating) await _e.waitForTurnToSettle();

    // Only continue if the last message is from a bot (non-user, non-system).
    // Narration banners (dreams, Chance Time) are excluded: continue_ streams
    // straight into _session.messages.last, which would append a chat reply to the
    // banner (the dream-corruption class, 2026-07-28).
    if (!_session.messages.last.isUser &&
        _session.messages.last.sender != 'System' &&
        _session.messages.last.activeMetadata?['is_dream'] != true &&
        _session.messages.last.activeMetadata?['is_chance_time_narration'] !=
            true) {
      await _e.generate(GenerationMode.continue_);
    }
  }

  void stopGeneration() {
    // Discard before plan consume so the next speaker cannot inherit a
    // Needs catastrophe armed for a turn that never ran. 1:1 evals happen
    // before `isGenerating`, so this is not gated on that flag.
    _needsSimulation.consumePendingCatastrophe();
    if (_p.isGenerating) {
      _p.cancelRequested = true;
      // A waiting reply leaves the line, and nothing of this turn is on the
      // wire to cut. Otherwise abort mouth speech and side-lane evals/clerk.
      if (!_lanes.dropWaitingReplies()) _lanes.abortAll();
    }
  }

  /// Cancel any in-flight generation and wait for it to fully stop.
  Future<void> cancelAndWaitForGeneration() async {
    _needsSimulation.consumePendingCatastrophe();
    if (!_p.isGenerating) return;
    _p.cancelRequested = true;
    _lanes
        .dropWaitingReplies(); // not held up by the pass ahead; nothing is aborted
    // Spin until generate finishes its cleanup
    while (_p.isGenerating) {
      await Future.delayed(const Duration(milliseconds: 10));
    }
  }

  void rewindPocketsForDeletedMessage(
    ChatMessage deleted, {
    required bool wasTail,
  }) {
    if (wasTail) {
      _pocketsRewinds.restoreFromStamp(deleted, after: false);
      return;
    }
    unawaited(_itemCards.replant(deleted, key: 'item_cards_retired'));
    if (!_storageService.realismSettings.pocketsEnabled) return;
    final before = deleted.metadata?['pockets_before'];
    if (before is! Map) return;
    final speakerId = before['char'];
    if (speakerId is! String || speakerId.isEmpty) return;
    final othersBefore = <String, Pockets>{};
    final rawOthers = before['others'];
    if (rawOthers is List) {
      for (final o in rawOthers) {
        if (o is Map && o['char'] is String) {
          othersBefore[o['char'] as String] = Pockets.fromJson(o['record']);
        }
      }
    }
    final othersAfter = <String, Pockets>{};
    final rawAfter = deleted.activeMetadata?['pockets_after_others'];
    if (rawAfter is List) {
      for (final o in rawAfter) {
        if (o is Map && o['char'] is String) {
          othersAfter[o['char'] as String] = Pockets.fromJson(o['record']);
        }
      }
    }
    final ids = <String>{
      speakerId,
      ...othersBefore.keys,
      ...othersAfter.keys,
      if (_activeGroup != null)
        for (final c in _groupCharacters) _getCharacterIdFromCard(c),
      if (_activeGroup == null && _session.activeCharacter != null)
        _getCharacterIdFromCard(_session.activeCharacter!),
    };
    final live = <String, Pockets>{
      for (final id in ids)
        if (id.isNotEmpty && _pocketsLedger.pocketsWriteAllowed(id))
          id: (_g.pocketsLedger.pocketsFor(id) ?? Pockets()).copy(),
    };
    invertDeletedPocketTurn(
      speakerId: speakerId,
      speakerBefore: Pockets.fromJson(before['record']),
      speakerAfter: pocketsStamp(deleted.activeMetadata?['pockets_after']),
      othersBefore: othersBefore,
      othersAfter: othersAfter,
      live: live,
    );
    for (final e in live.entries) {
      if (!_pocketsLedger.pocketsWriteAllowed(e.key)) continue;
      _g.pocketsLedger.setPocketsFor(e.key, e.value);
    }
  }

  /// The deleted speaker's Needs before a delete's restores run, for the
  /// refund the editor settles last (NeedsRewinds.revertForDeletedMessage).
  /// In a group, refund ONLY when the speaker resolved unambiguously —
  /// falling back to the live scalars there would credit whichever member
  /// happens to be loaded, i.e. refund the wrong character. An empty
  /// baseline makes the revert a no-op. Reads the chat's stored switch: this
  /// rewinds state, it does not run Needs.
  Map<String, int> needsBeforeDelete(String? deletedSid) =>
      (!_needsSimEnabled || (_activeGroup != null && deletedSid == null))
      ? const <String, int>{}
      : (deletedSid != null
            ? Map<String, int>.from(_groupStore.needsOf(deletedSid))
            : Map<String, int>.from(_needsSimulation.vector));

  /// Cancel an in-flight Realism eval or post-gen tick. No-op when idle.
  Future<void> cancelRealismEval() async {
    // Always tear down both lanes first — a fused/clerk call on the
    // worker can still be in flight when the mouth flags look idle.
    _lanes.abortAll();
    _needsSimulation.consumePendingCatastrophe();

    // No-op if there is nothing to cancel. Post-gen clock/wear is
    // cancellable too — a regen abort mid-tick must put the captured
    // clock back and drop the aborted slot's after.
    if (!_isEvaluatingRealism &&
        !_isProcessingGreeting &&
        !_p.isPostGenerating) {
      debugPrint('[Realism] Cancel request ignored — no active realism eval.');
      return;
    }

    _isCancellingRealismEval = true;
    // Signal to any ongoing realism evaluation that a cancel has been requested.
    _realismEvalCancelled = true;
    _p.postGenAbortRequested = true;
    _d.notify();

    // Transient banner only — NEVER a chat message. The old code appended an
    // "evaluation interrupted" line attributed to the character, which then
    // permanently rode chat history, prompts, RAG, and journal windows.
    // Regen holds isPostGenerating from the first revert through
    // post-gen. Cancel during the pre-reply judges is still a regen:
    // the popped reply is put back. Do not require !_isEvaluatingRealism.
    // No reply: a notice that stays until the chat moves on (not a timer).
    _noteStoppedReply(
      replyKept: _p.isPostGenerating && !_p.answeringUnansweredLine,
    );

    debugPrint('[Realism] Realism eval cancel requested');
    _realismEvalStreamText = '';
    _pendingRealismMetadata = null;
    _isEvaluatingRealism = false;
    _isProcessingGreeting = false;
    _isCancellingRealismEval = false;
    // Keep _realismEvalCancelled so sendMessage returns early.
    _d.notify();
  }

  /// Ends a stopped turn: keeps the partial with its thought closed so regen
  /// and Continue work, saves, and signals done. The stream-loop break and
  /// the catch path's treatAsCancel both end here; [target] is null when the
  /// throw came before any reply was painted.
  Future<void> haltStoppedTurn(GenTurn t, ChatMessage? target) async {
    _p.drainTimer?.cancel();
    _p.drainTimer = null;
    _p.tokenBuffer.clear();
    _p.isGenerating = false;
    _p.cancelRequested = false;
    _p.generationProgress = 0.0;
    _p.generationPhase = GenerationPhase.idle;
    _p.prefillStartTime = null;
    _p.prefillPromptTokens = 0;
    _p.generationStartTime = null;
    t.perfPoller?.cancel();
    t.perfPoller = null;
    _p.tokenBroadcast.add('__DONE__');
    if (_p.sentenceBuffer.trim().isNotEmpty) {
      _p.sentenceBroadcast.add(_p.sentenceBuffer.trim());
      _p.sentenceBuffer = '';
    }
    _p.sentenceBroadcast.add('__DONE__');
    if (t.originalModelName != null && _llmProvider != null) {
      _llmProvider!.openRouterService.configure(modelName: t.originalModelName);
    }
    if (target != null) {
      t.sealThinkClock();
      final closed = closeOpenThink(target.text);
      if (closed != target.text) target.text = closed;
    }
    await _saveChat();
    _d.notify();
  }
}
