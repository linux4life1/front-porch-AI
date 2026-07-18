// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/models/character_card.dart';
import 'package:front_porch_ai/models/lorebook.dart';
import 'package:front_porch_ai/services/chat/lorebook_collection.dart';
import 'package:front_porch_ai/services/chat/lorebook_matcher.dart';
import 'package:front_porch_ai/services/chat/lorebook_scanner.dart';
import 'package:front_porch_ai/services/chat/lorebook_timed_effects.dart';

/// Scanner factory with a live timed-effects store and a mutable message
/// list standing in for the chat.
({LorebookScanner scanner, LorebookTimedEffects timers, List<String> chat})
    timedScannerFor(List<LorebookEntry> entries) {
  final timers = LorebookTimedEffects();
  final chat = <String>[];
  final ch = CharacterCard(name: 'T', lorebook: Lorebook(entries: entries));
  final scanner = LorebookScanner(
    onNotify: () {},
    getEntryRefs: () =>
        collectLoreEntryRefs(characters: [ch], resolveWorld: (_) => null),
    getRecentMessages: (count) =>
        chat.length > count ? chat.sublist(chat.length - count) : chat,
    timedEffects: timers,
    getChatLength: () => chat.length,
  );
  return (scanner: scanner, timers: timers, chat: chat);
}

