// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Group Away recovery. Quiet pulse + at most one spoken return per user
// send. At work never enters. 1:1 is a no-op.

part of '../chat_service.dart';

extension ChatServiceAwayPulse on ChatService {
  /// Quiet glance for Away members, then at most one return-speak.
  /// [fromUserSend] always pulses; otherwise the N=3 present-speaker
  /// cadence. Quiet true does not write `withUser` — that waits for a
  /// spoken reply (or stays false on cancel/empty).
  Future<void> _runAwayPulse({
    required String userText,
    required bool fromUserSend,
  }) async {
    if (_activeGroup == null) return;
    if (!_realismEnabled) return;
    if (fromUserSend) {
      _awayPulse.beginUserSend(userText);
    } else if (_awayPulse.lastUserText.isEmpty) {
      _awayPulse.lastUserText = userText;
    }
    if (!AwayPulse.shouldPulse(
      fromUserSend: fromUserSend,
      presentSpeakerTurns: _awayPulse.presentSpeakerTurns,
      nobodyPresent: _groupCharacters.every(_groupSpeakerSkips),
    )) {
      return;
    }

    PresenceWhere presenceOf(CharacterCard card) {
      final work = _workFieldsFor(card);
      return derivePresence(
        occupation: work.occupation,
        hours: work.hours,
        clockMinutes: _timeService.clockMinutes,
        weekday: _timeService.clock.weekday,
        workDays: work.workDays,
        inScene: _memberInScene(card),
      );
    }

    final text = userText.trim().isEmpty ? _awayPulse.lastUserText : userText;
    // `@Name` of Away is this user send only. Cadence / auto-play
    // must not re-force a return from lastUserText. Vocative without
    // `@` never forces — it only raises quiet priority.
    final addressed = fromUserSend
        ? AwayPulse.addressedAwayMember(
            roster: _groupCharacters,
            userText: text,
            presenceOf: presenceOf,
          )
        : null;
    final targets = AwayPulse.quietPulseTargets(
      roster: _groupCharacters,
      userText: text,
      presenceOf: presenceOf,
      isHeld: (c) =>
          _groupRealism[_getCharacterIdFromCard(c)]?.awayHeld ?? false,
    );
    final userName = _userPersonaService.persona.name.trim();
    final exchange = recentExchange(_session.messages);
    final eval = _realismJudges.makeWithUserEval();
    final flipped = <({String id, int lastSpokeIndex})>[];

    for (final card in targets) {
      final id = _getCharacterIdFromCard(card);
      final verdict = await eval.detectQuiet(
        charName: card.name,
        userName: userName.isEmpty ? 'the user' : userName,
        recentExchange: exchange,
        stance: _groupRealism[id]?.spatialStance ?? '',
        directing: _directing,
      );
      debugPrint('[Presence] away-pulse ${card.name}=$verdict');
      if (verdict == true) {
        flipped.add((id: id, lastSpokeIndex: _lastSpokeIndex(card.name)));
      }
    }

    final pick = AwayPulse.pickReturnSpeak(
      addressedAwayId: addressed == null
          ? null
          : _getCharacterIdFromCard(addressed),
      flippedTrueOldestFirst: AwayPulse.orderOldestAway(flipped),
      // The cap is per user send: a cadence / all-Away pulse after it must
      // still bring one back, or Director Mode (notes are the sends) stalls.
      alreadyUsedThisSend:
          fromUserSend && _awayPulse.returnSpeakUsedThisUserSend,
    );
    final forcedPresent = _session.groupManager?.hasForcedSpeaker ?? false;
    if (pick != null && !forcedPresent) {
      _awayPulse.pendingReturnSpeakId = pick;
      _awayPulse.pendingReturnForcedByAt =
          addressed != null && pick == _getCharacterIdFromCard(addressed);
      if (fromUserSend) _awayPulse.returnSpeakUsedThisUserSend = true;
    }
  }

  /// Where a group member is right now: the same read the turn picker
  /// skips on. Null outside a group or for a name not in the roster.
  PresenceWhere? groupMemberPresence(String memberId) {
    if (_activeGroup == null) return null;
    for (final card in _groupCharacters) {
      if (_getCharacterIdFromCard(card) != memberId) continue;
      final work = _workFieldsFor(card);
      return derivePresence(
        occupation: work.occupation,
        hours: work.hours,
        clockMinutes: _timeService.clockMinutes,
        weekday: _timeService.clock.weekday,
        workDays: work.workDays,
        inScene: _memberInScene(card),
      );
    }
    return null;
  }

  /// The user's own Away / Back for one group member. The user's choice
  /// beats the model: a held Away stays until Back, whatever the glance or
  /// quiet pulse says. Back puts them in the turn order now.
  /// False (nothing changed) outside a group, mid-turn, or for an id not
  /// in the roster.
  Future<bool> setGroupMemberAway(String memberId, {required bool away}) async {
    if (_activeGroup == null || _isTurnBusy) return false;
    if (!_groupCharacters.any((c) => _getCharacterIdFromCard(c) == memberId)) {
      return false;
    }
    final slot = _groupStore.memberForWrite(memberId);
    slot.awayHeld = away;
    slot.withUser = !away;
    if (!away && _awayPulse.pendingReturnSpeakId == memberId) {
      _awayPulse.pendingReturnSpeakId = null;
    }
    debugPrint('[Presence] manual ${away ? 'away' : 'back'} $memberId');
    await _saveChat();
    notifyListeners();
    return true;
  }

  /// The user's own `@Name` or `/speak` of a member they set Away is their
  /// Back: the hold lifts and they reply. A model Away is left alone — the
  /// glance after their reply decides that one.
  void _releaseHeldAway(CharacterCard card) {
    final id = _getCharacterIdFromCard(card);
    if (!(_groupRealism[id]?.awayHeld ?? false)) return;
    final slot = _groupStore.memberForWrite(id);
    slot.awayHeld = false;
    slot.withUser = true;
    debugPrint('[Presence] addressed back $id');
  }

  int _lastSpokeIndex(String name) {
    var last = -1;
    for (var i = 0; i < _session.messages.length; i++) {
      final m = _session.messages[i];
      if (!m.isUser && m.sender == name) last = i;
    }
    return last;
  }
}
