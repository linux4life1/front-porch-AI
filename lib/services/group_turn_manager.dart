// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:front_porch_ai/models/models.dart';

/// Where the turn order stands: the round-robin index, a forced speaker and
/// a random pick made ahead. Saved before a pick and put back when that
/// turn wrote no reply.
typedef TurnRotation = ({
  int index,
  String? forcedId,
  String? previewId,
  String? queuedId,
});

/// Manages turn order, forced speaker selection, Director Mode state,
/// and related group chat orchestration.
///
/// Extracted from ChatService to reduce the ~40+ scattered
/// `if (_activeGroup != null)` checks and to give the group chat
/// subsystem a clear, testable home for future features
/// (weighted turns, explicit queues, per-character initiative, etc.).
class GroupTurnManager extends ChangeNotifier {
  GroupChat? _group;
  List<CharacterCard> _characters = [];
  int _turnIndex = 0;
  String? _forcedNextSpeakerId;

  /// A cast member the user queued from the chip's Next pill (or the
  /// Director cue) to answer the next turn — keyed by row id, full member
  /// or lite guest alike (both are rotation rows). Unlike [_forcedNextSpeakerId]
  /// (a command's immediate pick, cleared by the slash handler only on
  /// success) this hold is consumed at the pick: a turn stopped or refused
  /// before its bubble opened gets the hold back through the rotation
  /// snapshot; a failed stream goes down the same failure path every
  /// failed pick does. A hand pick ([setNextSpeaker])
  /// replaces it, and so does queueing someone else — one chat, one next
  /// speaker.
  String? _queuedSpeakerId;

  /// Random turn order's next pick, made ahead: a Chance Time spin names who
  /// reacts before the turn picks. Not a forced speaker, so an Away member
  /// coming back still answers; the next random pick takes it.
  String? _previewId;
  ({int index, String? forcedId, String regenId, String? queuedId})? _regenHold;
  bool _observerMode = false;
  bool _autoPlayActive = false;

  // Director auto-play delay is kept here for now (UI frequently mutates it)
  double directorDelaySec = 15.0;

  // ── Public API ─────────────────────────────────────────────────────────

  bool get isActive => _group != null;
  GroupChat? get activeGroup => _group;
  List<CharacterCard> get characters => List.unmodifiable(_characters);

  // characterIds + ID-based add/remove removed (clean-break decoupling of group members).
  // Membership is now List<GroupMember> loaded from repo; IDs are UUIDs from the rows.
  // Add/remove during live chat now copies assets to private group storage + DB row.

  bool get observerMode => _observerMode;
  bool get autoPlayActive => _autoPlayActive;

  /// True while a user-named speaker is waiting to be consumed.
  bool get hasForcedSpeaker => _forcedNextSpeakerId != null;

  /// A member sits in the chip-queue slot (survives failed turns).
  bool get hasQueuedSpeaker => _queuedSpeakerId != null;

  /// The character that will speak on the next generation (respects forced override).
  CharacterCard? get nextSpeaker {
    if (!isActive || _characters.isEmpty) return null;

    // The chip queue shows first: it is the newest user intent (queueing
    // clears a hand pick, and vice versa), and the pill reads this getter.
    if (_queuedSpeakerId != null) {
      final q = _characters.where((c) => _getId(c) == _queuedSpeakerId).firstOrNull;
      if (q != null) return q;
    }

    if (_forcedNextSpeakerId != null) {
      return _characters.firstWhere(
        (c) => _getId(c) == _forcedNextSpeakerId,
        orElse: () => _characters.first,
      );
    }

    if (_group!.turnOrder == TurnOrder.roundRobin) {
      return _characters[_turnIndex % _characters.length];
    }
    return _previewed; // random: decided at pick time unless picked ahead
  }

  CharacterCard? get _previewed =>
      _characters.where((c) => _getId(c) == _previewId).firstOrNull;

  /// Random turn order: make the next pick now (see [_previewId]). No-op for
  /// round robin or while a pick is already held.
  void previewRandomSpeaker() {
    if (!isActive || _characters.isEmpty) return;
    if (_group!.turnOrder != TurnOrder.random || _previewed != null) return;
    _previewId = _getId(_characters[Random().nextInt(_characters.length)]);
    notifyListeners();
  }

  /// Random turn order: hold [character] as the next pick.
  void previewSpeaker(CharacterCard character) {
    if (!isActive || _group!.turnOrder != TurnOrder.random) return;
    _previewId = _getId(character);
    notifyListeners();
  }