void main() {
  group('LorebookTimedEffects store', () {
    test('sticky lifecycle: activate → force-active → expire → protected '
        'cooldown → eligible again', () {
      final e = LorebookEntry(
        keys: const ['omen'],
        content: 'x',
        sticky: 3,
        cooldown: 2,
      );
      final t = LorebookTimedEffects();

      t.recordActivation(e, 5); // activates at chat length 5
      expect(t.isStickyActive(e, 5), isTrue);
      expect(t.isStickyActive(e, 7), isTrue);
      expect(t.isStickyActive(e, 8), isFalse); // 5 + 3 = 8 → over

      t.tick(8, [e]); // sticky expires → protected cooldown starts
      expect(t.isStickyActive(e, 8), isFalse);
      expect(t.isOnCooldown(e, 8), isTrue);
      expect(t.isOnCooldown(e, 9), isTrue);

      t.tick(10, [e]); // 8 + 2 = 10 → cooldown over
      expect(t.isOnCooldown(e, 10), isFalse);
    });

    test('re-activation never refreshes a running sticky (ST rule)', () {
      final e = LorebookEntry(keys: const ['k'], content: 'x', sticky: 3);
      final t = LorebookTimedEffects();
      t.recordActivation(e, 5);
      t.recordActivation(e, 7); // must NOT extend
      expect(t.isStickyActive(e, 7), isTrue);
      expect(t.isStickyActive(e, 8), isFalse);
    });

    test('non-sticky cooldown records on activation', () {
      final e = LorebookEntry(keys: const ['k'], content: 'x', cooldown: 4);
      final t = LorebookTimedEffects();
      t.recordActivation(e, 10);
      expect(t.isOnCooldown(e, 11), isTrue);
      expect(t.isOnCooldown(e, 14), isFalse);
    });

    test('rewound chat (deleted messages) drops unprotected effects', () {
      final e = LorebookEntry(keys: const ['k'], content: 'x', cooldown: 4);
      final t = LorebookTimedEffects();
      t.recordActivation(e, 10);
      t.tick(8, [e]); // messages deleted back past the start
      expect(t.isOnCooldown(e, 8), isFalse);
    });

    test('serialize → hydrate round-trip (restart persistence)', () {
      final sticky = LorebookEntry(keys: const ['a'], content: 's', sticky: 5);
      final cooling = LorebookEntry(keys: const ['b'], content: 'c', cooldown: 3);
      final t = LorebookTimedEffects();
      t.recordActivation(sticky, 4);
      t.recordActivation(cooling, 6);

      // Ride an arbitrary state blob the way _doSaveChat does.
      final blob = jsonEncode({
        'sceneGuests': ['g1'],
        'lorebookTimers': t.toJsonFragment(),
      });

      final restored = LorebookTimedEffects()..hydrate(blob);
      expect(restored.isStickyActive(sticky, 6), isTrue);
      expect(restored.isOnCooldown(cooling, 7), isTrue);
      expect(restored.isStickyActive(sticky, 9), isFalse);
    });

    test('editing an entry drops its timed state (hash identity)', () {
      final e = LorebookEntry(keys: const ['a'], content: 'original', sticky: 5);
      final t = LorebookTimedEffects();
      t.recordActivation(e, 4);
      e.content = 'edited';
      expect(t.isStickyActive(e, 5), isFalse); // new hash, no state
    });

    test('empty store persists nothing (old-version-friendly blobs)', () {
      expect(LorebookTimedEffects().toJsonFragment(), isNull);
    });

    test('hash is stable and deterministic', () {
      final a = LorebookEntry(keys: const ['x', 'y'], content: 'c', name: 'n');
      final b = LorebookEntry(keys: const ['x', 'y'], content: 'c', name: 'n');
      expect(loreEntryHash(a), loreEntryHash(b));
    });

    test('chat lorebook persists in the blob and clears on reset', () {
      final t = LorebookTimedEffects();
      t.chatLorebook.entries.add(
        LorebookEntry(keys: const ['vale'], content: 'Chat-only lore.'),
      );
      final blob = jsonEncode({'chatLorebook': t.chatLorebookFragment()});

      final restored = LorebookTimedEffects()..hydrate(blob);
      expect(restored.chatLorebook.entries.single.keys, ['vale']);
      expect(restored.chatLorebook.entries.single.content, 'Chat-only lore.');

      restored.reset();
      expect(restored.chatLorebook.entries, isEmpty);
      expect(LorebookTimedEffects().chatLorebookFragment(), isNull);
    });

    test('chat book enumerates FIRST and its entries can trigger', () {
      final t = LorebookTimedEffects();
      final chatEntry =
          LorebookEntry(keys: const ['pier'], content: 'chat lore');
      t.chatLorebook.entries.add(chatEntry);
      final ch = CharacterCard(
        name: 'T',
        lorebook: Lorebook(
          entries: [LorebookEntry(keys: const ['pier'], content: 'char lore')],
        ),
      );
      final refs = collectLoreEntryRefs(
        characters: [ch],
        chatLorebook: t.chatLorebook,
        resolveWorld: (_) => null,
      );
      expect(refs.first.sourceLabel, 'chat');
      expect(identical(refs.first.entry, chatEntry), isTrue);

      final scanner = LorebookScanner(
        onNotify: () {},
        getEntryRefs: () => refs,
      );
      scanner.scanLorebook('User: down by the pier');
      expect(chatEntry.isTriggered, isTrue);
    });

    test('macro locals persist alongside timers and clear on reset', () {
      final t = LorebookTimedEffects();
      t.localMacroVars['mood'] = 'grim';
      final blob = jsonEncode({'macroVars': t.macroVarsFragment()});
      final restored = LorebookTimedEffects()..hydrate(blob);
      expect(restored.localMacroVars['mood'], 'grim');
      restored.reset();
      expect(restored.localMacroVars, isEmpty);
      expect(LorebookTimedEffects().macroVarsFragment(), isNull);
    });
  });

  group('scanner integration', () {
    test('delay suppresses until the chat is long enough', () {
      final e = LorebookEntry(keys: const ['omen'], content: 'x', delay: 3);
      final s = timedScannerFor([e]);

      s.chat.add('User: an omen appears');
      s.scanner.scanLatest(); // chat length 1 < delay 3
      expect(e.isTriggered, isFalse);

      s.chat.addAll(['T: hm', 'User: the omen again']);
      s.scanner.scanLatest(); // length 3 → eligible
      expect(e.isTriggered, isTrue);
    });

    test('sticky force-refreshes without key matches; cooldown then blocks '
        're-activation until it lapses', () {
      final e = LorebookEntry(
        keys: const ['omen'],
        content: 'x',
        sticky: 2,
        cooldown: 2,
      );
      final s = timedScannerFor([e]);

      s.chat.add('User: an omen appears');
      s.scanner.scanLatest(); // activates; sticky ends at length 3
      expect(e.isTriggered, isTrue);

      // Next turns mention nothing — sticky keeps it active and refreshed.
      s.chat.add('T: quiet');
      s.scanner.scanLatest();
      expect(s.timers.isStickyActive(e, s.chat.length), isTrue);
      expect(e.remainingDepth, e.stickyDepth);

      // Sticky expires; protected cooldown begins. Even a fresh key match
      // cannot re-activate during cooldown.
      s.chat.add('User: nothing');
      s.scanner.scanLatest(); // length 3 → sticky over, cooldown 3..5
      e.isTriggered = false; // legacy depth ran out too
      s.chat.add('User: the omen returns');
      s.scanner.scanLatest(); // length 4 — cooling
      expect(e.isTriggered, isFalse);

      s.chat.addAll(['T: …', 'User: the omen rises once more']);
      s.scanner.scanLatest(); // length 6 — cooldown (ended at 5) is over
      expect(e.isTriggered, isTrue);
    });

    test('sticky-active entries skip the probability roll', () {
      final e = LorebookEntry(
        keys: const ['omen'],
        content: 'x',
        sticky: 3,
        probability: 100,
      );
      final s = timedScannerFor([e]);
      s.chat.add('User: an omen appears');
      s.scanner.scanLatest();
      expect(e.isTriggered, isTrue);

      // Make any future roll impossible — the sticky refresh must not roll.
      e.probability = 0;
      e.isTriggered = false; // simulate legacy depth expiry
      s.chat.add('T: unrelated');
      s.scanner.scanLatest();
      expect(e.isTriggered, isTrue); // revived by sticky, no roll
    });

    test('remaining counters feed the sidebar pills', () {
      final e = LorebookEntry(
        keys: const ['omen'],
        content: 'x',
        sticky: 3,
        cooldown: 2,
      );
      final t = LorebookTimedEffects();
      t.recordActivation(e, 5);
      expect(t.stickyRemaining(e, 6), 2);
      expect(t.cooldownRemaining(e, 6), 0);
      t.tick(8, [e]); // sticky over → protected cooldown 8..10
      expect(t.stickyRemaining(e, 8), 0);
      expect(t.cooldownRemaining(e, 9), 1);
    });

    test('previewTriggers is a pure dry-run (no state writes)', () {
      final e = LorebookEntry(
        keys: const ['omen'],
        secondaryKeys: const ['dark'],
        content: 'x',
      );
      final gated = LorebookEntry(
        keys: const ['omen'],
        probability: 0, // preview ignores probability entirely
        content: 'y',
      );
      final s = timedScannerFor([e, gated]);
      final hits = s.scanner.previewTriggers('a dark omen rises');
      expect(hits, containsAll([e, gated]));
      expect(e.isTriggered, isFalse); // nothing was mutated
      expect(gated.isTriggered, isFalse);
      expect(s.scanner.previewTriggers('an omen'), isNot(contains(e)));
      expect(s.scanner.previewTriggers(''), isEmpty);
    });

    test('session-boundary reset clears timers', () {
      final e = LorebookEntry(keys: const ['omen'], content: 'x', sticky: 5);
      final s = timedScannerFor([e]);
      s.chat.add('User: an omen appears');
      s.scanner.scanLatest();
      expect(s.timers.isStickyActive(e, s.chat.length), isTrue);

      s.scanner.resetLorebookTriggerState();
      expect(s.timers.isStickyActive(e, s.chat.length), isFalse);
      expect(e.isTriggered, isFalse);
    });
  });
}
