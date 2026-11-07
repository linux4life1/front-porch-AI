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
import 'package:front_porch_ai/services/chat/doors/cast/cast_deps.dart';
import 'package:front_porch_ai/services/chat/doors/turn/turn_engine.dart';

/// Group Away recovery: a quiet pulse for members who are Away, and at most
/// one spoken return per user send. At work never enters. 1:1 is a no-op.
/// The planner is the [AwayPulse] leaf; this runs its evals and keeps
/// [state].
class AwayPulseRunner {
  AwayPulseRunner(this._d);

  final CastDeps _d;

  /// The pulse's cadence and the pending return speaker.
  final AwayPulseState state = AwayPulseState();

  ChatSessionState get _session => _d.session;
  CastShellHooks get _h => _d.hooks;
  TurnEngine get _turn => _d.turn();
  RealismScope get _scope => _d.realism();
  TimeService get _timeService => _scope.time();
  GroupRealismStore get _groupStore => _scope.groups;
  Map<String, GroupMemberRealism> get _groupRealism => _groupStore.members;
  GroupChat? get _activeGroup => _session.activeGroup;
  List<CharacterCard> get _groupCharacters => _session.groupCharacters;

  /// Quiet glance for Away members, then at most one return-speak.
  /// [fromUserSend] always pulses; otherwise the N=3 present-speaker
  /// cadence. Quiet true does not write `withUser` — that waits for a
  /// spoken reply (or stays false on cancel/empty).
  Future<void> runAwayPulse({
    required String userText,
    required bool fromUserSend,
  }) async {
    if (_activeGroup == null) return;
    if (!_scope.realismEnabled()) return;
    if (fromUserSend) {
      state.beginUserSend(userText);
    } else if (state.lastUserText.isEmpty) {
      state.lastUserText = userText;
    }
    if (!AwayPulse.shouldPulse(
      fromUserSend: fromUserSend,
      presentSpeakerTurns: state.presentSpeakerTurns,
      nobodyPresent: _groupCharacters.every(
        _d.send().speakers.groupSpeakerSkips,
      ),
    )) {
      return;
    }

    PresenceWhere presenceOf(CharacterCard card) {
      final work = _d.send().speakers.workFieldsFor(card);
      return derivePresence(
        occupation: work.occupation,
        hours: work.hours,
        clockMinutes: _timeService.clockMinutes,
        weekday: _timeService.clock.weekday,
        workDays: work.workDays,
        inScene: _d.send().speakers.memberInScene(card),
      );
    }

    final text = userText.trim().isEmpty ? state.lastUserText : userText;
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
      isHeld: (c) => _groupRealism[_d.characterIdFor(c)]?.awayHeld ?? false,
    );
    final userName = _d.personas.persona.name.trim();
    final exchange = recentExchange(_session.messages);
    final eval = _d.judges().makeWithUserEval();
    final flipped = <({String id, int lastSpokeIndex})>[];

    for (final card in targets) {
      final id = _d.characterIdFor(card);
      final verdict = await eval.detectQuiet(
        charName: card.name,
        userName: userName.isEmpty ? 'the user' : userName,
        recentExchange: exchange,
        stance: _groupRealism[id]?.spatialStance ?? '',
        directing: _h.directing(),
      );
      debugPrint('[Presence] away-pulse ${card.name}=$verdict');
      if (verdict == true) {
        flipped.add((id: id, lastSpokeIndex: _lastSpokeIndex(card.name)));
      }
    }

    final pick = AwayPulse.pickReturnSpeak(
      addressedAwayId: addressed == null ? null : _d.characterIdFor(addressed),
      flippedTrueOldestFirst: AwayPulse.orderOldestAway(flipped),
      // The cap is per user send: a cadence / all-Away pulse after it must
      // still bring one back, or Director Mode (notes are the sends) stalls.
      alreadyUsedThisSend: fromUserSend && state.returnSpeakUsedThisUserSend,
    );
    final forcedPresent = _session.groupManager?.hasForcedSpeaker ?? false;
    if (pick != null && !forcedPresent) {
      state.pendingReturnSpeakId = pick;
      state.pendingReturnForcedByAt =
          addressed != null && pick == _d.characterIdFor(addressed);
      if (fromUserSend) state.returnSpeakUsedThisUserSend = true;
    }
  }

  /// A line that is only `@Name` runs as `/speak` (no user bubble), but
  /// it is still the user's send: pulse exactly as `@Name hi` would, and
  /// when that makes [card] this send's Away return, the forced turn
  /// consumes it the way the picker would have.
  Future<void> pulseBeforeBareAddress(CharacterCard card, String typed) async {
    await runAwayPulse(userText: typed, fromUserSend: true);
    if (state.pendingReturnSpeakId == _d.characterIdFor(card)) {
      state.consumingReturnSpeak = true;
    }
  }

  /// Where a group member is right now: the same read the turn picker
  /// skips on. Null outside a group or for a name not in the roster.
  PresenceWhere? groupMemberPresence(String memberId) {
    if (_activeGroup == null) return null;
    for (final card in _groupCharacters) {
      if (_d.characterIdFor(card) != memberId) continue;
      final work = _d.send().speakers.workFieldsFor(card);
      return derivePresence(
        occupation: work.occupation,
        hours: work.hours,
        clockMinutes: _timeService.clockMinutes,
        weekday: _timeService.clock.weekday,
        workDays: work.workDays,
        inScene: _d.send().speakers.memberInScene(card),
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
    if (_activeGroup == null || _turn.isTurnBusy) return false;
    if (!_groupCharacters.any((c) => _d.characterIdFor(c) == memberId)) {
      return false;
    }
    final slot = _groupStore.memberForWrite(memberId);
    slot.awayHeld = away;
    slot.withUser = !away;
    if (!away && state.pendingReturnSpeakId == memberId) {
      state.pendingReturnSpeakId = null;
    }
    debugPrint('[Presence] manual ${away ? 'away' : 'back'} $memberId');
    await _d.saveChat();
    _d.notify();
    return true;
  }

  /// The user's own `@Name` or `/speak` of a member they set Away is their
  /// Back: the hold lifts and they reply. A model Away is left alone — the
  /// glance after their reply decides that one.
  void releaseHeldAway(CharacterCard card) {
    final id = _d.characterIdFor(card);
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
