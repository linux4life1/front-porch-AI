// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Integration tests for the full character lifecycle:
// create → chat → edit → new chat → verify persistence.
//
// These tests combine CharacterCard, FrontPorchExtensions, and session
// management logic to validate end-to-end workflows that unit tests
// can't cover in isolation.

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/models/character_card.dart';

/// Simulates a minimal character lifecycle manager that ties together
/// character creation, chat session management, and state persistence.
class _CharacterLifecycleSimulator {
  CharacterCard? _currentCharacter;
  String? _currentSessionId;
  final List<String> _messageHistory = [];
  final Map<String, dynamic> _sessionState = {};
  int _affectionScore = 0;
  int _trustLevel = 0;
  String _characterEmotion = '';

  CharacterCard? get currentCharacter => _currentCharacter;
  String? get currentSessionId => _currentSessionId;
  List<String> get messageHistory => List.unmodifiable(_messageHistory);
  int get affectionScore => _affectionScore;
  int get trustLevel => _trustLevel;
  String get characterEmotion => _characterEmotion;

  // ── Create character ──────────────────────────────────────────────
  void createCharacter({
    required String name,
    String personality = '',
    String description = '',
    String firstMessage = '',
    String? imagePath,
    FrontPorchExtensions? extensions,
    String? dbId,
  }) {
    _currentCharacter = CharacterCard(
      name: name,
      personality: personality,
      description: description,
      firstMessage: firstMessage,
      imagePath: imagePath,
      frontPorchExtensions: extensions,
    )..dbId = dbId ?? 'char_${DateTime.now().millisecondsSinceEpoch}';
    _affectionScore = 0;
    _trustLevel = 0;
    _characterEmotion = '';
  }

  // ── Start chat ────────────────────────────────────────────────────
  void startChat() {
    if (_currentCharacter == null) return;

    _currentSessionId = 'session_${DateTime.now().millisecondsSinceEpoch}';
    _messageHistory.clear();

    // Seed from extensions if present
    if (_currentCharacter!.frontPorchExtensions != null) {
      final ext = _currentCharacter!.frontPorchExtensions!;
      _affectionScore = ext.shortTermBond.clamp(-300, 300);
      _trustLevel = ext.trustLevel.clamp(-100, 100);
      _characterEmotion = ext.characterEmotion;
    }

    // Add greeting
    if (_currentCharacter!.firstMessage.isNotEmpty) {
      _messageHistory.add(_currentCharacter!.firstMessage);
    }
  }

  // ── Simulate message exchange ─────────────────────────────────────
  void simulateMessageExchange({
    required String userMessage,
    required String characterResponse,
    int? bondDelta,
    int? trustDelta,
    String? emotion,
  }) {
    _messageHistory.add(userMessage);
    _messageHistory.add(characterResponse);

    if (bondDelta != null) {
      _affectionScore = (_affectionScore + bondDelta).clamp(-300, 300);
    }
    if (trustDelta != null) {
      _trustLevel = (_trustLevel + trustDelta).clamp(-100, 100);
    }
    if (emotion != null) {
      _characterEmotion = emotion;
    }
  }

  // ── Edit character ────────────────────────────────────────────────
  void editCharacter({
    String? personality,
    String? description,
    String? firstMessage,
    FrontPorchExtensions? extensions,
  }) {
    if (_currentCharacter == null) return;

    _currentCharacter = CharacterCard(
      name: _currentCharacter!.name,
      personality: personality ?? _currentCharacter!.personality,
      description: description ?? _currentCharacter!.description,
      firstMessage: firstMessage ?? _currentCharacter!.firstMessage,
      imagePath: _currentCharacter!.imagePath,
      frontPorchExtensions: extensions ?? _currentCharacter!.frontPorchExtensions,
    )..dbId = _currentCharacter!.dbId;
  }

