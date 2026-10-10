// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:front_porch_ai/models/models.dart';

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
  ({int index, String? forcedId, String regenId})? _regenHold;
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

  /// The character that will speak on the next generation (respects forced override).
  CharacterCard? get nextSpeaker {
    if (!isActive || _characters.isEmpty) return null;

    if (_forcedNextSpeakerId != null) {
      return _characters.firstWhere(
        (c) => _getId(c) == _forcedNextSpeakerId,
        orElse: () => _characters.first,
      );
    }

    if (_group!.turnOrder == TurnOrder.roundRobin) {
      return _characters[_turnIndex % _characters.length];
    }
    return null; // random decided at pick time
  }

  /// Pick (and advance) the next speaker according to turn order.
  /// Consumes any forced override if present.
  CharacterCard pickNextSpeaker() {
    if (!isActive || _characters.isEmpty) {
      throw StateError('No active group');
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
      return _characters[Random().nextInt(_characters.length)];
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
    final before = (index: _turnIndex, forcedId: _forcedNextSpeakerId);
    setNextSpeaker(character);
    final regenId = _forcedNextSpeakerId;
    if (regenId == null) return;
    _regenHold ??= (
      index: before.index,
      forcedId: before.forcedId,
      regenId: regenId,
    );
  }

  /// Put the rotation back as [beginRegeneration] found it, whether the
  /// regen succeeded or not. A speaker picked during the regen stands.
  void endRegeneration() {
    final hold = _regenHold;
    _regenHold = null;
    if (hold == null || _forcedNextSpeakerId != hold.regenId) return;
    restoreRotation((index: hold.index, forcedId: hold.forcedId));
  }

  /// Where the rotation stands, for [restoreRotation].
  ({int index, String? forcedId}) get rotation =>
      (index: _turnIndex, forcedId: _forcedNextSpeakerId);

  /// Put back a [rotation] taken before a pick whose turn wrote no reply
  /// (stopped, refused or failed): that member is still up next.
  void restoreRotation(({int index, String? forcedId}) r) {
    _turnIndex = _characters.isEmpty ? 0 : r.index % _characters.length;
    _forcedNextSpeakerId = _characters.any((c) => _getId(c) == r.forcedId)
        ? r.forcedId
        : null;
    notifyListeners();
  }

  /// Resets the round-robin pointer and any forced speaker.
  /// Used when a new greeting is sent or the conversation is reset.
  void resetTurnState() {
    _turnIndex = 0;
    _forcedNextSpeakerId = null;
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