  /// Pick (and advance) the next speaker according to turn order.
  /// Consumes any forced override if present.
  CharacterCard pickNextSpeaker() {
    if (!isActive || _characters.isEmpty) {
      throw StateError('No active group');
    }

    // The chip queue goes first and is one-shot here: a hand pick (@,
    // /speak, bubble tap) has already cleared it, so at most one of the
    // two holds exists. The rotation carries on after the queued member,
    // as after any hand-picked turn. If the id is gone (member removed
    // mid-hold), the pick falls through to the normal order.
    if (_queuedSpeakerId != null) {
      final qIdx = _characters.indexWhere(
        (c) => _getId(c) == _queuedSpeakerId,
      );
      _queuedSpeakerId = null;
      if (qIdx >= 0) {
        if (_group!.turnOrder == TurnOrder.roundRobin) {
          _turnIndex = (qIdx + 1) % _characters.length;
        }
        notifyListeners();
        return _characters[qIdx];
      }
      notifyListeners();
    }

    // Forced override wins and is one-shot. A hand-picked turn is still a
    // turn: round robin carries on with whoever follows the speaker.
    if (_forcedNextSpeakerId != null) {
      final idx = _characters.indexWhere(
        (c) => _getId(c) == _forcedNextSpeakerId,
      );
      _forcedNextSpeakerId = null;
      if (idx >= 0 && _group!.turnOrder == TurnOrder.roundRobin) {
        _turnIndex = (idx + 1) % _characters.length;
      }
      notifyListeners();
      return _characters[idx >= 0 ? idx : 0];
    }

    if (_group!.turnOrder == TurnOrder.random) {
      final previewed = _previewed;
      _previewId = null;
      return previewed ?? _characters[Random().nextInt(_characters.length)];
    }

    // Round robin
    final char = _characters[_turnIndex % _characters.length];
    _turnIndex = (_turnIndex + 1) % _characters.length;
    notifyListeners();
    return char;
  }

  /// Manually force a specific character to speak next.
  /// Works for both random and round-robin, and in Director Mode.
  void setNextSpeaker(CharacterCard character) {
    if (!isActive) return;

    final idx = _characters.indexWhere((c) => c.name == character.name);
    if (idx >= 0) {
      _turnIndex = idx;
      _forcedNextSpeakerId = _getId(character);
      // The newest pick wins the single "who's next" seat.
      _queuedSpeakerId = null;
      notifyListeners();
    }
  }

  /// The chip's Next pill / Director cue: hold a member (full or lite —
  /// both are rotation rows) for the next turn. Keyed by row id, matched
  /// by id (a hand pick matches by name and drops lite guests whose row
  /// id differs; never both holds at once). The pointer stays put until
  /// the hold is consumed or cancelled — cancelling speaks the rotation
  /// as if nothing was queued.
  void queueSpeaker(CharacterCard character) {
    if (!isActive) return;
    final id = _getId(character);
    if (!_characters.any((c) => _getId(c) == id)) return;
    _queuedSpeakerId = id;
    _forcedNextSpeakerId = null;
    notifyListeners();
  }

  /// Cancel the chip queue (second tap on the filled NEXT pill).
  void clearQueuedSpeaker() {
    if (_queuedSpeakerId != null) {
      _queuedSpeakerId = null;
      notifyListeners();
    }
  }

  /// Clear any pending forced speaker.
  void clearForcedSpeaker() {
    if (_forcedNextSpeakerId != null) {
      _forcedNextSpeakerId = null;
      notifyListeners();
    }
  }

  /// Advance the round-robin turn pointer (if applicable) as if the given
  /// character has just completed their turn (an entrance, a `/speak`, or a
  /// member skipped as away). Not for regenerations: [beginRegeneration] and
  /// [endRegeneration] hold and put back the rotation there.
  /// Safe no-op for random turn order or non-round-robin groups.
  void advanceAfterRegeneration(CharacterCard character) {
    if (!isActive || _characters.isEmpty) return;
    if (_group!.turnOrder != TurnOrder.roundRobin) return;
    final idx = _characters.indexWhere((c) => c.name == character.name);
    if (idx < 0) return;
    _turnIndex = (idx + 1) % _characters.length;
    notifyListeners();
  }

  /// Force [character] to re-speak the reply being regenerated, remembering
  /// the rotation so [endRegeneration] can put it back: a regen redoes a
  /// turn, it does not take one.
  void beginRegeneration(CharacterCard character) {
    if (!isActive) return;
    final before = (
      index: _turnIndex,
      forcedId: _forcedNextSpeakerId,
      queuedId: _queuedSpeakerId,
    );
    setNextSpeaker(character);
    final regenId = _forcedNextSpeakerId;
    if (regenId == null) return;
    _regenHold ??= (
      index: before.index,
      forcedId: before.forcedId,
      regenId: regenId,
      queuedId: before.queuedId,
    );
  }

  /// Put the rotation back as [beginRegeneration] found it, whether the
  /// regen succeeded or not. A speaker picked during the regen stands.
  void endRegeneration() {
    final hold = _regenHold;
    _regenHold = null;
    if (hold == null || _forcedNextSpeakerId != hold.regenId) return;
    restoreRotation((
      index: hold.index,
      forcedId: hold.forcedId,
      previewId: _previewId,
      queuedId: hold.queuedId,
    ));
  }

