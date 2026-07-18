// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Integration tests for lorebook entry matching and injection (historical file).
// Core scan/decr logic extracted; this now exercises real LorebookScanner + notes
// deletion of obsolete simulator + conflicting substring test. See dedicated for contract.

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/models/character_card.dart';
import 'package:front_porch_ai/models/lorebook.dart';
import 'package:front_porch_ai/models/world.dart';
import 'package:front_porch_ai/services/chat/lorebook_collection.dart';
import 'package:front_porch_ai/services/chat/lorebook_scanner.dart';

// Historical simulator + conflicting substring logic deleted (obsolete post-extraction;
// duplicated wrong .contains vs real word-boundary _matchKeyword; outdated _scanLorebook line refs to excised god code).
// Now delegates to real public LorebookScanner API (correct boundary/wildcard semantics; see dedicated lorebook_scanner_test.dart).
// Full lore injection exercised via thin delegations in key suites (god's getActiveGroupLoreEntries + _buildLorebookContext + pre-existing startNew/setActive/greeting/send/final paths).
// No aug file edits for lore qualifiers (only in dedicated+service+god+MD).
// Group/world/per-char via cb.

/// Local test factory (live cb closures; modeled on dedicated).
LorebookScanner createTestLorebookScannerForIntegration({
  List<CharacterCard>? characters,
  Map<String, World>? worldsByName,
}) {
  final chars = characters ?? <CharacterCard>[];
  final worlds = worldsByName ?? <String, World>{};
  return LorebookScanner(
    onNotify: () {},
    getEntryRefs: () => collectLoreEntryRefs(
      characters: chars,
      resolveWorld: (name) => worlds[name],
    ),
  );
}

