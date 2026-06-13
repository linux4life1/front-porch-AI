// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Tests for the custom-entrance logic used when forking a 1:1 chat into a
// group. Each added character may have an optional entrance; entrants take a
// one-off "cut-in" turn (forced), and in round-robin the next turn falls to
// whoever follows the last entrant in the rotation (originals, then entrance
// arrivals, then silent arrivals). The turn-order half is owned by
// GroupTurnManager (ChatService.forkToGroupChat stores members in that rotation
// order and drives it via setNextSpeaker + advanceAfterRegeneration), so these
// exercise the real manager rather than a stub.

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/models/character_card.dart';
import 'package:front_porch_ai/models/chat_message.dart';
import 'package:front_porch_ai/models/group_chat.dart';
import 'package:front_porch_ai/services/group_turn_manager.dart';

CharacterCard _card(String name) => CharacterCard(name: name);

GroupChat _group({TurnOrder order = TurnOrder.roundRobin}) =>
    GroupChat(id: 'g1', name: 'Test Group', turnOrder: order);

void main() {
  group('Group entrance — forced entrance speaker', () {
    test('round robin cycles through characters in order', () {
      final mgr = GroupTurnManager()
        ..enterGroup(_group(), [_card('Alice'), _card('Bob'), _card('Cara')]);

      expect(mgr.pickNextSpeaker().name, 'Alice');
      expect(mgr.pickNextSpeaker().name, 'Bob');
      expect(mgr.pickNextSpeaker().name, 'Cara');
      expect(mgr.pickNextSpeaker().name, 'Alice');
    });

    test('forced entrance speaker overrides round robin', () {
      final cara = _card('Cara');
      final mgr = GroupTurnManager()
        ..enterGroup(_group(), [_card('Alice'), _card('Bob'), cara]);

      mgr.setNextSpeaker(cara); // round robin would pick Alice
      expect(mgr.pickNextSpeaker().name, 'Cara',
          reason: 'forced entrance speaker must win over the round-robin index');
    });

    test('forced entrance speaker overrides random order', () {
      final bob = _card('Bob');
      final mgr = GroupTurnManager()
        ..enterGroup(
          _group(order: TurnOrder.random),
          [_card('Alice'), bob, _card('Cara')],
        );

      mgr.setNextSpeaker(bob);
      expect(mgr.pickNextSpeaker().name, 'Bob',
          reason: 'forced entrance speaker must win over random selection');
    });
  });

  group('Group entrance — turn order after the cut-in', () {
    // Models what ChatService.forkToGroupChat does: members are stored in
    // rotation order [originals, entrance-arrivals (add order), silent-arrivals
    // (add order)]; each entrance arrival takes a forced turn; then the pointer
    // advances to just after the LAST entrant (advanceAfterRegeneration), so the
    // next turn is whoever falls after them in the rotation.

    test('one added character with an entrance: next wraps to the original', () {
      // 1:1 with Alice, fork in Bob (entrance). Rotation: [Alice, Bob].
      final alice = _card('Alice'), bob = _card('Bob');
      final mgr = GroupTurnManager()..enterGroup(_group(), [alice, bob]);

      mgr.setNextSpeaker(bob);
      expect(mgr.pickNextSpeaker().name, 'Bob'); // entrance turn
      mgr.advanceAfterRegeneration(bob); // advance past the last entrant

      expect(mgr.nextSpeaker?.name, 'Alice',
          reason: 'after Bob (last in rotation) it wraps to the original');
      expect(mgr.pickNextSpeaker().name, 'Alice');
      expect(mgr.pickNextSpeaker().name, 'Bob');
    });

    test('two entrances + one silent: next is the silent arrival after them',
        () {
      // The maintainer's example: original O, add A (entrance), B (no
      // entrance), C (entrance). Stored rotation = [O, A, C, B] (entrance
      // arrivals before the silent one). A and C take entrances; next is B.
      final o = _card('O'), a = _card('A'), b = _card('B'), c = _card('C');
      final mgr = GroupTurnManager()..enterGroup(_group(), [o, a, c, b]);

      mgr.setNextSpeaker(a);
      expect(mgr.pickNextSpeaker().name, 'A');
      mgr.setNextSpeaker(c);
      expect(mgr.pickNextSpeaker().name, 'C');

      mgr.advanceAfterRegeneration(c); // last entrant is C
      expect(mgr.nextSpeaker?.name, 'B',
          reason: 'B falls after C in the rotation [O, A, C, B]');
      expect(mgr.pickNextSpeaker().name, 'B');
      expect(mgr.pickNextSpeaker().name, 'O');
      expect(mgr.pickNextSpeaker().name, 'A');
      expect(mgr.pickNextSpeaker().name, 'C');
    });

    test('all entrances, no silent arrival: next wraps to the original', () {
      // O + A (entrance) + C (entrance). Rotation [O, A, C]; after C wraps to O.
      final o = _card('O'), a = _card('A'), c = _card('C');
      final mgr = GroupTurnManager()..enterGroup(_group(), [o, a, c]);

      mgr.setNextSpeaker(a);
      expect(mgr.pickNextSpeaker().name, 'A');
      mgr.setNextSpeaker(c);
      expect(mgr.pickNextSpeaker().name, 'C');

      mgr.advanceAfterRegeneration(c);
      expect(mgr.nextSpeaker?.name, 'O');
    });

    test('random mode: entrance forces the entrant, next stays random', () {
      final alice = _card('Alice'), bob = _card('Bob');
      final mgr = GroupTurnManager()
        ..enterGroup(_group(order: TurnOrder.random), [alice, bob]);

      mgr.setNextSpeaker(bob);
      expect(mgr.pickNextSpeaker().name, 'Bob'); // entrance still forced
      // forkToGroupChat skips the advance for random; next is decided at pick.
      expect(mgr.nextSpeaker, isNull,
          reason: 'random groups decide the next speaker at pick time');
    });
  });

  group('Group entrance — verbatim ("Opening line") contract', () {
    // Documents the message ChatService.forkToGroupChat builds for the verbatim
    // path: the entrance text becomes the character's message exactly as written
    // (attributed to them), with NO LLM generation/continuation.
    ChatMessage seed(CharacterCard newChar, String entrance) => ChatMessage(
          text: entrance.trim(),
          sender: newChar.name,
          isUser: false,
          characterId: newChar.name,
        );

    test('uses the entrance text verbatim as the character\'s message', () {
      final msg = seed(_card('Bob'), 'A new person enters the room.');

      expect(msg.sender, 'Bob');
      expect(msg.isUser, isFalse);
      expect(msg.text, 'A new person enters the room.',
          reason: 'Opening line is verbatim — no continuation appended');
    });
  });
}
