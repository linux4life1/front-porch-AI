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

/// The two ends of a regen around the generation: clearing a failed turn's
/// leftovers before it, and after it merging the new reply as a swipe on
/// the original message, or putting the popped reply back when no reply
/// came.
class RegenTail {
  RegenTail(this._d);

  final EditDeps _d;

  ChatSessionState get _session => _d.session;
  EditServices get _s => _d.services;
  late final RealismScope _scope = _s.realismScope();
  GroupChat? get _activeGroup => _session.activeGroup;

  CharacterCard? _resolveGroupSpeakerForMessage(ChatMessage msg) =>
      resolveGroupSpeakerForMessage(_session.groupCharacters, msg);
  bool _isGuestAuthoredMessage(ChatMessage m) => _d.cast.isGuestAuthored(m);
  void _restoreRealismStateForSpeaker(ChatMessage msg) =>
      _d.realism.restoreForSpeaker(msg);
  Future<void> _saveChat({bool replaceAll = false}) =>
      _d.saveChat(replaceAll: replaceAll);
  void notifyListeners() => _d.notify();

  /// A failed turn ends `user -> System banner`, or `user -> empty reply ->
  /// banner` when it failed after its bubble was attached (a server error on
  /// the stream). Neither is a reply to regenerate, so regenerate was a
  /// silent no-op. Drop them, leaving the user line to be answered again.
  /// Only with that unanswered user line behind them: every System banner
  /// (generation error, backend-down, failed entrance) is discardable only
  /// then; a banner after a real reply stays.
  ///
  /// Returns the failed reply's group member, who answers again: their pick
  /// already moved the rotation on, so a fresh pick would skip them.
  Future<CharacterCard?> dropFailedTurnLeftovers() async {
    final n = _session.messages.length;
    if (n < 2 ||
        _session.messages.last.isUser ||
        _session.messages.last.sender != 'System') {
      return null;
    }
    final ghost = _isFailedReplyGhost(_session.messages[n - 2])
        ? _session.messages[n - 2]
        : null;
    final userAt = n - (ghost == null ? 2 : 3);
    if (userAt < 0 || !_session.messages[userAt].isUser) return null;
    _session.messages.removeRange(userAt + 1, n);
    // Its quests have no reply to ride on; the retry proposes them again.
    if (ghost != null) await _s.objectives().revertTurn(ghost);
    await _saveChat(replaceAll: true);
    if (ghost == null || _activeGroup == null) return null;
    return _resolveGroupSpeakerForMessage(ghost);
  }

  /// The bubble a failed turn attached before any text: no text or thinking,
  /// one swipe, no image. The host's or a member's only; a Scene Guest's is
  /// left alone (the retry answers the user line as the host).
  bool _isFailedReplyGhost(ChatMessage m) =>
      !m.isUser &&
      m.sender != 'System' &&
      m.text.trim().isEmpty &&
      m.swipes.length == 1 &&
      m.activeMetadata?['is_generated_image'] != true &&
      !_isGuestAuthoredMessage(m);

  Future<void> mergeOrRestore({
    required ChatMessage lastMsg,
    required CharacterCard? regenGuest,
    required Map<String, dynamic>? preservedRejectedMeta,
    required int rejectedSwipeIndex,
    required int preGenLen,
  }) async {
    final appendedReply =
        _session.messages.length > preGenLen &&
        !_session.messages.last.isUser &&
        _session.messages.last.sender != 'System';
    if (!appendedReply) {
      // The shell catch leaves the failed turn's EMPTY stream target in
      // place before the System banner — drop that ghost so the restored
      // reply doesn't sit next to a blank bubble of the same speaker.
      final ghostIdx = _session.messages.indexWhere(
        (m) => !m.isUser && m.sender != 'System' && m.text.isEmpty,
        preGenLen,
      );
      if (ghostIdx >= 0) _session.messages.removeAt(ghostIdx);
      _session.messages.insert(preGenLen, lastMsg);
      _s.clockReader().applyTipClock();
      if (regenGuest == null) {
        _restoreRealismStateForSpeaker(lastMsg);
        // The pre-generation rewind above rolled pockets to the PRE-turn
        // record; with no new reply the message returns showing its
        // accepted text, so the pockets must return to the accepted
        // (post-turn) record too — same put-back contract as the two
        // realism-cancel points in the regen before it.
        _s.pocketsRewinds().restoreFromStamp(lastMsg, after: true);
      }
      notifyListeners();
      // Full rewrite: the abort inside the generation already persisted
      // the shortened transcript, so an upsert alone cannot heal the row.
      await _saveChat(replaceAll: true);
      return;
    }
    if (_session.messages.isNotEmpty &&
        !_session.messages.last.isUser &&
        _session.messages.last.sender != 'System') {
      final newText = _session.messages.last.text;
      final newMetadata = _session.messages.last.activeMetadata != null
          ? Map<String, dynamic>.from(_session.messages.last.activeMetadata!)
          : null;
      // This swipe's own "Thought for Ns", timed while it streamed.
      final newThinkingMs = _session.messages.last.thinkingDurationMs;
      final tempBefore = _session.messages.last.metadata?['pockets_before'];
      _session.messages.removeLast();
      if (tempBefore is Map) {
        lastMsg.metadata ??= {};
        lastMsg.metadata!['pockets_before'] = tempBefore;
      }
      lastMsg.swipes.add(newText);
      while (lastMsg.swipeDurations.length < lastMsg.swipes.length) {
        lastMsg.swipeDurations.add(0);
      }
      final newSwipeIndex = lastMsg.swipes.length - 1;
      lastMsg.swipeDurations[newSwipeIndex] = newThinkingMs;
      if (preservedRejectedMeta != null && rejectedSwipeIndex >= 0) {
        while (lastMsg.swipeMetadata.length <= rejectedSwipeIndex) {
          lastMsg.swipeMetadata.add(null);
        }
        lastMsg.swipeMetadata[rejectedSwipeIndex] = preservedRejectedMeta;
      }
      while (lastMsg.swipeMetadata.length <= newSwipeIndex) {
        lastMsg.swipeMetadata.add(null);
      }
      lastMsg.swipeIndex = newSwipeIndex;
      // New swipe metadata only — prior swipes (incl. manual reprocess) stay
      // intact. newMetadata already carries this swipe's needs_deltas: the
      // chip attach inside the generation is the one source of truth.
      if (newMetadata != null) {
        lastMsg.swipeMetadata[newSwipeIndex] = newMetadata;
      }
      if (_scope.clockRunning()) {
        _s.clockWriter().discoverAndPersistMessageBefore(lastMsg);
      }
      _session.messages.add(lastMsg);
      // Host messages restore the active character's Realism/Needs from the
      // accepted swipe (in groups: the speaker's own _groupRealism entry).
      // Guest swipes wear present bodies (1:1 host); the replay just wore
      // them once — do not pull a host realism_state the guest never had.
      if (regenGuest == null) _restoreRealismStateForSpeaker(lastMsg);
      _s.clockReader().applyTipClock();
      _scope.time().clearCapturedClock();
      await _saveChat();
      notifyListeners();
      // The group rotation is put back by regenerateLastMessage's finally.
    }
  }
}
