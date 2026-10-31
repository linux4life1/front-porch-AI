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

part of '../chat_service.dart';

/// Turn stops and the delete rewinds hygiene tests pin to this file:
/// Continue's entry, the settling yield, [stopGeneration],
/// [cancelRealismEval], and delete's Needs baseline and Pockets rewind.
/// Edit, delete, swipe and the session clears live in the edits door
/// (lib/services/chat/doors/edits/).
extension ChatServiceTurnStops on ChatService {
  /// Abort in-flight post-gen evals so a mutation (regen/continue) can
  /// start. Streaming (`_isGenerating`) and import still refuse — those
  /// are not "I already have the reply and I don't want it scored."
  void _clearPostGenAbortFlags() {
    _postGenAbortRequested = false;
    _isCancellingRealismEval = false;
    _realismEvalCancelled = false;
  }

  Future<bool> _yieldSettlingTurn() async {
    if (_isGenerating || isImporting || _skipAsked) return false;
    if (!_isPostGenerating) {
      // Fast path used to return without touching the flags, so a leftover
      // latch from a prior yield survived into the next regen.
      _clearPostGenAbortFlags();
      return true;
    }
    _postGenAbortRequested = true;
    _isCancellingRealismEval = true;
    _realismEvalCancelled = true;
    _abortAllLanes();
    final deadline = DateTime.now().add(const Duration(seconds: 5));
    while (_isPostGenerating && DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 16));
    }
    // Timeout: post-gen is still running and must keep skipping applies.
    // Success: the next turn starts clean so regen can tick the clock.
    final done = !_isPostGenerating;
    if (done) _clearPostGenAbortFlags();
    return done;
  }

  Future<void> continueGeneration() async {
    if (_session.messages.isEmpty || _sceneGuest.busy) return;
    // Continue KEEPS the reply. Aborting its scoring would leave the first
    // half unbookkept and only score the new fragment. Wait like Send.
    if (_isGenerating || isImporting || _skipAsked) return;
    if (_isPostGenerating) await _waitForTurnToSettle();

    // Only continue if the last message is from a bot (non-user, non-system).
    // Narration banners (dreams, Chance Time) are excluded: continue_ streams
    // straight into _session.messages.last, which would append a chat reply to the
    // banner (the dream-corruption class, 2026-07-28).
    if (!_session.messages.last.isUser &&
        _session.messages.last.sender != 'System' &&
        _session.messages.last.activeMetadata?['is_dream'] != true &&
        _session.messages.last.activeMetadata?['is_chance_time_narration'] !=
            true) {
      await _generateResponse(GenerationMode.continue_);
    }
  }

  void stopGeneration() {
    // Discard before plan consume so the next speaker cannot inherit a
    // Needs catastrophe armed for a turn that never ran. 1:1 evals happen
    // before `_isGenerating`, so this is not gated on that flag.
    _needsSimulation.consumePendingCatastrophe();
    if (_isGenerating) {
      _cancelRequested = true;
      // A waiting reply leaves the line, and nothing of this turn is on the
      // wire to cut. Otherwise abort mouth speech and side-lane evals/clerk.
      if (!_dropWaitingReplies()) _abortAllLanes();
    }
  }

  /// Cancel any in-flight generation and wait for it to fully stop.
  Future<void> _cancelAndWaitForGeneration() async {
    _needsSimulation.consumePendingCatastrophe();
    if (!_isGenerating) return;
    _cancelRequested = true;
    _dropWaitingReplies(); // not held up by the pass ahead; nothing is aborted
    // Spin until _generateResponse finishes its cleanup
    while (_isGenerating) {
      await Future.delayed(const Duration(milliseconds: 10));
    }
  }

  void _rewindPocketsForDeletedMessage(
    ChatMessage deleted, {
    required bool wasTail,
  }) {
    if (wasTail) {
      _pocketsRewinds.restoreFromStamp(deleted, after: false);
      return;
    }
    unawaited(_itemCards.replant(deleted, key: 'item_cards_retired'));
    if (!pocketsFeatureEnabled) return;
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
          id: (pocketsFor(id) ?? Pockets()).copy(),
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
      setPocketsFor(e.key, e.value);
    }
  }

  /// The deleted speaker's Needs before a delete's restores run, for the
  /// refund the editor settles last (NeedsRewinds.revertForDeletedMessage).
  /// In a group, refund ONLY when the speaker resolved unambiguously —
  /// falling back to the live scalars there would credit whichever member
  /// happens to be loaded, i.e. refund the wrong character. An empty
  /// baseline makes the revert a no-op. Reads the chat's stored switch: this
  /// rewinds state, it does not run Needs.
  Map<String, int> _needsBeforeDelete(String? deletedSid) =>
      (!_needsSimEnabled || (_activeGroup != null && deletedSid == null))
      ? const <String, int>{}
      : (deletedSid != null
            ? Map<String, int>.from(_groupStore.needsOf(deletedSid))
            : Map<String, int>.from(_needsSimulation.vector));

  /// Cancel an in-flight Realism eval or post-gen tick. No-op when idle.
  Future<void> cancelRealismEval() async {
    // Always tear down both lanes first — a fused/clerk call on the
    // worker can still be in flight when the mouth flags look idle.
    _abortAllLanes();
    _needsSimulation.consumePendingCatastrophe();

    // No-op if there is nothing to cancel. Post-gen clock/wear is
    // cancellable too — a regen abort mid-tick must put the captured
    // clock back and drop the aborted slot's after.
    if (!_isEvaluatingRealism && !_isProcessingGreeting && !_isPostGenerating) {
      debugPrint('[Realism] Cancel request ignored — no active realism eval.');
      return;
    }

    _isCancellingRealismEval = true;
    // Signal to any ongoing realism evaluation that a cancel has been requested.
    _realismEvalCancelled = true;
    _postGenAbortRequested = true;
    notifyListeners();

    // Transient banner only — NEVER a chat message. The old code appended an
    // "evaluation interrupted" line attributed to the character, which then
    // permanently rode chat history, prompts, RAG, and journal windows.
    // Regen holds _isPostGenerating from the first revert through
    // post-gen. Cancel during the pre-reply judges is still a regen:
    // the popped reply is put back. Do not require !_isEvaluatingRealism.
    // No reply: a notice that stays until the chat moves on (not a timer).
    _noteStoppedReply(
      replyKept: _isPostGenerating && !_answeringUnansweredLine,
    );

    debugPrint('[Realism] Realism eval cancel requested');
    _realismEvalStreamText = '';
    _pendingRealismMetadata = null;
    _isEvaluatingRealism = false;
    _isProcessingGreeting = false;
    _isCancellingRealismEval = false;
    // Keep _realismEvalCancelled so sendMessage returns early.
    notifyListeners();
  }
}