  // ── Start new chat (refreshes from "repository") ──────────────────
  void startNewChat() {
    if (_currentCharacter == null) return;

    _currentSessionId = 'session_${DateTime.now().millisecondsSinceEpoch}';
    _messageHistory.clear();

    // Seed from extensions (preserves bond/trust for emotional continuity)
    if (_currentCharacter!.hasFrontPorchExtensions) {
      // Update extensions with current runtime state before seeding
      final existing = _currentCharacter!.frontPorchExtensions!;
      _currentCharacter!.frontPorchExtensions = FrontPorchExtensions(
        realismEnabled: existing.realismEnabled,
        shortTermBond: _affectionScore,
        longTermBond: existing.longTermBond,
        trustLevel: _trustLevel,
        dayCount: existing.dayCount,
        timeOfDay: existing.timeOfDay,
        characterEmotion: _characterEmotion,
        emotionIntensity: existing.emotionIntensity,
        nsfwCooldownEnabled: existing.nsfwCooldownEnabled,
        passageOfTimeEnabled: existing.passageOfTimeEnabled,
        chaosModeEnabled: existing.chaosModeEnabled,
        currentTask: existing.currentTask,
      );
      final ext = _currentCharacter!.frontPorchExtensions!;
      _affectionScore = ext.shortTermBond.clamp(-300, 300);
      _trustLevel = ext.trustLevel.clamp(-100, 100);
      _characterEmotion = ext.characterEmotion;
    } else {
      // No extensions — reset to defaults
      _affectionScore = 0;
      _trustLevel = 0;
      _characterEmotion = '';
    }

    // Add greeting
    if (_currentCharacter!.firstMessage.isNotEmpty) {
      _messageHistory.add(_currentCharacter!.firstMessage);
    }
  }

  // ── Duplicate character ───────────────────────────────────────────
  CharacterCard duplicateCharacter() {
    if (_currentCharacter == null) {
      throw StateError('No active character to duplicate');
    }

    final original = _currentCharacter!;
    final duplicate = CharacterCard(
      name: '${original.name} (Copy)',
      personality: original.personality,
      description: original.description,
      firstMessage: original.firstMessage,
      imagePath: original.imagePath,
      frontPorchExtensions: FrontPorchExtensions(
        realismEnabled: original.frontPorchExtensions?.realismEnabled ?? false,
        shortTermBond: original.frontPorchExtensions?.shortTermBond ?? 0,
        longTermBond: original.frontPorchExtensions?.longTermBond ?? 0,
        trustLevel: original.frontPorchExtensions?.trustLevel ?? 0,
        dayCount: original.frontPorchExtensions?.dayCount ?? 1,
        timeOfDay: original.frontPorchExtensions?.timeOfDay ?? 'morning',
        characterEmotion: original.frontPorchExtensions?.characterEmotion ?? '',
        emotionIntensity:
            original.frontPorchExtensions?.emotionIntensity ?? '',
        nsfwCooldownEnabled:
            original.frontPorchExtensions?.nsfwCooldownEnabled ?? false,
        passageOfTimeEnabled:
            original.frontPorchExtensions?.passageOfTimeEnabled ?? true,
        chaosModeEnabled:
            original.frontPorchExtensions?.chaosModeEnabled ?? false,
        currentTask: original.frontPorchExtensions?.currentTask ?? '',
      ),
    )..dbId = 'char_${DateTime.now().millisecondsSinceEpoch}';

    return duplicate;
  }

  // ── Toggle realism ────────────────────────────────────────────────
  bool get realismEnabled =>
      _currentCharacter?.frontPorchExtensions?.realismEnabled ?? false;
  void toggleRealism(bool enabled) {
    if (_currentCharacter == null) return;
    final existing = _currentCharacter!.frontPorchExtensions ??
        FrontPorchExtensions();
    _currentCharacter!.frontPorchExtensions = FrontPorchExtensions(
      realismEnabled: enabled,
      shortTermBond: existing.shortTermBond,
      longTermBond: existing.longTermBond,
      trustLevel: existing.trustLevel,
      dayCount: existing.dayCount,
      timeOfDay: existing.timeOfDay,
      characterEmotion: existing.characterEmotion,
      emotionIntensity: existing.emotionIntensity,
      nsfwCooldownEnabled: existing.nsfwCooldownEnabled,
      passageOfTimeEnabled: existing.passageOfTimeEnabled,
      chaosModeEnabled: existing.chaosModeEnabled,
      currentTask: existing.currentTask,
    );
  }

  // ── Serialize/deserialize session state (simulates DB persistence) ─
  Map<String, dynamic> serializeSession() {
    return {
      'sessionId': _currentSessionId,
      'affectionScore': _affectionScore,
      'trustLevel': _trustLevel,
      'characterEmotion': _characterEmotion,
      'messageCount': _messageHistory.length,
      'characterDbId': _currentCharacter?.dbId,
      'characterName': _currentCharacter?.name,
      'characterPersonality': _currentCharacter?.personality,
      'extensions': _currentCharacter?.frontPorchExtensions?.toJson(),
    };
  }