  /// Where the rotation stands, for [restoreRotation].
  TurnRotation get rotation => (
    index: _turnIndex,
    forcedId: _forcedNextSpeakerId,
    previewId: _previewId,
    queuedId: _queuedSpeakerId,
  );

  /// Put back a [rotation] taken before a pick whose turn wrote no reply
  /// (stopped, refused or failed): that member is still up next.
  void restoreRotation(TurnRotation r) {
    _turnIndex = _characters.isEmpty ? 0 : r.index % _characters.length;
    _forcedNextSpeakerId = _characters.any((c) => _getId(c) == r.forcedId)
        ? r.forcedId
        : null;
    _previewId = r.previewId;
    _queuedSpeakerId = _characters.any((c) => _getId(c) == r.queuedId)
        ? r.queuedId
        : null;
    notifyListeners();
  }

  /// Resets the round-robin pointer and any forced speaker.
  /// Used when a new greeting is sent or the conversation is reset.
  void resetTurnState() {
    _turnIndex = 0;
    _forcedNextSpeakerId = null;
    _queuedSpeakerId = null;
    _previewId = null;
    _regenHold = null;
    notifyListeners();
  }

  // ── Lifecycle ──────────────────────────────────────────────────────────

  /// Enter group mode with the given definition and resolved characters.
  void enterGroup(
    GroupChat group,
    List<CharacterCard> resolvedCharacters, {
    bool startInDirectorMode = false,
  }) {
    _group = group;
    _characters = List.of(resolvedCharacters);
    _turnIndex = 0;
    _forcedNextSpeakerId = null;
    _queuedSpeakerId = null;
    _previewId = null;
    _regenHold = null;
    _observerMode = startInDirectorMode;
    _autoPlayActive = false;
    notifyListeners();
  }

  /// Leave group mode (returns to 1:1 or nothing).
  void leaveGroup() {
    _group = null;
    _characters = [];
    _turnIndex = 0;
    _forcedNextSpeakerId = null;
    _queuedSpeakerId = null;
    _previewId = null;
    _regenHold = null;
    _observerMode = false;
    _autoPlayActive = false;
    notifyListeners();
  }

  /// Swap one roster slot. [characters] is unmodifiable; writing through
  /// that getter throws. The chat editor saves onto this mutable list.
  void replaceCharacterAt(int index, CharacterCard card) {
    if (index < 0 || index >= _characters.length) return;
    _characters[index] = card;
  }

  /// Re-resolve the character list after the character repository changes
  /// (add/remove/rename). The upcoming round-robin speaker keeps the turn
  /// when still present (a member leaving ahead of them must not skip them);
  /// otherwise the index is clamped. Drops a forced ID if its character is
  /// no longer present.
  void refreshCharacters(List<CharacterCard> newResolvedList) {
    final upcoming = _characters.isEmpty
        ? null
        : _characters[_turnIndex % _characters.length];
    _characters = List.of(newResolvedList);

    final kept = upcoming == null
        ? -1
        : _characters.indexWhere((c) => _sameMember(c, upcoming));
    if (kept >= 0) {
      _turnIndex = kept;
    } else if (_characters.isNotEmpty) {
      _turnIndex = _turnIndex % _characters.length;
    } else {
      _turnIndex = 0;
    }

    if (_forcedNextSpeakerId != null &&
        !_characters.any((c) => _getId(c) == _forcedNextSpeakerId)) {
      _forcedNextSpeakerId = null;
    }
    if (_queuedSpeakerId != null &&
        !_characters.any((c) => _getId(c) == _queuedSpeakerId)) {
      _queuedSpeakerId = null;
    }

    notifyListeners();
  }

  void setObserverMode(bool value) {
    if (_observerMode == value) return;
    _observerMode = value;
    if (!value) {
      _autoPlayActive = false;
    }
    notifyListeners();
  }

  void startAutoPlay() {
    if (!isActive || !_observerMode) return;
    _autoPlayActive = true;
    notifyListeners();
  }

  void stopAutoPlay() {
    if (_autoPlayActive) {
      _autoPlayActive = false;
      notifyListeners();
    }
  }

  // ── Internal helpers ───────────────────────────────────────────────────

  /// Group members carry their row id; avatar-less ones share an empty
  /// [_getId], so the row id is compared first.
  bool _sameMember(CharacterCard a, CharacterCard b) {
    if (a.dbId != null && b.dbId != null) return a.dbId == b.dbId;
    return _getId(a) == _getId(b);
  }

  String _getId(CharacterCard card) {
    if (card.imagePath != null) {
      return card.imagePath!.split('/').last.split('\\').last.split('.').first;
    }
    return card.name.replaceAll(RegExp(r'[^\w\s]'), '').replaceAll(' ', '_');
  }
}
