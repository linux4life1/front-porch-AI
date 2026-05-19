// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Tests for Realism Engine state seeding and reset logic extracted from ChatService.
// Covers how realism state is initialized from V2.5 card extensions and how it
// resets when switching characters or starting new chats.

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/models/character_card.dart';

/// Minimal stub that replicates the Realism Engine state fields and seeding/reset
/// logic from ChatService. This enables unit testing of the state transitions
/// without needing the full ChatService dependency chain.
class _RealismStateStub {
  // ── Realism Engine state (mirrors ChatService fields) ──────────────
  bool _realismEnabled = false;
  int _affectionScore = 0;
  int _longTermScore = 0;
  int _trustLevel = 0;
  int _dayCount = 1;
  String _timeOfDay = 'morning';
  String _characterEmotion = '';
  String _emotionIntensity = '';
  bool _nsfwCooldownEnabled = false;
  bool _passageOfTimeEnabled = true;
  bool _chaosModeEnabled = false;
  int _arousalLevel = 0;
  String _activeFixation = '';
  int _fixationLifespan = 0;
  int _relationshipTier = 0;
  int _longTermTier = 0;

  // ── Simulated storage service flag ─────────────────────────────────
  bool passageOfTimeDefault = true;

  // ── Getters (mirror ChatService) ───────────────────────────────────
  bool get realismEnabled => _realismEnabled;
  int get affectionScore => _affectionScore;
  int get longTermScore => _longTermScore;
  int get trustLevel => _trustLevel;
  int get dayCount => _dayCount;
  String get timeOfDay => _timeOfDay;
  String get characterEmotion => _characterEmotion;
  String get emotionIntensity => _emotionIntensity;
  bool get nsfwCooldownEnabled => _nsfwCooldownEnabled;
  bool get passageOfTimeEnabled => _passageOfTimeEnabled;
  bool get chaosModeEnabled => _chaosModeEnabled;
  int get arousalLevel => _arousalLevel;
  String get activeFixation => _activeFixation;
  int get fixationLifespan => _fixationLifespan;
  int get relationshipTier => _relationshipTier;
  int get longTermTier => _longTermTier;

  /// Mirrors the V2.5 extension seeding logic from ChatService.setActiveCharacter
  /// (lines 1073-1108).
  void seedFromExtensions(FrontPorchExtensions? ext) {
    if (ext == null) return;

    _realismEnabled = ext.realismEnabled;
    _affectionScore = ext.shortTermBond.clamp(-300, 300);
    _longTermScore = ext.longTermBond.clamp(-300, 300);
    _trustLevel = ext.trustLevel.clamp(-100, 100);
    _dayCount = ext.dayCount.clamp(1, 9999);
    _timeOfDay = ext.timeOfDay;
    _characterEmotion = ext.characterEmotion;
    _emotionIntensity = ext.emotionIntensity;
    _nsfwCooldownEnabled = ext.nsfwCooldownEnabled;
    _passageOfTimeEnabled = ext.passageOfTimeEnabled && passageOfTimeDefault;
    _chaosModeEnabled = ext.chaosModeEnabled;

    // Recalculate tiers from seeded scores
    _relationshipTier = _calculateTier(_affectionScore);
    _longTermTier = _calculateTier(_longTermScore);
  }

  /// Mirrors the realism state reset logic from ChatService.setActiveCharacter
  /// (lines 1057-1066).
  void resetRealismState() {
    _arousalLevel = 0;
    _fixationLifespan = 0;
    _activeFixation = '';
  }

  /// Mirrors the _calculateTier method from ChatService (21-tier system).
  int _calculateTier(int score) {
    final absScore = score.abs();
    if (absScore < 5) return 0;
    if (absScore < 15) return score > 0 ? 1 : -1;
    if (absScore < 30) return score > 0 ? 2 : -2;
    if (absScore < 50) return score > 0 ? 3 : -3;
    if (absScore < 80) return score > 0 ? 4 : -4;
    if (absScore < 120) return score > 0 ? 5 : -5;
    if (absScore < 160) return score > 0 ? 6 : -6;
    if (absScore < 200) return score > 0 ? 7 : -7;
    if (absScore < 250) return score > 0 ? 8 : -8;
    if (absScore < 300) return score > 0 ? 9 : -9;
    return score > 0 ? 10 : -10;
  }

  /// Migration: scale old scores (±150) to new range (±300)
  int _migrateShortTermScore(int rawScore) {
    if (rawScore.abs() <= 150) {
      return (rawScore * 2).clamp(-300, 300);
    }
    return rawScore;
  }

