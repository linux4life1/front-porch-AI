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
// These drive the REAL GroupTurnManager, whose nextSpeaker is the trap the bug
// turned on. The resolver it feeds is now the public
// GroupRealismStore.currentSpeakerId (covered by member_switches_gates_test).

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/models/character_card.dart';
import 'package:front_porch_ai/models/group_chat.dart';
import 'package:front_porch_ai/services/group_turn_manager.dart';

CharacterCard _card(String name) => CharacterCard(name: name);

GroupChat _group({TurnOrder order = TurnOrder.roundRobin}) =>
    GroupChat(id: 'g1', name: 'Test Group', turnOrder: order);

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
    });
  });

  // A Chance Time spin in random turn order has to name who reacts before the
  // turn picks. It makes the next random pick ahead; that pick is not forced,
  // so an Away member coming back still takes the turn.
  group('a random pick made ahead', () {
    final members = [_card('Alice'), _card('Bob'), _card('Cara')];

    test('names the next speaker without forcing them, and the next random '
        'pick takes it', () {
      final mgr = GroupTurnManager()
        ..enterGroup(_group(order: TurnOrder.random), members);
      mgr.previewRandomSpeaker();
      final named = mgr.nextSpeaker;
      expect(named, isNotNull);
      expect(mgr.hasForcedSpeaker, isFalse);

      mgr.previewRandomSpeaker();
      expect(mgr.nextSpeaker, same(named), reason: 'a held pick stays put');
      expect(mgr.pickNextSpeaker(), same(named));
      expect(mgr.nextSpeaker, isNull, reason: 'the pick was used');
    });

    test('a hand-picked speaker still wins, and round robin ignores it', () {
      final mgr = GroupTurnManager()
        ..enterGroup(_group(order: TurnOrder.random), members);
      mgr.previewSpeaker(members[2]);
      mgr.setNextSpeaker(members[1]);
      expect(mgr.pickNextSpeaker().name, 'Bob');
      expect(mgr.pickNextSpeaker().name, 'Cara', reason: 'the held pick');

      final rr = GroupTurnManager()..enterGroup(_group(), members);
      rr.previewRandomSpeaker();
      rr.previewSpeaker(members[2]);
      expect(rr.nextSpeaker?.name, 'Alice');
    });

    test('a turn that wrote no reply puts the held pick back', () {
      final mgr = GroupTurnManager()
        ..enterGroup(_group(order: TurnOrder.random), members);
      mgr.previewSpeaker(members[1]);
      final before = mgr.rotation;
      expect(mgr.pickNextSpeaker().name, 'Bob');
      mgr.restoreRotation(before);
      expect(mgr.nextSpeaker?.name, 'Bob', reason: 'Bob is still up next');
    });

    test('a reset drops the held pick', () {
      final mgr = GroupTurnManager()
        ..enterGroup(_group(order: TurnOrder.random), members);
      mgr.previewSpeaker(members[1]);
      mgr.resetTurnState();
      expect(mgr.nextSpeaker, isNull);
    });
  });
}