  void deserializeSession(Map<String, dynamic> state) {
    _currentSessionId = state['sessionId'];
    _affectionScore = state['affectionScore'] ?? 0;
    _trustLevel = state['trustLevel'] ?? 0;
    _characterEmotion = state['characterEmotion'] ?? '';

    // Reconstruct character from serialized data
    final name = state['characterName'] ?? 'Unknown';
    final personality = state['characterPersonality'] ?? '';
    final dbId = state['characterDbId'] ?? '';

    _currentCharacter = CharacterCard(
      name: name,
      personality: personality,
    )..dbId = dbId;

    if (state['extensions'] != null) {
      _currentCharacter!.frontPorchExtensions =
          FrontPorchExtensions.fromJson(state['extensions']);
    }
  }
}

void main() {
  // ─── 4.1: Character Lifecycle Integration ──────────────────────────

  group('Character Lifecycle Integration', () {
    test('full lifecycle: create → chat → edit → new chat', () {
      final sim = _CharacterLifecycleSimulator();

      // 1. Create character
      sim.createCharacter(
        name: 'Luna',
        personality: 'Shy and reserved',
        description: 'A timid elf mage',
        firstMessage: 'H-hello... nice to meet you.',
        extensions: FrontPorchExtensions(
          realismEnabled: true,
          shortTermBond: 0,
          trustLevel: 0,
        ),
        dbId: 'char-luna',
      );
      expect(sim.currentCharacter!.name, 'Luna');
      expect(sim.currentCharacter!.personality, 'Shy and reserved');

      // 2. Start chat
      sim.startChat();
      expect(sim.currentSessionId, isNotNull);
      expect(sim.messageHistory, isNotEmpty);
      expect(sim.messageHistory.first, 'H-hello... nice to meet you.');

      // 3. Simulate message exchange (build bond)
      sim.simulateMessageExchange(
        userMessage: 'Hi Luna! I like your magic.',
        characterResponse: '*blushes* T-thank you...',
        bondDelta: 5,
        trustDelta: 3,
        emotion: 'happy',
      );
      expect(sim.affectionScore, 5);
      expect(sim.trustLevel, 3);
      expect(sim.characterEmotion, 'happy');

      // 4. Edit character (change personality)
      sim.editCharacter(personality: 'Bold and confident');
      expect(sim.currentCharacter!.personality, 'Bold and confident');

      // 5. Start new chat
      sim.startNewChat();
      expect(sim.currentSessionId, isNotNull);
      expect(sim.messageHistory, isNotEmpty);

      // 6. Verify personality is updated (refreshed from "repository")
      expect(sim.currentCharacter!.personality, 'Bold and confident',
          reason: 'new chat must pick up personality edits');

      // 7. Verify bond is preserved (from extensions)
      expect(sim.affectionScore, 5,
          reason: 'bond must be preserved across chat sessions');
    });

    test('duplicate → chat preserves realism settings', () {
      final sim = _CharacterLifecycleSimulator();

      // Create character with realism enabled and existing bond
      sim.createCharacter(
        name: 'Kael',
        personality: 'Cunning rogue',
        firstMessage: 'What do you want?',
        extensions: FrontPorchExtensions(
          realismEnabled: true,
          shortTermBond: 25,
          longTermBond: 20,
          trustLevel: 15,
          dayCount: 3,
          timeOfDay: 'evening',
        ),
        dbId: 'char-kael',
      );

      // Simulate some chat history
      sim.startChat();
      sim.simulateMessageExchange(
        userMessage: 'Let\'s talk.',
        characterResponse: 'Fine. What is it?',
        bondDelta: 5,
        trustDelta: 2,
      );

      // Duplicate the character
      final duplicate = sim.duplicateCharacter();
      expect(duplicate.name, 'Kael (Copy)');
      expect(duplicate.frontPorchExtensions, isNotNull);
      expect(duplicate.frontPorchExtensions!.realismEnabled, isTrue);
      expect(duplicate.frontPorchExtensions!.shortTermBond, 25);
      expect(duplicate.frontPorchExtensions!.trustLevel, 15);

      // Start chat with duplicate
      sim.createCharacter(
        name: duplicate.name,
        personality: duplicate.personality,
        firstMessage: duplicate.firstMessage,
        extensions: duplicate.frontPorchExtensions,
        dbId: duplicate.dbId,
      );
      sim.startChat();

      expect(sim.affectionScore, 25,
          reason: 'duplicated character must preserve bond score');
      expect(sim.trustLevel, 15,
          reason: 'duplicated character must preserve trust level');
      expect(sim.characterEmotion, '',
          reason: 'emotion should be empty for new chat with duplicate');
    });

    test('toggle realism off → on preserves state', () {
      final sim = _CharacterLifecycleSimulator();

      // Create and chat
      sim.createCharacter(
        name: 'Mira',
        personality: 'Cheerful',
        firstMessage: 'Hi there!',
        extensions: FrontPorchExtensions(
          realismEnabled: true,
          shortTermBond: 10,
          trustLevel: 5,
        ),
        dbId: 'char-mira',
      );
      sim.startChat();
      sim.simulateMessageExchange(
        userMessage: 'Hello!',
        characterResponse: 'Hey!',
        bondDelta: 5,
        emotion: 'excited',
      );

      final savedAffection = sim.affectionScore;
      final savedTrust = sim.trustLevel;
      final savedEmotion = sim.characterEmotion;

      // Toggle realism off
      sim.toggleRealism(false);
      expect(sim.realismEnabled, isFalse);

      // State should still be accessible
      expect(sim.affectionScore, savedAffection,
          reason: 'affection must be preserved when realism is disabled');
      expect(sim.trustLevel, savedTrust,
          reason: 'trust must be preserved when realism is disabled');
      expect(sim.characterEmotion, savedEmotion,
          reason: 'emotion must be preserved when realism is disabled');

      // Toggle realism back on
      sim.toggleRealism(true);
      expect(sim.realismEnabled, isTrue);

      // All state must be restored
      expect(sim.affectionScore, savedAffection,
          reason: 'state must be restored when realism is re-enabled');
      expect(sim.trustLevel, savedTrust);
      expect(sim.characterEmotion, savedEmotion);
    });

    test('session serialization preserves all state', () {
      final sim = _CharacterLifecycleSimulator();

      sim.createCharacter(
        name: 'Aria',
        personality: 'Wise wizard',
        firstMessage: 'Greetings, traveler.',
        extensions: FrontPorchExtensions(
          realismEnabled: true,
          shortTermBond: 30,
          longTermBond: 25,
          trustLevel: 20,
          dayCount: 5,
          timeOfDay: 'afternoon',
          characterEmotion: 'content',
          emotionIntensity: 'mild',
        ),
        dbId: 'char-aria',
      );

      sim.startChat();
      sim.simulateMessageExchange(
        userMessage: 'Tell me a story.',
        characterResponse: 'Once upon a time...',
        bondDelta: 10,
        trustDelta: 5,
        emotion: 'nostalgic',
      );

      // Serialize
      final state = sim.serializeSession();
      expect(state['affectionScore'], 40);
      expect(state['trustLevel'], 25);
      expect(state['characterEmotion'], 'nostalgic');
      expect(state['messageCount'], 3); // greeting + user msg + character response
      expect(state['extensions'], isNotNull);

      // Deserialize into a fresh simulator
      final sim2 = _CharacterLifecycleSimulator();
      sim2.deserializeSession(state);

      expect(sim2.affectionScore, 40);
      expect(sim2.trustLevel, 25);
      expect(sim2.characterEmotion, 'nostalgic');
    });

    test('character without extensions starts fresh each chat', () {
      final sim = _CharacterLifecycleSimulator();

      sim.createCharacter(
        name: 'Rogue',
        personality: 'Mysterious',
        firstMessage: '...',
        extensions: null, // No extensions
        dbId: 'char-rogue',
      );

      sim.startChat();
      sim.simulateMessageExchange(
        userMessage: 'Hello.',
        characterResponse: '...',
        bondDelta: 10,
      );

      expect(sim.affectionScore, 10);

      // Start new chat without extensions → bond resets
      sim.startNewChat();

      expect(sim.affectionScore, 0,
          reason: 'bond must reset when character has no extensions');
    });
  });
}
