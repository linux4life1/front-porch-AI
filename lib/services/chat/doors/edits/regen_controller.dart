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

import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/chat/chat.dart';
import 'package:front_porch_ai/services/chat/doors/edits/edit_deps.dart';
import 'package:front_porch_ai/services/chat/doors/edits/regen_tail.dart';
import 'package:front_porch_ai/services/chat/prompt_injection/prompt_injection.dart';

/// Regenerate: the rejected reply is popped, its turn is rewound to the
/// pre-turn baseline (Realism, Needs, Pockets, objectives, the clock from
/// `story_clock_before`), the same inputs are scored again and the new
/// reply lands as a swipe on the original message.
///
/// 1:1 replays the judges here; a group replays them inside the generation
/// for the rejected SPEAKER, resolved from the message, never from whoever
/// is loaded. Continue is not this class.
class RegenController {
  RegenController(this._d);

  final EditDeps _d;
  late final RegenTail _tail = RegenTail(_d);

  ChatSessionState get _session => _d.session;
  EditServices get _s => _d.services;
  late final RealismScope _scope = _s.graph().scope;
  GroupChat? get _activeGroup => _session.activeGroup;
  List<CharacterCard> get _groupCharacters => _session.groupCharacters;
  bool get _realismEnabled => _scope.realismEnabled();
  bool get _realismEvalCancelled => _d.realism.evalCancelled();
  set _realismEvalCancelled(bool on) => _d.realism.setEvalCancelled(on);
  Map<String, dynamic>? get _pendingRealismMetadata => _scope.pending();
  set _pendingRealismMetadata(Map<String, dynamic>? v) => _scope.setPending(v);
  TimeService get _timeService => _scope.time();

  String _getCharacterIdFromCard(CharacterCard c) => _d.characterIdFor(c);
  CharacterCard? _resolveGroupSpeakerForMessage(ChatMessage msg) =>
      resolveGroupSpeakerForMessage(_groupCharacters, msg);
  bool _isGuestAuthoredMessage(ChatMessage m) => _d.cast.isGuestAuthored(m);
  void _restoreRealismStateForSpeaker(ChatMessage msg) =>
      _s.graph().restores.forSpeaker(msg);
  Future<void> _saveChat({bool replaceAll = false}) =>
      _d.saveChat(replaceAll: replaceAll);
  void notifyListeners() => _d.notify();

  /// Index of the most recent host (main character) message that is buried only
  /// under Scene Guest (Lite NPC) chime-in replies — i.e. the tail of the chat
  /// is one or more guest messages sitting directly on top of it. Returns null
  /// when the last message is already the host's (use the normal last-message
  /// regen), when a user/System message breaks the guest tail, or outside a 1:1
  /// scene. The UI uses this to offer "regenerate the main character" on a host
  /// bubble that the last-message-only regen button can no longer reach.
  int? get hostBelowGuestsIndex {
    if (_activeGroup != null || _session.messages.isEmpty) return null;
    if (!_isGuestAuthoredMessage(_session.messages.last)) return null;
    for (int i = _session.messages.length - 1; i >= 0; i--) {
      final m = _session.messages[i];
      if (m.isUser || m.sender == 'System') return null;
      if (!_isGuestAuthoredMessage(m)) return i;
    }
    return null;
  }