void main() {
  // ─── 4.3: Lorebook Injection ───────────────────────────────────────

  group('Lorebook Injection (now via real LorebookScanner)', () {
    test('constant entries always match', () {
      final entry = LorebookEntry(
        key: 'dragon',
        content: 'Dragons are ancient and powerful.',
        name: 'Dragon Lore',
        constant: true,
      );
      final ch = CharacterCard(
        name: 'C',
        lorebook: Lorebook(entries: [entry]),
      );
      final svc = createTestLorebookScannerForIntegration(characters: [ch]);
      svc.scanLorebook('I see a dragon');
      expect(entry.isTriggered, isTrue);
      expect(entry.remainingDepth, 1);
    });

    test(
      'keyword-triggered entries match on keywords + sticky + decr (adapted to real scanner)',
      () {
        final entry = LorebookEntry(
          key: 'dragon, wyrm',
          content: 'Dragons breathe fire.',
          stickyDepth: 2,
        );
        final ch = CharacterCard(
          name: 'C',
          lorebook: Lorebook(entries: [entry]),
        );
        final svc = createTestLorebookScannerForIntegration(characters: [ch]);
        svc.scanLorebook('I see a dragon');
        expect(entry.isTriggered, isTrue);
        expect(entry.remainingDepth, 2);

        final pre = {entry};
        svc.decrementLoreDepthForEntries(pre);
        expect(entry.remainingDepth, 1);
        expect(entry.isTriggered, isTrue);

        svc.decrementLoreDepthForEntries(pre);
        expect(entry.remainingDepth, 0);
        expect(entry.isTriggered, isFalse);
      },
    );

    test('entries do not match on unrelated keywords', () {
      final entry = LorebookEntry(
        key: 'dragon',
        content: 'Dragons are fire-breathing reptiles.',
      );
      final ch = CharacterCard(
        name: 'C',
        lorebook: Lorebook(entries: [entry]),
      );
      final svc = createTestLorebookScannerForIntegration(characters: [ch]);
      svc.scanLorebook('I see a horse');
      expect(entry.isTriggered, isFalse);
    });

    test('multiple keywords in one entry — any match triggers', () {
      final entry = LorebookEntry(
        key: 'elf, elven, highborn',
        content: 'Elves are long-lived beings.',
      );
      final ch = CharacterCard(
        name: 'C',
        lorebook: Lorebook(entries: [entry]),
      );
      final svc = createTestLorebookScannerForIntegration(characters: [ch]);
      svc.scanLorebook('The elven ranger approaches');
      expect(entry.isTriggered, isTrue);

      final entry2 = LorebookEntry(
        key: 'elf, elven, highborn',
        content: 'Elves are long-lived beings.',
      );
      final ch2 = CharacterCard(
        name: 'C2',
        lorebook: Lorebook(entries: [entry2]),
      );
      final svc2 = createTestLorebookScannerForIntegration(characters: [ch2]);
      svc2.scanLorebook('A highborn noble enters');
      expect(entry2.isTriggered, isTrue);

      final entry3 = LorebookEntry(
        key: 'elf, elven, highborn',
        content: 'Elves are long-lived beings.',
      );
      final ch3 = CharacterCard(
        name: 'C3',
        lorebook: Lorebook(entries: [entry3]),
      );
      final svc3 = createTestLorebookScannerForIntegration(characters: [ch3]);
      svc3.scanLorebook('Nothing here');
      expect(entry3.isTriggered, isFalse);
    });

    test('disabled entries do not match', () {
      final entry = LorebookEntry(
        key: 'dragon',
        content: 'Dragons are dangerous.',
        enabled: false,
      );
      final ch = CharacterCard(
        name: 'C',
        lorebook: Lorebook(entries: [entry]),
      );
      final svc = createTestLorebookScannerForIntegration(characters: [ch]);
      svc.scanLorebook('I see a dragon');
      expect(entry.isTriggered, isFalse);
    });

    test('case-insensitive keyword matching', () {
      final entry = LorebookEntry(
        key: 'Dragon',
        content: 'Dragons breathe fire.',
      );
      final ch = CharacterCard(
        name: 'C',
        lorebook: Lorebook(entries: [entry]),
      );
      final svc = createTestLorebookScannerForIntegration(characters: [ch]);
      svc.scanLorebook('i saw a DRAGON in the sky');
      expect(entry.isTriggered, isTrue);
    });

    test(
      'keyword matching uses word boundaries (not arbitrary substring; fire does not match fireball) — conflicting substring test body deleted',
      () {
        final entry = LorebookEntry(key: 'fire', content: 'Fire is dangerous.');
        final ch = CharacterCard(
          name: 'C',
          lorebook: Lorebook(entries: [entry]),
        );
        final svc = createTestLorebookScannerForIntegration(characters: [ch]);
        svc.scanLorebook('The dragon breathes fireballs');
        expect(
          entry.isTriggered,
          isFalse,
          reason: 'boundary semantics from real scanner',
        );
      },
    );

    test('sticky depth extends on each match (adapted)', () {
      final entry = LorebookEntry(
        key: 'dragon',
        content: 'Dragons are ancient.',
        stickyDepth: 2,
      );
      final ch = CharacterCard(
        name: 'C',
        lorebook: Lorebook(entries: [entry]),
      );
      final svc = createTestLorebookScannerForIntegration(characters: [ch]);
      svc.scanLorebook('I see a dragon');
      expect(entry.remainingDepth, 2);

      svc.decrementLoreDepthForEntries({entry});
      expect(entry.remainingDepth, 1);

      svc.scanLorebook('The dragon roars');
      expect(entry.remainingDepth, 2);
    });

    test('multiple entries can be active simultaneously (adapted)', () {
      final e1 = LorebookEntry(
        key: 'dragon',
        content: 'Dragons breathe fire.',
        stickyDepth: 3,
      );
      final e2 = LorebookEntry(
        key: 'elf',
        content: 'Elves are graceful.',
        stickyDepth: 2,
      );
      final ch = CharacterCard(
        name: 'C',
        lorebook: Lorebook(entries: [e1, e2]),
      );
      final svc = createTestLorebookScannerForIntegration(characters: [ch]);
      svc.scanLorebook('An elf fights a dragon');
      expect(e1.isTriggered && e2.isTriggered, isTrue);
    });

    test('constant entries stay active regardless of depth (adapted)', () {
      final entry = LorebookEntry(
        key: 'magic',
        content: 'Magic is rare in this world.',
        constant: true,
      );
      final ch = CharacterCard(
        name: 'C',
        lorebook: Lorebook(entries: [entry]),
      );
      final svc = createTestLorebookScannerForIntegration(characters: [ch]);
      svc.scanLorebook('I see magic');
      expect(entry.isTriggered, isTrue);

      for (int i = 0; i < 100; i++) {
        svc.decrementLoreDepthForEntries({entry});
      }

      expect(
        entry.isTriggered,
        isTrue,
        reason: 'constant entries never expire',
      );
    });

    test('re-scanning after expiry re-triggers the entry (adapted)', () {
      final entry = LorebookEntry(
        key: 'dragon',
        content: 'Dragons are fierce.',
        stickyDepth: 1,
      );
      final ch = CharacterCard(
        name: 'C',
        lorebook: Lorebook(entries: [entry]),
      );
      final svc = createTestLorebookScannerForIntegration(characters: [ch]);
      svc.scanLorebook('A dragon appears');
      expect(entry.isTriggered, isTrue);

      svc.decrementLoreDepthForEntries({entry});
      expect(entry.isTriggered, isFalse);

      svc.scanLorebook('The dragon returns');
      expect(entry.isTriggered, isTrue);
    });

    test('empty key does not match', () {
      final entry = LorebookEntry(key: '', content: 'This should never match.');
      final ch = CharacterCard(
        name: 'C',
        lorebook: Lorebook(entries: [entry]),
      );
      final svc = createTestLorebookScannerForIntegration(characters: [ch]);
      svc.scanLorebook('anything at all');
      expect(entry.isTriggered, isFalse);
    });

    test('whitespace in keys is trimmed', () {
      final entry = LorebookEntry(
        key: ' dragon , wyrm ',
        content: 'Dragons are powerful.',
      );
      final ch = CharacterCard(
        name: 'C',
        lorebook: Lorebook(entries: [entry]),
      );
      final svc = createTestLorebookScannerForIntegration(characters: [ch]);
      svc.scanLorebook('I see a dragon');
      expect(entry.isTriggered, isTrue);
    });
  });
}
