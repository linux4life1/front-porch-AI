// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Tests for the custom-entrance logic used when forking a 1:1 chat into a
// group: the one-shot forced-speaker override (so the newly added character
// delivers their entrance regardless of turn order) and the verbatim entrance
// seeding (your text becomes the start of their first message).

import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/models/character_card.dart';
import 'package:front_porch_ai/services/chat_service.dart';

enum _Order { roundRobin, random }

// ── Stub: mirrors the group turn-selection + entrance seeding in ChatService ──
class _GroupTurnStub {
  final List<CharacterCard> groupCharacters;
  _Order turnOrder;
  int turnIndex = 0;
  CharacterCard? forcedNextSpeaker;
  final List<ChatMessage> messages = [];

  _GroupTurnStub(this.groupCharacters, {this.turnOrder = _Order.roundRobin});

  // Mirrors ChatService._pickNextGroupCharacter (with forced-speaker override).
  CharacterCard pickNextGroupCharacter() {
    if (forcedNextSpeaker != null) {
      final forced = forcedNextSpeaker!;
      forcedNextSpeaker = null;
      final idx = groupCharacters.indexWhere((c) => c.name == forced.name);
      if (idx >= 0) {
        turnIndex = idx + 1; // keep round-robin aligned after the entrance
        return groupCharacters[idx];
      }
      return forced;
    }
    if (turnOrder == _Order.random) {
      return groupCharacters[Random().nextInt(groupCharacters.length)];
    }
    final char = groupCharacters[turnIndex % groupCharacters.length];
    turnIndex++;
    return char;
  }

  // Mirrors the verbatim entrance seeding in ChatService.forkToGroupChat.
  void seedVerbatimEntrance(CharacterCard newChar, String entrance) {
    messages.add(
      ChatMessage(
        text: '${entrance.trim()}\n\n',
        sender: newChar.name,
        isUser: false,
        characterId: newChar.name,
      ),
    );
  }
}

CharacterCard _card(String name) => CharacterCard(name: name);

void main() {
  group('Group entrance — forced-speaker override', () {
    test('round robin cycles through characters in order', () {
      final a = _card('Alice'), b = _card('Bob'), c = _card('Cara');
      final stub = _GroupTurnStub([a, b, c]);

      expect(stub.pickNextGroupCharacter().name, 'Alice');
      expect(stub.pickNextGroupCharacter().name, 'Bob');
      expect(stub.pickNextGroupCharacter().name, 'Cara');
      expect(stub.pickNextGroupCharacter().name, 'Alice');
    });

    test('forced speaker overrides round robin', () {
      final a = _card('Alice'), b = _card('Bob'), c = _card('Cara');
      final stub = _GroupTurnStub([a, b, c]);

      // Round robin would pick Alice (turnIndex 0), but we force Cara.
      stub.forcedNextSpeaker = c;
      expect(stub.pickNextGroupCharacter().name, 'Cara',
          reason: 'forced speaker must win over the round-robin index');
    });

    test('forced speaker overrides random order', () {
      final a = _card('Alice'), b = _card('Bob'), c = _card('Cara');
      final stub = _GroupTurnStub([a, b, c], turnOrder: _Order.random);

      stub.forcedNextSpeaker = b;
      // Forced returns before the RNG branch, so this is deterministic.
      expect(stub.pickNextGroupCharacter().name, 'Bob',
          reason: 'forced speaker must win over random selection');
    });

    test('forced speaker is one-shot — normal order resumes after', () {
      final a = _card('Alice'), b = _card('Bob'), c = _card('Cara');
      final stub = _GroupTurnStub([a, b, c]);

      stub.forcedNextSpeaker = c;
      expect(stub.pickNextGroupCharacter().name, 'Cara');

      // Override consumed; round robin continues from Cara's index + 1 (wraps to Alice).
      expect(stub.forcedNextSpeaker, isNull);
      expect(stub.pickNextGroupCharacter().name, 'Alice');
      expect(stub.pickNextGroupCharacter().name, 'Bob');
    });

    test('forced speaker realigns the round-robin index to after itself', () {
      final a = _card('Alice'), b = _card('Bob'), c = _card('Cara');
      final stub = _GroupTurnStub([a, b, c]);

      stub.forcedNextSpeaker = b; // index 1
      stub.pickNextGroupCharacter();
      expect(stub.turnIndex, 2,
          reason: 'turnIndex should be forced index + 1');
    });
  });

  group('Group entrance — verbatim seeding', () {
    test('seeds the new character\'s first message with the entrance text', () {
      final stub = _GroupTurnStub([_card('Alice')]);
      final newChar = _card('Bob');

      stub.seedVerbatimEntrance(newChar, 'A new person enters the room.');

      expect(stub.messages.length, 1);
      final msg = stub.messages.single;
      expect(msg.sender, 'Bob');
      expect(msg.isUser, isFalse);
      expect(msg.characterId, 'Bob');
      expect(msg.text, startsWith('A new person enters the room.'));
    });

    test('separates setup and response with a blank line', () {
      final stub = _GroupTurnStub([_card('Alice')]);

      stub.seedVerbatimEntrance(_card('Bob'), 'A new person enters.');

      expect(stub.messages.single.text, endsWith('\n\n'),
          reason: 'trailing blank line keeps the response off the setup line');
    });
  });
}