  /// Regenerate the main character's (host's) most recent message when it has
  /// been buried under Scene Guest (Lite NPC) chime-in replies — the case the
  /// last-message-only [regenerateLastMessage] button can no longer reach (the
  /// guest spoke last). The guest replies were reactions to the host text we are
  /// about to discard, so they are removed from the chat (UI + context) first;
  /// the host message is then regenerated as a new swipe via
  /// [regenerateLastMessage] (so realism is reverted to the previous accepted
  /// baseline exactly as for a normal regen — no parallel logic); finally the
  /// guest chime gate is re-run against the NEW host reply, so a guest speaks
  /// again only if it is still warranted (mention / relevance), never blindly.
  ///
  /// When the host message is already last (no trailing guests) this simply
  /// delegates to [regenerateLastMessage].
  Future<void> regenerateMainCharacter({
    String? critique,
    String? webQuery,
    String? wikiQuery,
  }) async {
    if (_session.messages.isEmpty || _d.cast.guestBusy()) return;
    if (!await _d.turn.yieldSettlingTurn()) return;
    _d.turn.bumpMemoryEpoch();
    // Backend gate BEFORE any guest-tail splice — same restore problem as
    // regenerateLastMessage (see abortIfBackendDown).
    if (await _d.turn.abortIfBackendDown()) return;

    // Walk back past the trailing guest replies to the host message beneath them.
    int hostIndex = -1;
    for (int i = _session.messages.length - 1; i >= 0; i--) {
      final m = _session.messages[i];
      if (m.isUser || m.sender == 'System') {
        return; // user/System tail — nothing to regen
      }
      // Narration banners (dreams, Chance Time) look like character messages
      // (isUser false, character-name sender) but are not regen targets —
      // regenerating one would replace a rollover artifact with a chat reply.
      if (m.activeMetadata?['is_dream'] == true ||
          m.activeMetadata?['is_chance_time_narration'] == true) {
        return;
      }
      if (!_isGuestAuthoredMessage(m)) {
        hostIndex = i;
        break;
      }
    }
    if (hostIndex < 0) return; // only guest messages present — no host to regen

    // Host already last → plain regen (no guests to pop).
    if (hostIndex == _session.messages.length - 1) {
      await regenerateLastMessage(
        critique: critique,
        webQuery: webQuery,
        wikiQuery: wikiQuery,
      );
      return;
    }

    // Reconstruct the user text that prompted the host turn for the re-chime gate.
    String userText = '';
    for (int i = hostIndex - 1; i >= 0; i--) {
      if (_session.messages[i].isUser) {
        userText = _session.messages[i].text;
        break;
      }
    }

    // Remove the now-stale trailing guest replies from UI + context, then regen
    // the (now last) host message and re-run the chime gate on the new reply.
    _session.messages.removeRange(hostIndex + 1, _session.messages.length);
    await _saveChat(replaceAll: true);
    notifyListeners();
    await regenerateLastMessage(
      critique: critique,
      webQuery: webQuery,
      wikiQuery: wikiQuery,
    );
    await _d.cast.guestChimeIns(userText: userText);
  }

  Future<void> regenerateLastMessage({
    String? critique,
    String? webQuery,
    String? wikiQuery,
  }) async {
    if (_session.messages.isEmpty || _d.cast.guestBusy()) return;
    if (!await _d.turn.yieldSettlingTurn()) return;
    _d.turn.bumpMemoryEpoch();
    // Hold the settling flag across the WHOLE regen — the realism revert +
    // eval replay before generation and the swipe-merge after it both run
    // outside the generation, and used to run with every guard open: a
    // send/delete/chat-switch landing there operated on a timeline with the
    // last message popped or the merge half-done (the same interleave class
    // the in-generate settling fix closed). The generation restores the
    // caller's hold on exit instead of hard-clearing, so this survives the
    // nested call; the finally makes a wedged flag impossible. The body is
    // extracted (not inlined in the try) purely so its early returns and
    // this hold compose without re-indenting the whole flow.
    _d.turn.setPostGenerating(true);
    try {
      await _regenerateLastMessageHeld(
        critique: critique,
        webQuery: webQuery,
        wikiQuery: wikiQuery,
      );
    } catch (e) {
      _s.graph().clockWriter.restoreCapturedThroughReader();
      rethrow;
    } finally {
      _session.groupManager?.endRegeneration();
      _d.turn.setPostGenerating(false);
      _d.turn.clearPostGenAbortFlags();
      _s.graph().clockReader.applyTipClock();
      // Listeners (web isSettlingTurn → chat_updated) only see the clear
      // through a notification. The flag alone does not broadcast.
      notifyListeners();
    }
  }

