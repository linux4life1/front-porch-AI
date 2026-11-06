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
import 'package:front_porch_ai/services/chat/doors/turn/turn_engine.dart';

import 'send_spine.dart';

/// Who speaks next in a group: the user's one-shot pick, the rotation, an
/// Away member's quiet return, and the members passed over because they are
/// Away or at work (their turn is a banner, [presenceSkipBanner]). 1:1
/// never skips. The turn engine, the cast door's Away pulse and guest
/// flow, the idle turn and the Next tooltip all read this one pick.
class GroupSpeakers {
  GroupSpeakers(this._s);

  final SendSpine _s;

  ChatSessionState get _session => _s.session;
  TurnEngine get turnEngine => _s.engine;
  GroupChat? get _activeGroup => _session.activeGroup;
  List<CharacterCard> get _groupCharacters => _session.groupCharacters;
  AwayPulseState get _awayPulse => _s.cast.away.state;
  TimeService get _timeService => _s.graph.time;
  Map<String, GroupMemberRealism> get _groupRealism => _s.graph.groups.members;
  bool get _isTurnBusy => turnEngine.isTurnBusy;
  String _getCharacterIdFromCard(CharacterCard card) => _s.characterIdFor(card);
  void notifyListeners() => _s.notify();

  /// Trigger the next character to speak in group mode.
  Future<void> triggerNextCharacter() async {
    if (_activeGroup == null || _groupCharacters.isEmpty || _isTurnBusy) {
      return;
    }
    // Bucket brigade: this speaker announces the time the last reply
    // decided, then post-decides for whoever speaks next.
    await turnEngine.generate(GenerationMode.normal);
  }

  /// Manually select which character speaks next in group mode.
  /// Delegated to GroupTurnManager.
  void setNextCharacter(CharacterCard character) {
    _session.groupManager?.setNextSpeaker(character);
    notifyListeners(); // ensure UI updates even if manager didn't notify

    // In group mode, switch the active objectives to this character's personal ones.
    if (_activeGroup != null) {
      _s.objectives.loadObjectivesForCurrentSpeaker();
    }
  }

  /// Pick which character speaks next based on turn order.
  /// A _forcedNextSpeakerId (set by manual user choice) is consumed first
  /// and works for both TurnOrder.random and roundRobin. After consumption
  /// we resume normal cycling / random behavior.
  CharacterCard _pickNextGroupCharacter() {
    if (_session.groupManager == null) {
      throw StateError('No active group');
    }
    return _session.groupManager!.pickNextSpeaker();
  }

  /// At work (and Away when we know they are not in scene). 1:1 never skips.
  /// A held member (the user's Away, or a chat that seeded "starts away")
  /// skips whenever their hold is on — Back is the only way back in.
  bool groupSpeakerSkips(CharacterCard card) {
    if (_activeGroup == null) return false;
    final work = workFieldsFor(card);
    final where = derivePresence(
      occupation: work.occupation,
      hours: work.hours,
      clockMinutes: _timeService.clockMinutes,
      weekday: _timeService.clock.weekday,
      workDays: work.workDays,
      heldAway: _groupRealism[_getCharacterIdFromCard(card)]?.awayHeld ?? false,
      inScene: memberInScene(card),
    );
    return groupTurnSkips(where);
  }

  /// Next member who is With you. A forced @name is not swapped. Random
  /// turn order must not re-roll the same At-work member and miss the
  /// only free one — walk the roster once.
  CharacterCard pickPresentGroupSpeaker() {
    // Forced / @ of a present member wins over a quiet Away return.
    // Serving pendingReturnSpeakId first stole @Bea when Ana flipped.
    final forced = _session.groupManager?.hasForcedSpeaker ?? false;
    if (forced) {
      return _pickNextGroupCharacter();
    }
    final returnId = _awayPulse.pendingReturnSpeakId;
    if (returnId != null) {
      for (final card in _groupCharacters) {
        if (_getCharacterIdFromCard(card) == returnId) {
          _awayPulse.consumingReturnSpeak = true;
          _session.groupManager?.advanceAfterRegeneration(card);
          return card;
        }
      }
    }
    final first = _pickNextGroupCharacter();
    final present = _presentFrom(first);
    if (present == null || identical(present, first)) return first;
    _session.groupManager?.advanceAfterRegeneration(present);
    return present;
  }

  /// Who [pickPresentGroupSpeaker] will pick, without taking the turn.
  /// The Next tooltip, sidebar badge and web cast chip read this, so they
  /// name the member who actually speaks.
  CharacterCard? get upcomingGroupSpeaker {
    final manager = _session.groupManager;
    if (manager == null || !manager.isActive) return null;
    final head = manager.nextSpeaker;
    if (manager.hasForcedSpeaker) return head;
    final returnId = _awayPulse.pendingReturnSpeakId;
    if (returnId != null) {
      for (final card in _groupCharacters) {
        if (_getCharacterIdFromCard(card) == returnId) return card;
      }
    }
    if (head == null) return null;
    return _presentFrom(head) ?? head;
  }

  /// First member With you walking the rotation from [head]: the member
  /// after a skipped one, not the roster's first (that parked the rotation
  /// on the skipped member and starved everyone behind them). Null when
  /// the whole roster skips.
  CharacterCard? _presentFrom(CharacterCard head) {
    final cast = _groupCharacters;
    final start = cast.indexWhere((c) => identical(c, head));
    if (start < 0) return groupSpeakerSkips(head) ? null : head;
    for (var i = 0; i < cast.length; i++) {
      final card = cast[(start + i) % cast.length];
      if (!groupSpeakerSkips(card)) return card;
    }
    return null;
  }

  /// The banner a skipped member's turn writes.
  String presenceSkipBanner(CharacterCard card) {
    final work = workFieldsFor(card);
    final where = derivePresence(
      occupation: work.occupation,
      hours: work.hours,
      clockMinutes: _timeService.clockMinutes,
      weekday: _timeService.clock.weekday,
      workDays: work.workDays,
      heldAway: _groupRealism[_getCharacterIdFromCard(card)]?.awayHeld ?? false,
      inScene: memberInScene(card),
    );
    if (where == PresenceWhere.atWork) {
      final range = parseWorkHoursRange(work.hours);
      final until = range == null
          ? ''
          : ' until ${StoryClock.formatClock(DateTime.utc(2000, 1, 1, range.$2 ~/ 60, range.$2 % 60))}';
      final job = work.occupation.trim();
      return '${card.name} is at work${job.isEmpty ? '' : ' as a $job'}$until.';
    }
    return '${card.name} is away.';
  }

  /// A member's job, hours and work days from their library card.
  WorkFields workFieldsFor(CharacterCard card) => workFieldsForMember(
    card,
    _s.deps.services.characters()?.characters ?? const <CharacterCard>[],
  );

  /// Skip path only. 1:1 never skips (caller returns false first).
  /// Group: judge bit, else recent line, or stance that does not say they left.
  bool memberInScene(CharacterCard card) {
    if (_activeGroup == null) return true;
    final id = _getCharacterIdFromCard(card);
    final judged = _groupRealism[id]?.withUser;
    if (judged != null) return judged;
    var seen = 0;
    for (final m in _session.messages.reversed) {
      if (m.isUser) continue;
      if (m.sender == card.name) return true;
      if (++seen >= 8) break;
    }
    final stance = _groupRealism[id]?.spatialStance ?? '';
    return !stanceSaysAway(stance);
  }
}
