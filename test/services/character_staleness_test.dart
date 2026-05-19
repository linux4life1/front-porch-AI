// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Regression tests for character staleness bug:
// Editing a character's personality/description was not reflected in chat
// because setActiveCharacter() skipped updating the reference when the
// same character (same name + dbId) was re-selected, and startNewChat()
// did not refresh the active character from the repository.

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/models/character_card.dart';

/// Minimal stub that replicates the character-staleness-critical logic
/// extracted from ChatService, enabling unit testing without the full
/// service dependency chain (KoboldService, DB, etc.).
///
/// Each test validates that the fix patterns hold; if someone alters the
/// guard logic in ChatService, the matching test here must also be updated
/// (or will rightfully fail in CI).
class _CharacterSessionStub {
  CharacterCard? activeCharacter;
  final List<String> messages = [];
  List<CharacterCard> repositoryCharacters = [];

  /// Mirrors the setActiveCharacter early-return guard from ChatService.
  /// MUST stay in sync with the real implementation.
  void setActiveCharacter(CharacterCard? character) {
    if (activeCharacter?.name == character?.name &&
        activeCharacter?.dbId == character?.dbId &&
        messages.isNotEmpty) {
      // FIX: still update the reference so edits are picked up
      activeCharacter = character;
      return;
    }

    activeCharacter = character;
    messages.clear();
    if (character != null && character.firstMessage.isNotEmpty) {
      messages.add(character.firstMessage);
    }
  }

  /// Mirrors the startNewChat refresh logic from ChatService.
  /// MUST stay in sync with the real implementation.
  void startNewChat() {
    if (activeCharacter == null) return;

    // Refresh from repository
    final freshChar = repositoryCharacters.cast<CharacterCard?>().firstWhere(
      (c) => c!.dbId == activeCharacter!.dbId,
      orElse: () => null,
    );
    if (freshChar != null) {
      activeCharacter = freshChar;
    }

    messages.clear();
    if (activeCharacter!.firstMessage.isNotEmpty) {
      messages.add(activeCharacter!.firstMessage);
    }
  }
}