  Future<void> _regenerateLastMessageHeld({
    String? critique,
    String? webQuery,
    String? wikiQuery,
  }) async {
    // Backend gate BEFORE the pop below — aborting after removeLast would
    // drop the popped reply (the deep guard in the generation cannot
    // restore it; see abortIfBackendDown).
    if (await _d.turn.abortIfBackendDown()) return;

    // A failed turn's banner (and empty bubble) go; the user line behind
    // them is then answered by the last branch below, as the member who
    // failed. Without this, regenerate after any failure did nothing.
    final failedSpeaker = await _tail.dropFailedTurnLeftovers();

    // Check if the last message is from the character. Narration banners
    // (dreams, Chance Time) carry a character-name sender but must never be
    // regen targets — a regen would swipe a chat reply into the banner.
    if (!_session.messages.last.isUser &&
        _session.messages.last.sender != 'System' &&
        _session.messages.last.activeMetadata?['is_dream'] != true &&
        _session.messages.last.activeMetadata?['is_chance_time_narration'] !=
            true) {
      // New swipe; pop first so the cite is persist index, not window 23.
      final lastMsg = _session.messages.removeLast();
      // Is this a Scene Guest message? If so the whole regen must stay a
      // parity-safe GUEST turn: skip every Realism/Needs revert + re-eval below
      // and regenerate spoken as the guest (guestSpeaker), exactly like the
      // normal guest turn path. A host message keeps the existing behaviour.
      final regenGuest = _d.cast.guestFor(lastMsg);
      // If the message was authored by a guest who has since LEFT the scene (or
      // had their card deleted), we can neither regenerate as them nor run the
      // host realism block on their text (that would perturb the host's
      // bond/trust/emotion/needs from guest-authored content). Refuse cleanly
      // BEFORE journal invalidation — the bubble stays on screen, so its
      // cites must stay too.
      if (regenGuest == null && _isGuestAuthoredMessage(lastMsg)) {
        _session.messages.add(lastMsg); // put it back untouched
        notifyListeners();
        _d.cast.setStatus(
          'Can’t regenerate "${lastMsg.sender}" — they have left the scene.',
          isError: true,
        );
        return;
      }
      // Snapshot the rejected swipe's metadata (e.g. manual needs reprocess) before
      // we add a new swipe — regen must not clobber prior swipe timelines.
      final rejectedSwipeIndex = lastMsg.swipeIndex;
      Map<String, dynamic>? preservedRejectedMeta;
      if (rejectedSwipeIndex >= 0) {
        if (rejectedSwipeIndex < lastMsg.swipeMetadata.length &&
            lastMsg.swipeMetadata[rejectedSwipeIndex] != null) {
          preservedRejectedMeta = Map<String, dynamic>.from(
            lastMsg.swipeMetadata[rejectedSwipeIndex]!,
          );
        } else if (lastMsg.activeMetadata != null) {
          preservedRejectedMeta = Map<String, dynamic>.from(
            lastMsg.activeMetadata!,
          );
        }
      }
      notifyListeners();

      // Resolve the rejected turn's speaker once (exact name match) — used to
      // force the turn manager AND to target the realism revert below. If the
      // member was renamed/removed, BOTH sites skip rather than fall back to
      // the first member: forcing or reverting the wrong character corrupts
      // that character's state and attribution.
      CharacterCard? regenSpeakerCard;
      String regenSpeakerSid = '';
      if (_activeGroup != null && regenGuest == null) {
        regenSpeakerCard = _resolveGroupSpeakerForMessage(lastMsg);
        if (regenSpeakerCard != null) {
          regenSpeakerSid = _getCharacterIdFromCard(regenSpeakerCard);
        }
      }

      // In group mode the original speaker re-speaks. The rotation is held
      // and put back by regenerateLastMessage's finally, success or not.
      if (regenSpeakerCard != null) {
        _session.groupManager?.beginRegeneration(regenSpeakerCard);
      }

      // Roll back objective mutations recorded for the rejected turn (eval
      // proposals + completion-check side effects) BEFORE the eval replay, so
      // the new turn re-derives objectives from a clean baseline instead of
      // stacking on the invalidated turn's (and dedup can't suppress a fresh
      // proposal because the rejected turn's copy still exists). Runs with or
      // without realism (completion checks also run realism-off); id-addressed
      // ops keep 1:1 and group identical. Guest turns never touch objectives.
      if (regenGuest == null) {
        await _s.objectives().revertTurn(lastMsg);
        // Rewind the rejected turn's pockets ops to the pre-turn record, so
        // the regenerated reply's own pass re-applies from the same base
        // instead of stacking — "they hand you their keys", regenerate, they
        // keeps knitting, and the keys used to be gone anyway (hostile
        // review 2026-08-11). Group-safe: the stamp carries the speaker's
        // own charId. The journal invalidation above already took the
        // rejected turn's item cards with it.
        _s.graph().pocketsRewinds.restoreFromStamp(lastMsg, after: false);
      }

      // Capture the live clock first. Fail/cancel/abort put it back so
      // a rejected regen never leaves the sidebar on the rewound before.
      // Then rewind to the shared message-level before (every swipe).
      _s.graph().clockWriter.rewindClockToPreReply(lastMsg);

      if (!_s.graph().regenBaseline.revert(
        lastMsg: lastMsg,
        regenGuest: regenGuest,
        regenSpeakerCard: regenSpeakerCard,
        regenSpeakerSid: regenSpeakerSid,
      )) {
        _session.messages.add(lastMsg);
        _s.graph().clockWriter.restoreCapturedThroughReader();
        _restoreRealismStateForSpeaker(lastMsg);
        _s.graph().pocketsRewinds.restoreFromStamp(lastMsg, after: true);
        return;
      }
      // A long skip's reply: the revert put the pre-skip mood back.
      final skipMeta = {...?preservedRejectedMeta, ...?lastMsg.activeMetadata};
      final longSkip = (skipMeta[kLongSkipMinutesMeta] as num?)?.toInt() ?? 0;
      if (longSkip > 0) LongSkipSettle(_s.graph().scope).settle();

      // After the unreadable-baseline bail: the bubble stays, so its
      // journal/growth cites must stay too (same rule as a departed guest).
      _s.graph().timeline.invalidateFrom(
        persistMessagePosition(
          base: _s.history().basePosition,
          index: _session.messages.length,
        ),
      );

      // 1:1 only: replay decay + the realism eval inline here (groups replay
      // via the per-speaker dance inside the generation). A cancel there has
      // already put the popped reply back with its accepted state.
      if (_realismEnabled && _activeGroup == null && regenGuest == null) {
        if (!await _d.realism.replayRegenJudges(lastMsg)) return;
      }

      // In group mode the per-speaker realism eval (and its metadata / needs deltas)
      // happens inside the generation via RealismDance.evaluateForUpcomingSpeaker
      // for the correctly-forced speaker. Skip the 1:1 scalar synthesis here.
      Map<String, int>? regenPreTurn;
      if (_activeGroup == null && regenGuest == null) {
        // Save pre-turn vector BEFORE the generation (which clears
        // the pending realism metadata).
        regenPreTurn =
            _pendingRealismMetadata?['needs_pre_turn_vector']
                as Map<String, int>?;

        // Synthesize metadata after all regen evals complete — mirrors the
        // normal path so emotion_label and realism_state are in the pending
        // metadata before the generation consumes it.
        _pendingRealismMetadata ??= {};
        // Mood only when Realism ran. With Realism off this stamped the
        // stale mood, and that one key lit Mood + Bond/Trust unchanged chips.
        if (_realismEnabled) {
          _pendingRealismMetadata!['emotion_label'] = _scope.emotion();
        }
        _pendingRealismMetadata!['realism_state'] = _s.graph().snapshot.capture(
          preTurn: regenPreTurn,
        );

        // If cancellation was requested during realism evaluation, abort
        // generation — restoring the popped reply first, for the same reason
        // as the cancel point in the judge replay: the generation has still
        // not run, so this local is the only place the message still exists.
        if (_realismEvalCancelled) {
          _session.messages.add(lastMsg);
          // Same put-back contract as the cancel point above: the message
          // returns WITH the state it was accepted under.
          _s.graph().clockReader.applyTipClock();
          _restoreRealismStateForSpeaker(lastMsg);
          _s.graph().pocketsRewinds.restoreFromStamp(lastMsg, after: true);
          _pendingRealismMetadata = null;
          _realismEvalCancelled = false;
          notifyListeners();
          await _saveChat();
          return;
        }
      }

      // Invalidate ONNX cache for the new response (delegated)
      _s.graph().expression.invalidateOnnxCacheForNewResponse();

      // Generate into a new message — it will be appended by the generation.
      // For a guest message we pass guestSpeaker so the new swipe is spoken as
      // the guest. The guest has no speaker Realism/Needs, but lite post-gen
      // still ticks the clock and wears present bodies (the 1:1 host). The
      // revert above restored that pre-wear snapshot so replay wears once.
      // For a host message regenGuest is null and this is the unchanged host
      // path: the generation runs the post-gen needs checks AND the chip
      // attach — a regen runs in normal mode, so needs_deltas land on the
      // streamed message exactly like a fresh turn (1:1 and group alike) and
      // ride newMetadata into the swipe-merge below.
      // The duplicate post-generation recompute that used to live here was a
      // second source of truth for the same numbers; deleted 2026-08-04.
      final skipTo =
          lastMsg.activeMetadata?['time_skip_to'] as String? ??
          preservedRejectedMeta?['time_skip_to'] as String?;
      if (skipTo != null && skipTo.isNotEmpty) {
        _pendingRealismMetadata ??= {};
        _pendingRealismMetadata!['time_skip_to'] = skipTo;
        final passed =
            lastMsg.activeMetadata?['time_passed'] as String? ??
            preservedRejectedMeta?['time_passed'] as String? ??
            _timeService.bodyTimeLabel;
        if (passed != null && passed.isNotEmpty) {
          _pendingRealismMetadata!['time_passed'] = passed;
        }
        _timeService.reclaimSkipOwnership();
      }
      // A skip line or a calendar jump: the replay notes the same beat, so
      // the bodies wear (or land, for days) again as the first reply's did.
      final skipped = longSkip > 0 || (skipTo ?? '').isEmpty
          ? longSkip
          : (skipMeta[kSkipMinutesMeta] as num?)?.toInt() ?? 0;
      if (skipped > 0) {
        final slept = skipMeta[kSkipSleptMeta] == true;
        _timeService.renoteSkip(skipped, to: skipTo, slept: slept);
      }

      final preGenLen = _session.messages.length;
      _s.media().armForcedLookup(webQuery: webQuery, wikiQuery: wikiQuery);
      await _d.turn.generate(
        GenerationMode.normal,
        directUserSend: true,
        guestSpeaker: regenGuest,
        forceSpeaker: regenGuest == null && _activeGroup != null
            ? _resolveGroupSpeakerForMessage(lastMsg)
            : null,
        regenCritique: RegenCritiqueInjection.fragment(
          spokenText: lastMsg.displayText,
          reason: critique ?? '',
        ),
      );

      // After generation, merge the new response as a swipe on the original
      // message — but ONLY when the generation actually appended one. It
      // can return empty-handed (the group per-speaker realism cancel path
      // saves-and-returns before assembling blocks) or append a System error
      // banner (any phase-1..4 throw). The old guard read the last message
      // alone, so an empty return dropped the popped reply — with every
      // alternate swipe it held — forever (and in a group whose previous
      // entry was ANOTHER member's reply, it merged that member's message
      // into the regen target instead). The length check makes "no new
      // reply" restore the popped message at its original position.
      await _tail.mergeOrRestore(
        lastMsg: lastMsg,
        regenGuest: regenGuest,
        preservedRejectedMeta: preservedRejectedMeta,
        rejectedSwipeIndex: rejectedSwipeIndex,
        preGenLen: preGenLen,
      );
    } else if (_session.messages.last.isUser) {
      // No reply to swipe: rewind to the user line's stamp and score it again.
      // A failed member is forced, not picked: the rotation already moved
      // past them, and a pick would move it again.
      await _d.turn.answerTrailingUserLine(
        webQuery: webQuery,
        wikiQuery: wikiQuery,
        forceSpeaker: failedSpeaker,
      );
    }
  }
}
