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
    );
    final userName = _userPersonaService.persona.name.trim();
    final exchange = recentExchange(_messages);
    final eval = _makeWithUserEval();
    final flipped = <({String id, int lastSpokeIndex})>[];

    for (final card in targets) {
      final id = _getCharacterIdFromCard(card);
      final verdict = await eval.detectQuiet(
        charName: card.name,
        userName: userName.isEmpty ? 'the user' : userName,
        recentExchange: exchange,
        stance: _groupRealism[id]?.spatialStance ?? '',
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
      alreadyUsedThisSend: _awayPulse.returnSpeakUsedThisUserSend,
    );
    final forcedPresent = _groupManager?.hasForcedSpeaker ?? false;
    if (pick != null && !forcedPresent) {
      _awayPulse.pendingReturnSpeakId = pick;
      _awayPulse.pendingReturnForcedByAt =
          addressed != null && pick == _getCharacterIdFromCard(addressed);
      if (fromUserSend) _awayPulse.returnSpeakUsedThisUserSend = true;
    }
  }

  int _lastSpokeIndex(String name) {
    var last = -1;
    for (var i = 0; i < _messages.length; i++) {
      final m = _messages[i];
      if (!m.isUser && m.sender == name) last = i;
    }
    return last;
  }
}
