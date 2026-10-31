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
    show AppDatabaseChatQueries;
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/chat/chat.dart';
import 'package:front_porch_ai/services/chat/doors/edits/edit_deps.dart';

/// Edit, delete and tail delete of one message, and the session-level
/// clears (reload, clear, delete a chat).
///
/// Delete is time travel for whatever the deleted reply changed: Realism
/// rewinds to the new last stamp, Needs are refunded by the reply's own
/// chips, Pockets and the clock rewind on their own stamps. In a group each
/// restore keys by the message's speaker id, never by whoever is loaded.
class MessageEditor {
  MessageEditor(this._d);

  final EditDeps _d;

  ChatSessionState get _session => _d.session;
  EditServices get _s => _d.services;
  GroupChat? get _activeGroup => _session.activeGroup;
  List<CharacterCard> get _groupCharacters => _session.groupCharacters;
  bool get _isTurnBusy => _d.turn.isTurnBusy();
  SessionHistoryWindow get _history => _s.history();

  String _getCharacterIdFromCard(CharacterCard c) => _d.characterIdFor(c);
  CharacterCard? _resolveGroupSpeakerForMessage(ChatMessage msg) =>
      resolveGroupSpeakerForMessage(_groupCharacters, msg);
  Future<void> _saveChat({bool replaceAll = false}) =>
      _d.saveChat(replaceAll: replaceAll);
  void notifyListeners() => _d.notify();

  /// Replaces [index]'s text. The text setter keeps swipe and realism
  /// metadata (chips survive an edit).
  void edit(int index, String newText) async {
    if (index >= 0 && index < _session.messages.length) {
      final msg = _session.messages[index];
      // text setter keeps swipe + realism metadata (chips survive edit).
      msg.text = newText;
      // Persist index — on-screen 0..23 is a tail window, not the diary cite.
      _s.timeline().invalidateFrom(
        persistMessagePosition(base: _history.basePosition, index: index),
      );
      await _saveChat();
      notifyListeners();
    }
  }

  /// Reload the current session from the database without clearing messages first.
  /// Used after cloud sync or DB migration updates the database — preserves the
  /// user's active chat instead of wiping it.
  Future<void> reloadCurrentSession() async {
    if (_session.currentSessionId == null) return;
    debugPrint(
      '[Chat] 🔄 reloadCurrentSession: reloading session ${_session.currentSessionId} '
      '(currently ${_session.messages.length} messages in memory)',
    );
    await _d.sessions().loader.loadSession(_session.currentSessionId!);
  }

  void clearChat() async {
    debugPrint(
      '[Chat] 🟡 clearChat: clearing ${_session.messages.length} messages',
    );
    _session.messages.clear();
    await _saveChat();
    notifyListeners();
  }

  /// Delete a specific chat session and its messages.
  /// If it's the current session, switches to the most recent remaining one.
  ///
  /// [startReplacement] is the in-chat folder behaviour (default): when the
  /// deleted id is the open session and nothing remains, start a new chat so
  /// the user is not left staring at a missing chat. Home / the web library
  /// pass false so emptying a card's history does not spawn a replacement.
  Future<void> deleteSession(
    String sessionId, {
    bool startReplacement = true,
  }) async {
    await _s.db().deleteMessagesForSession(sessionId);
    await _s.db().deleteSessionById(sessionId);

    // If we deleted the current session, switch to another
    if (sessionId == _session.currentSessionId) {
      final remaining = await _d.sessions().loader.getSessions();
      if (remaining.isNotEmpty) {
        if (startReplacement) {
          await _d.sessions().loader.loadSession(remaining.first['id']);
        } else {
          _session.messages.clear();
          _session.currentSessionId = null;
        }
      } else {
        // No sessions left — start fresh only when the open chat asked.
        debugPrint(
          '[Chat] 🟡 deleteSession: no sessions left, clearing messages',
        );
        _session.messages.clear();
        _session.currentSessionId = null;
        if (startReplacement) {
          await _d.sessions().loader.startNewChat();
        }
      }
    }
    notifyListeners();
  }

