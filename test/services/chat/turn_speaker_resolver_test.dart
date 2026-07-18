// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Guards the per-turn realism speaker resolution (ChatService
// ._getCurrentSpeakerIdForRealism, group branch).
//
// The bug this locks down: that resolver used to derive "who is speaking right
// now" from GroupTurnManager.nextSpeaker. But nextSpeaker is the *upcoming*
// speaker — after a round-robin pick the turn pointer has already advanced, so
// during the current speaker's turn it points at the NEXT member; and for random
// turn order it is null (the speaker is chosen at pick time). That made the old
// resolver feed realism/needs/prompt-injection the WRONG member (the next one,
// or — for random — always the first/primary). The fix pins the speaker the
// moment they are picked in _generateResponse and clears it when the turn ends,
// and the resolver prefers that pin.
//
// Pattern matches the rest of the suite: drive the REAL GroupTurnManager and a
// faithful replica of the resolver's group branch (the real method is private),
// using the card name as the id proxy.

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/models/character_card.dart';
import 'package:front_porch_ai/models/group_chat.dart';
import 'package:front_porch_ai/services/group_turn_manager.dart';

CharacterCard _card(String name) => CharacterCard(name: name);

GroupChat _group({TurnOrder order = TurnOrder.roundRobin}) =>
    GroupChat(id: 'g1', name: 'Test Group', turnOrder: order);

/// Faithful replica of ChatService._getCurrentSpeakerIdForRealism's group branch
/// (keyed on name here instead of stableGroupId). Prefer the per-turn pin; fall
/// back to the upcoming speaker (round-robin), then the first member.
String resolve(GroupTurnManager mgr, List<CharacterCard> members, String? pin) {
  if (pin != null && members.any((c) => c.name == pin)) return pin;
  final next = mgr.nextSpeaker;
  if (next != null) return next.name;
  return members.first.name;
}

void main() {
  group('per-turn realism speaker resolution', () {
    final members = [_card('Alice'), _card('Bob'), _card('Cara')];

    test('ROOT CAUSE (round-robin): after a pick, nextSpeaker is the NEXT '
        'member, not the one currently speaking', () {
      final mgr = GroupTurnManager()..enterGroup(_group(), members);
      final speaking = mgr.pickNextSpeaker(); // Alice speaks; pointer advances
      expect(speaking.name, 'Alice');
      expect(mgr.nextSpeaker?.name, 'Bob',
          reason: 'nextSpeaker is the upcoming speaker — using it as "current" '
              'mis-keyed realism to the next member');
    });

    test('ROOT CAUSE (random): nextSpeaker is null, so the old resolver fell '
        'back to the first/primary member', () {
      final mgr = GroupTurnManager()
        ..enterGroup(_group(order: TurnOrder.random), members);
      expect(mgr.nextSpeaker, isNull);
      // Unpinned random resolves to the first member — the bug the user saw
      // (only the primary character's needs/affection ever moved).
      expect(resolve(mgr, members, null), 'Alice');
    });

    test('FIX: a pinned speaker is used regardless of turn order — round-robin '
        '(nextSpeaker points elsewhere)', () {
      final mgr = GroupTurnManager()..enterGroup(_group(), members);
      final speaking = mgr.pickNextSpeaker(); // Alice; pointer now at Bob
      expect(resolve(mgr, members, speaking.name), 'Alice',
          reason: 'the pin wins over nextSpeaker (which is Bob)');
    });

    test('FIX: a pinned speaker is used for random turn order too '
        '(nextSpeaker is null)', () {
      final mgr = GroupTurnManager()
        ..enterGroup(_group(order: TurnOrder.random), members);
      expect(resolve(mgr, members, 'Cara'), 'Cara',
          reason: 'the pin wins even though nextSpeaker is null — no more '
              'falling back to the primary');
    });

    test('unpinned (outside a turn) preserves prior behaviour: round-robin uses '
        'the upcoming speaker', () {
      final mgr = GroupTurnManager()..enterGroup(_group(), members);
      mgr.pickNextSpeaker(); // Alice; pointer at Bob
      expect(resolve(mgr, members, null), 'Bob');
    });

    test('a stale pin not in the roster is ignored (falls back)', () {
      final mgr = GroupTurnManager()..enterGroup(_group(), members);
      expect(resolve(mgr, members, 'Ghost'), 'Alice',
          reason: 'a pin for a departed member must not be returned');
    });
  });
}