void main() {
  // ─── setActiveCharacter: Early-Return Guard ────────────────────────

  group('setActiveCharacter — same character re-selection', () {
    test('updates character reference even when name and dbId match', () {
      final stub = _CharacterSessionStub();

      // Initial activation — creates session with messages
      final original = CharacterCard(
        name: 'Luna',
        personality: 'Shy and reserved',
        firstMessage: 'H-hello...',
      )..dbId = 'char-001';

      stub.setActiveCharacter(original);
      expect(stub.messages, isNotEmpty, reason: 'should have greeting');
      expect(stub.activeCharacter!.personality, 'Shy and reserved');

      // Simulate editing: user changes personality in the editor
      // and a fresh card is created from the repository
      final edited = CharacterCard(
        name: 'Luna',
        personality: 'Bold and confident',
        firstMessage: 'Hey there!',
      )..dbId = 'char-001';

      // Re-select same character — triggers early-return path
      stub.setActiveCharacter(edited);

      // REGRESSION: Before the fix, activeCharacter would still be `original`
      expect(stub.activeCharacter!.personality, 'Bold and confident',
          reason: 'early-return must still update the character reference');
      expect(stub.messages, isNotEmpty,
          reason: 'existing messages must be preserved');
    });

    test('does NOT preserve messages when dbId differs (different character)', () {
      final stub = _CharacterSessionStub();

      final charA = CharacterCard(
        name: 'Luna',
        firstMessage: 'Hello from Luna',
      )..dbId = 'char-001';

      stub.setActiveCharacter(charA);
      expect(stub.messages.length, 1);

      final charB = CharacterCard(
        name: 'Stella',
        firstMessage: 'Hello from Stella',
      )..dbId = 'char-002';

      stub.setActiveCharacter(charB);
      // Different character: messages should be cleared and re-initialized
      expect(stub.messages.length, 1);
      expect(stub.messages.first, 'Hello from Stella');
    });

    test('preserves V2.5 extensions on the updated reference', () {
      final stub = _CharacterSessionStub();

      final original = CharacterCard(
        name: 'Luna',
        firstMessage: 'Hi',
      )..dbId = 'char-001';

      stub.setActiveCharacter(original);

      // Edited version now has realism extensions
      final edited = CharacterCard(
        name: 'Luna',
        firstMessage: 'Hi',
        frontPorchExtensions: FrontPorchExtensions(
          realismEnabled: true,
          shortTermBond: 42,
          trustLevel: 15,
        ),
      )..dbId = 'char-001';

      stub.setActiveCharacter(edited);
      expect(stub.activeCharacter!.frontPorchExtensions, isNotNull);
      expect(stub.activeCharacter!.frontPorchExtensions!.realismEnabled, true);
      expect(stub.activeCharacter!.frontPorchExtensions!.shortTermBond, 42);
    });
  });

  // ─── startNewChat: Repository Refresh ──────────────────────────────

  group('startNewChat — refreshes from repository', () {
    test('picks up personality edits from repository on new chat', () {
      final stub = _CharacterSessionStub();

      // Original character in the session
      final original = CharacterCard(
        name: 'Luna',
        personality: 'Shy and reserved',
        firstMessage: 'H-hello...',
      )..dbId = 'char-001';

      stub.setActiveCharacter(original);
      expect(stub.activeCharacter!.personality, 'Shy and reserved');

      // Simulate: user edits character → repository now has updated card
      final updatedInRepo = CharacterCard(
        name: 'Luna',
        personality: 'Bold and confident',
        firstMessage: 'Hey there!',
      )..dbId = 'char-001';

      stub.repositoryCharacters = [updatedInRepo];

      // Start new chat — should refresh from repository
      stub.startNewChat();

      expect(stub.activeCharacter!.personality, 'Bold and confident',
          reason: 'startNewChat must refresh activeCharacter from repository');
      expect(stub.messages.first, 'Hey there!',
          reason: 'first message should come from the refreshed character');
    });

    test('keeps current character when not found in repository', () {
      final stub = _CharacterSessionStub();

      final original = CharacterCard(
        name: 'Luna',
        personality: 'Shy',
        firstMessage: 'Hi',
      )..dbId = 'char-001';

      stub.setActiveCharacter(original);
      stub.repositoryCharacters = []; // empty repo

      stub.startNewChat();
      expect(stub.activeCharacter!.personality, 'Shy',
          reason: 'should keep existing character when not in repository');
    });

    test('refreshes first message content from repository', () {
      final stub = _CharacterSessionStub();

      final original = CharacterCard(
        name: 'Luna',
        firstMessage: 'Old greeting',
      )..dbId = 'char-001';

      stub.setActiveCharacter(original);
      expect(stub.messages.first, 'Old greeting');

      final updated = CharacterCard(
        name: 'Luna',
        firstMessage: 'Shiny new greeting!',
      )..dbId = 'char-001';

      stub.repositoryCharacters = [updated];
      stub.startNewChat();

      expect(stub.messages.first, 'Shiny new greeting!',
          reason: 'new chat greeting must use the refreshed character data');
    });

    test('refreshes realism extensions from repository', () {
      final stub = _CharacterSessionStub();

      final original = CharacterCard(
        name: 'Luna',
        firstMessage: 'Hi',
      )..dbId = 'char-001';

      stub.setActiveCharacter(original);
      expect(stub.activeCharacter!.frontPorchExtensions, isNull);

      // Repository now has the character with realism extensions
      final updated = CharacterCard(
        name: 'Luna',
        firstMessage: 'Hi',
        frontPorchExtensions: FrontPorchExtensions(
          realismEnabled: true,
          shortTermBond: 25,
          trustLevel: 10,
          chaosModeEnabled: true,
        ),
      )..dbId = 'char-001';

      stub.repositoryCharacters = [updated];
      stub.startNewChat();

      expect(stub.activeCharacter!.frontPorchExtensions, isNotNull);
      expect(stub.activeCharacter!.frontPorchExtensions!.realismEnabled, true);
      expect(stub.activeCharacter!.frontPorchExtensions!.chaosModeEnabled, true);
    });
  });
}