  Future<void> deleteMessage(int index) async {
    // The tail is the live reply. Positional writers still assume it stays
    // last, and removing it made a dream banner the last message, where
    // the aborted turn's writes landed (2026-07-28). Stop before deleting
    // THAT bubble. An earlier one is already finished — a group mate's
    // long generation must not trap it.
    if (index < 0 || index >= _session.messages.length) return;
    if (_isTurnBusy && index == _session.messages.length - 1) return;
    final dbPos = persistMessagePosition(
      base: _history.basePosition,
      index: index,
    );
    final wasTail = index == _session.messages.length - 1;
    // Middle-of-history delete needs the full prefix so replaceAll
    // cannot drop the 11k rows we have not loaded yet.
    if (!wasTail && _history.hasMore) {
      await _d.sessions().window.awaitHistoryHydrated();
      index = dbPos;
      if (index < 0 || index >= _session.messages.length) return;
      if (_isTurnBusy && index == _session.messages.length - 1) return;
    }
    // Re-read after the hydration await. The turn may have finished,
    // in which case this is an ordinary delete.
    final duringTurn = _isTurnBusy;
    if (index >= 0 && index < _session.messages.length) {
      final deleted = _session.messages[index];

      // Pockets stamp restore runs AFTER realism time-travel below (not
      // here). realism_state.pockets was historically pre-gen and, even
      // when restamped post-gen, restoring the NEW last message must not
      // clobber the deleted turn's pre-ops rewind for the deleted speaker
      // (and any hand-off recipients). Stamp wins last on tail deletes.

      // Needs are refunded by ARITHMETIC (subtract this message's own chips),
      // not by the realism time-travel below — that only ever rewinds the
      // tail, so deleting anything older left its needs cost applied forever.
      // Capture the deleted speaker's needs BEFORE the restore runs; the
      // refund is settled from this baseline afterwards.
      final deletedSpeaker = (!deleted.isUser && deleted.sender != 'System')
          ? _resolveGroupSpeakerForMessage(deleted)
          : null;
      final String? deletedSid =
          (_activeGroup != null && deletedSpeaker != null)
          ? _getCharacterIdFromCard(deletedSpeaker)
          : null;
      // In a group, refund ONLY when the speaker resolved unambiguously —
      // see needsBeforeDelete (an empty baseline makes the revert a no-op).
      final needsBeforeDelete = _d.realism.needsBeforeDelete(deletedSid);
      // Co-present bars, before the snapshot restore below. Ana's wear is
      // undone from these, not from the restored snapshot.
      final presentBeforeDelete = _s.needsRewinds().capturePresentBeforeDelete(
        deleted,
      );

      _session.messages.removeAt(index);

      // Persist index, not the on-screen 0..23 of a tail window.
      _s.timeline().invalidateFrom(dbPos);

      // Time-travel rollback for realism when deleting a character message.
      // Restore from the new last message if it has a snapshot, regardless
      // of whether this was the last message. This ensures needs state
      // (and all realism fields) reset to their previous saved values — in
      // groups, inside the NEW LAST speaker's own _groupRealism entry.
      // Clock is the new visible tip's after — tail and non-tail.
      // The streaming tail's snapshot is the turn still in flight.
      // Restoring it would rewind the speaker who is generating.
      if (!duringTurn) _restoreRealismAfterDelete(deleted, wasTail: wasTail);

      // Group: also roll back the DELETED speaker's OWN _groupRealism entry to
      // their previous stamped turn — otherwise that member's bond/trust/needs
      // deltas from the removed message stand forever (the state machine only
      // rewinds whoever is now last). Guards:
      //   • the deleted message must itself carry a realism_state — otherwise
      //     it applied no deltas and rewinding would INVENT older history;
      //   • the sender name must be unambiguous in the roster — restore resolves
      //     by name (restoreForSpeaker), so with two same-named members it
      //     could rewind the wrong one; skip that rare case rather than
      //     corrupt state;
      //   • skip when the deleted speaker is already the new-last (handled
      //     above) or has no earlier stamped turn.
      if (_activeGroup != null &&
          !deleted.isUser &&
          deleted.sender != 'System' &&
          deleted.activeMetadata?['realism_state'] is Map &&
          deletedSid != null &&
          (_session.messages.isEmpty ||
              _resolveGroupSpeakerForMessage(_session.messages.last) !=
                  deletedSpeaker)) {
        for (int i = _session.messages.length - 1; i >= 0; i--) {
          final m = _session.messages[i];
          final speaker = _resolveGroupSpeakerForMessage(m);
          if (speaker != null &&
              _getCharacterIdFromCard(speaker) == deletedSid &&
              m.activeMetadata?['realism_state'] is Map) {
            _d.realism.keepingLiveSpeaker(() {
              _d.realism.restoreForSpeaker(m, restoreClock: false);
            });
            break;
          }
        }
      }

      // Settle needs LAST so it wins over whatever the snapshot restores did
      // to the vector (see NeedsRewinds.revertForDeletedMessage).
      _s.needsRewinds().revertForDeletedMessage(
        deleted,
        needsBeforeDelete,
        groupSid: deletedSid,
        presentBeforeDelete: presentBeforeDelete,
      );

      if (!deleted.isUser && deleted.sender != 'System') {
        _d.realism.rewindPocketsForDelete(deleted, wasTail: wasTail);
        // Tail turn undone, as regen does: Generate reply re-proposes.
        if (wasTail && !duringTurn) {
          await _s.objectives().revertTurn(deleted);
        }
        // The live tip is the reply still being written. Applying the
        // clock from it mid-turn would move story time under that speaker.
        if (!duringTurn) {
          _s.clockWriter().applyClockAfterDelete(deleted, wasTail: wasTail);
          if (wasTail) _s.afterglow().restoreBeforeBeat(deleted);
        }
      }

      if (wasTail && _history.hasMore) {
        await _saveChat(replaceAll: false);
        final sid = _session.currentSessionId;
        if (sid != null) {
          await _s.db().deleteMessagesAtPosition(sid, dbPos);
        }
      } else {
        await _saveChat(replaceAll: true);
      }
      notifyListeners();
    }
  }

  /// Delete's realism time travel: back to the new last message's stamp.
  /// A 1:1 tail delete of a scored reply leaves the user line last, which
  /// carries no reply stamp, so the deleted reply's mood and bond used to
  /// stand. Rewind the scored registers the way regen does: to the last
  /// accepted reply, else the line's pre-turn stamp. Needs, pockets and the
  /// clock keep their own delete rewinds, which run after this. Groups
  /// rewind the deleted speaker's own entry in the caller.
  void _restoreRealismAfterDelete(
    ChatMessage deleted, {
    required bool wasTail,
  }) {
    if (_session.messages.isEmpty) return;
    final last = _session.messages.last;
    final scoredReplyGone =
        wasTail &&
        _activeGroup == null &&
        last.isUser &&
        deleted.activeMetadata?['realism_state'] is Map &&
        !_d.cast.isGuestAuthored(deleted);
    if (!scoredReplyGone) {
      _d.realism.restoreForSpeaker(last, restoreClock: false);
      return;
    }
    if (_d.realism.rewindToLastAcceptedReply()) return;
    final stamp = last.metadata?[kRealismPreTurn];
    if (stamp is Map) {
      _d.realism.restoreScoredRegisters(Map<String, dynamic>.from(stamp));
    }
  }
}