  int _migrateLongTermScore(int rawScore) {
    if (rawScore.abs() <= 150) {
      return (rawScore * 2).clamp(-300, 300);
    }
    return rawScore;
  }

  /// Simulates startNewChat seeding for 1:1 mode (lines 2144-2186).
  void seedForNewChat(CharacterCard character) {
    final extSeed = character.frontPorchExtensions ?? FrontPorchExtensions();

    _realismEnabled = extSeed.realismEnabled;
    _affectionScore = extSeed.shortTermBond.clamp(-300, 300);
    _longTermScore = extSeed.longTermBond.clamp(-300, 300);
    _trustLevel = extSeed.trustLevel.clamp(-100, 100);
    _dayCount = extSeed.dayCount.clamp(1, 9999);
    _timeOfDay = extSeed.timeOfDay;
    _characterEmotion = extSeed.characterEmotion;
    _emotionIntensity = extSeed.emotionIntensity;
    _nsfwCooldownEnabled = extSeed.nsfwCooldownEnabled;
    _passageOfTimeEnabled =
        extSeed.passageOfTimeEnabled && passageOfTimeDefault;
    _chaosModeEnabled = extSeed.chaosModeEnabled;

    // Preserve arousal/fixation if character has extensions
    if (character.hasFrontPorchExtensions) {
      // Preserved — don't reset
    } else {
      _arousalLevel = 0;
      _fixationLifespan = 0;
      _activeFixation = '';
    }

    if (_realismEnabled) {
      _relationshipTier = _calculateTier(_affectionScore);
      _longTermTier = _calculateTier(_longTermScore);
    }
  }
}

void main() {
  // ─── Realism State — seeding from V2.5 extensions ──────────────────

  group('seedFromExtensions', () {
    test('seeds realism enabled flag', () {
      final stub = _RealismStateStub();
      stub.seedFromExtensions(FrontPorchExtensions(realismEnabled: true));
      expect(stub.realismEnabled, isTrue);
    });

    test('seeds short-term bond score', () {
      final stub = _RealismStateStub();
      stub.seedFromExtensions(FrontPorchExtensions(shortTermBond: 30));
      expect(stub.affectionScore, 30);
    });

    test('seeds long-term bond score', () {
      final stub = _RealismStateStub();
      stub.seedFromExtensions(FrontPorchExtensions(longTermBond: 25));
      expect(stub.longTermScore, 25);
    });

    test('calculates tier for new system', () {
      final stub = _RealismStateStub();
      // Score 29 should be tier 2 in 21-tier system (threshold is < 30)
      expect(stub._calculateTier(29), 2);
      // Score 30 should be tier 3 (threshold is < 50)
      expect(stub._calculateTier(30), 3);
      // Score 150 should be tier 6 (threshold is < 160 for tier 6)
      expect(stub._calculateTier(150), 6);
      // Score 250 should be tier 9 (threshold is < 300 for tier 9)
      expect(stub._calculateTier(250), 9);
    });

    test('seeds trust level', () {
      final stub = _RealismStateStub();
      stub.seedFromExtensions(FrontPorchExtensions(trustLevel: 15));
      expect(stub.trustLevel, 15);
    });

    test('seeds day count', () {
      final stub = _RealismStateStub();
      stub.seedFromExtensions(FrontPorchExtensions(dayCount: 5));
      expect(stub.dayCount, 5);
    });

    test('seeds time of day', () {
      final stub = _RealismStateStub();
      stub.seedFromExtensions(FrontPorchExtensions(timeOfDay: 'evening'));
      expect(stub.timeOfDay, 'evening');
    });

    test('seeds character emotion', () {
      final stub = _RealismStateStub();
      stub.seedFromExtensions(
        FrontPorchExtensions(characterEmotion: 'happy', emotionIntensity: 'strong'),
      );
      expect(stub.characterEmotion, 'happy');
      expect(stub.emotionIntensity, 'strong');
    });

    test('seeds nsfw cooldown', () {
      final stub = _RealismStateStub();
      stub.seedFromExtensions(FrontPorchExtensions(nsfwCooldownEnabled: true));
      expect(stub.nsfwCooldownEnabled, isTrue);
    });

    test('seeds chaos mode', () {
      final stub = _RealismStateStub();
      stub.seedFromExtensions(FrontPorchExtensions(chaosModeEnabled: true));
      expect(stub.chaosModeEnabled, isTrue);
    });

    test('respects passage of time global setting', () {
      final stub = _RealismStateStub();
      stub.passageOfTimeDefault = false;
      stub.seedFromExtensions(FrontPorchExtensions(passageOfTimeEnabled: true));
      expect(stub.passageOfTimeEnabled, isFalse,
          reason: 'global setting overrides card setting');
    });

    test('clamps short-term bond to -300..300', () {
      final stub = _RealismStateStub();
      stub.seedFromExtensions(FrontPorchExtensions(shortTermBond: 400));
      expect(stub.affectionScore, 300);

      stub.seedFromExtensions(FrontPorchExtensions(shortTermBond: -400));
      expect(stub.affectionScore, -300);
    });

    test('clamps long-term bond to -300..300', () {
      final stub = _RealismStateStub();
      stub.seedFromExtensions(FrontPorchExtensions(longTermBond: 400));
      expect(stub.longTermScore, 300);
    });

    test('clamps trust level to -100..100', () {
      final stub = _RealismStateStub();
      stub.seedFromExtensions(FrontPorchExtensions(trustLevel: 150));
      expect(stub.trustLevel, 100);

      stub.seedFromExtensions(FrontPorchExtensions(trustLevel: -150));
      expect(stub.trustLevel, -100);
    });

    test('clamps day count to 1..9999', () {
      final stub = _RealismStateStub();
      stub.seedFromExtensions(FrontPorchExtensions(dayCount: 0));
      expect(stub.dayCount, 1);

      stub.seedFromExtensions(FrontPorchExtensions(dayCount: 10000));
      expect(stub.dayCount, 9999);
    });

    test('calculates relationship tier from bonded score', () {
      final stub = _RealismStateStub();
      stub.seedFromExtensions(FrontPorchExtensions(shortTermBond: 30));
      expect(stub.relationshipTier, 3,
          reason: 'score 30 => tier 3 (Amiable) since 30 >= 30 threshold');
    });

    test('calculates long-term tier from bonded score', () {
      final stub = _RealismStateStub();
      stub.seedFromExtensions(FrontPorchExtensions(longTermBond: 50));
      expect(stub.longTermTier, 4,
          reason: 'score 50 => tier 4 (Friendly) since 50 >= 50 threshold');
    });

    test('negative bond produces negative tier', () {
      final stub = _RealismStateStub();
      stub.seedFromExtensions(FrontPorchExtensions(shortTermBond: -30));
      expect(stub.relationshipTier, -3,
          reason: 'negative bond => negative tier (Unimpressed) since -30 >= -30 threshold');
    });

    test('null extension does nothing', () {
      final stub = _RealismStateStub();
      stub.seedFromExtensions(null);
      expect(stub.realismEnabled, isFalse);
      expect(stub.affectionScore, 0);
    });
  });

  // ─── Realism State — reset ─────────────────────────────────────────

  group('resetRealismState', () {
    test('resets arousal to 0', () {
      final stub = _RealismStateStub();
      stub._arousalLevel = 7;
      stub.resetRealismState();
      expect(stub.arousalLevel, 0);
    });

    test('resets fixation to empty', () {
      final stub = _RealismStateStub();
      stub._activeFixation = 'revenge';
      stub._fixationLifespan = 5;
      stub.resetRealismState();
      expect(stub.activeFixation, '');
      expect(stub.fixationLifespan, 0);
    });

    test('does not affect other state fields', () {
      final stub = _RealismStateStub();
      stub.seedFromExtensions(FrontPorchExtensions(shortTermBond: 30));
      final bond = stub.affectionScore;

      stub.resetRealismState();

      expect(stub.affectionScore, bond,
          reason: 'reset should not affect bond/trust/emotion');
    });
  });

  // ─── Realism State — new chat seeding ──────────────────────────────

  group('seedForNewChat', () {
    test('seeds from character extensions', () {
      final stub = _RealismStateStub();
      final char = CharacterCard(
        name: 'Luna',
        firstMessage: 'Hi',
        frontPorchExtensions: FrontPorchExtensions(
          realismEnabled: true,
          shortTermBond: 20,
          trustLevel: 10,
          dayCount: 3,
          timeOfDay: 'afternoon',
        ),
      );

      stub.seedForNewChat(char);

      expect(stub.realismEnabled, isTrue);
      expect(stub.affectionScore, 20);
      expect(stub.trustLevel, 10);
      expect(stub.dayCount, 3);
      expect(stub.timeOfDay, 'afternoon');
    });

    test('preserves arousal/fixation when character has extensions', () {
      final stub = _RealismStateStub();
      stub._arousalLevel = 5;
      stub._activeFixation = 'curiosity';
      stub._fixationLifespan = 3;

      final char = CharacterCard(
        name: 'Luna',
        firstMessage: 'Hi',
        frontPorchExtensions: FrontPorchExtensions(realismEnabled: true),
      );

      stub.seedForNewChat(char);

      expect(stub.arousalLevel, 5,
          reason: 'arousal must be preserved for characters with extensions');
      expect(stub.activeFixation, 'curiosity',
          reason: 'fixation must be preserved for characters with extensions');
    });

    test('resets arousal/fixation when character has no extensions', () {
      final stub = _RealismStateStub();
      stub._arousalLevel = 5;
      stub._activeFixation = 'curiosity';
      stub._fixationLifespan = 3;

      final char = CharacterCard(
        name: 'Luna',
        firstMessage: 'Hi',
        // No extensions
      );

      stub.seedForNewChat(char);

      expect(stub.arousalLevel, 0,
          reason: 'arousal must reset for characters without extensions');
      expect(stub.activeFixation, '',
          reason: 'fixation must reset for characters without extensions');
    });

    test('uses default FrontPorchExtensions when null', () {
      final stub = _RealismStateStub();
      final char = CharacterCard(
        name: 'Luna',
        firstMessage: 'Hi',
        frontPorchExtensions: null,
      );

      stub.seedForNewChat(char);

      expect(stub.realismEnabled, isFalse);
      expect(stub.affectionScore, 0);
      expect(stub.trustLevel, 0);
      expect(stub.dayCount, 1);
      expect(stub.timeOfDay, 'morning');
    });

    test('only calculates tiers when realism enabled', () {
      final stub = _RealismStateStub();
      final char = CharacterCard(
        name: 'Luna',
        firstMessage: 'Hi',
        frontPorchExtensions: FrontPorchExtensions(
          realismEnabled: false,
          shortTermBond: 50,
        ),
      );

      stub._relationshipTier = 99; // set a non-zero value
      stub.seedForNewChat(char);

      expect(stub.relationshipTier, 99,
          reason: 'tiers should not be recalculated when realism is disabled');
    });

    test('calculates tiers when realism enabled', () {
      final stub = _RealismStateStub();
      final char = CharacterCard(
        name: 'Luna',
        firstMessage: 'Hi',
        frontPorchExtensions: FrontPorchExtensions(
          realismEnabled: true,
          shortTermBond: 30,
          longTermBond: 25,
        ),
      );

      stub.seedForNewChat(char);

      // Score 30 => tier 3 (since threshold is < 50 for tier 3)
      expect(stub.relationshipTier, 3);
      // Score 25 => tier 2 (since threshold is < 30 for tier 2)
      expect(stub.longTermTier, 2);
    });
  });

  // ─── Realism State — state preservation across transitions ─────────

  group('state preservation', () {
    test('arousal preserved when extensions exist, reset when not', () {
      final stub = _RealismStateStub();

      // First: character with extensions — arousal preserved
      final charWithExt = CharacterCard(
        name: 'Luna',
        firstMessage: 'Hi',
        frontPorchExtensions: FrontPorchExtensions(realismEnabled: true),
      );

      stub._arousalLevel = 5;
      stub.seedForNewChat(charWithExt);
      expect(stub.arousalLevel, 5);

      // Second: character without extensions — arousal resets
      final charNoExt = CharacterCard(
        name: 'Luna',
        firstMessage: 'Hi',
      );

      stub.seedForNewChat(charNoExt);
      expect(stub.arousalLevel, 0);
    });

    test('bond/trust preserved across new chat for extended characters', () {
      final stub = _RealismStateStub();
      final char = CharacterCard(
        name: 'Luna',
        firstMessage: 'Hi',
        frontPorchExtensions: FrontPorchExtensions(
          realismEnabled: true,
          shortTermBond: 40,
          longTermBond: 35,
          trustLevel: 20,
        ),
      );

      stub.seedForNewChat(char);
      expect(stub.affectionScore, 40);
      expect(stub.longTermScore, 35);
      expect(stub.trustLevel, 20);

      // Simulate bond changing during chat
      stub._affectionScore = 50;
      stub._trustLevel = 25;

      // New chat should re-seed from extensions (not current runtime state)
      stub.seedForNewChat(char);
      expect(stub.affectionScore, 40,
          reason: 'new chat re-seeds from extensions, not runtime state');
      expect(stub.trustLevel, 20);
    });
  });
}
