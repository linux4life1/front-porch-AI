// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/models/lorebook.dart';
import 'package:front_porch_ai/models/lorebook_codec.dart';
import 'package:front_porch_ai/models/lorebook_export.dart';

Map<String, dynamic> _fixture(String name) {
  final file = File('test/fixtures/lorebooks/$name');
  return jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
}

void main() {
  group('detectLorebookFormat', () {
    test('detects each foreign format by its marker', () {
      expect(detectLorebookFormat(_fixture('novelai.json')),
          LorebookFormat.novelAi);
      expect(detectLorebookFormat(_fixture('agnai.json')), LorebookFormat.agnai);
      expect(detectLorebookFormat(_fixture('risu.json')), LorebookFormat.risu);
      expect(detectLorebookFormat(_fixture('v3_lorebook.json')),
          LorebookFormat.v3Lorebook);
      expect(detectLorebookFormat(_fixture('st_world_info.json')),
          LorebookFormat.fpaiOrSt);
      expect(detectLorebookFormat(_fixture('v2_character_book.json')),
          LorebookFormat.fpaiOrSt);
    });
  });

  group('ST world info decode', () {
    test('reads the full field set faithfully', () {
      final book = Lorebook.fromJson(_fixture('st_world_info.json'));
      expect(book.entries.length, 2);
      final e = book.entries[0];
      expect(e.uid, 0);
      expect(e.name, 'The Ember Court');
      expect(e.keys, ['ember court', 'the court']);
      expect(e.secondaryKeys, ['queen', 'throne']);
      expect(e.selective, true);
      expect(e.selectiveLogic, SelectiveLogic.andAll);
      expect(e.order, 250);
      expect(e.position, 4);
      expect(e.role, 2);
      expect(e.depth, 6);
      expect(e.probability, 75);
      expect(e.useProbability, true);
      expect(e.group, 'court');
      expect(e.groupOverride, true);
      expect(e.groupWeight, 150);
      expect(e.useGroupScoring, true);
      expect(e.scanDepth, 8);
      expect(e.caseSensitive, true);
      expect(e.matchWholeWords, false);
      expect(e.sticky, 3);
      expect(e.cooldown, 5);
      expect(e.delay, 2);
      expect(e.excludeRecursion, true);
      expect(e.delayUntilRecursion, 2);
      expect(e.ignoreBudget, true);
      expect(e.matchPersonaDescription, true);
      expect(e.matchScenario, true);
      expect(e.automationId, 'court-arrival');
      expect(e.triggers, ['normal', 'continue']);
      expect(e.characterFilter?['names'], ['Maravelle']);
      expect(e.stickyDepth, 1); // never coerced from ST fields
      // Unknown ST fields survive in extensions.
      expect(e.extensions['someFutureStField'], 'must-survive');

      final e2 = book.entries[1];
      expect(e2.uid, 7);
      expect(e2.enabled, false); // disable: true
      // Regex key with a comma inside stays atomic.
      expect(e2.keys, ['/a{1,2}shfall/i', 'blight']);
    });

    test('semantic round-trip: decode → encodeStWorldInfo → decode', () {
      final original = Lorebook.fromJson(_fixture('st_world_info.json'));
      final exported = encodeStWorldInfo(original);
      final restored = Lorebook.fromJson(exported);

      expect(restored.entries.length, original.entries.length);
      for (var i = 0; i < original.entries.length; i++) {
        final a = original.entries[i];
        final b = restored.entries[i];
        expect(b.uid, a.uid);
        expect(b.keys, a.keys);
        expect(b.secondaryKeys, a.secondaryKeys);
        expect(b.name, a.name);
        expect(b.content, a.content);
        expect(b.enabled, a.enabled);
        expect(b.constant, a.constant);
        expect(b.selectiveLogic, a.selectiveLogic);
        expect(b.order, a.order);
        expect(b.position, a.position);
        expect(b.role ?? 0, a.role ?? 0);
        expect(b.depth, a.depth);
        expect(b.probability, a.probability);
        expect(b.group, a.group);
        expect(b.groupOverride, a.groupOverride);
        expect(b.groupWeight, a.groupWeight);
        expect(b.scanDepth, a.scanDepth);
        expect(b.caseSensitive, a.caseSensitive);
        expect(b.matchWholeWords, a.matchWholeWords);
        expect(b.sticky, a.sticky);
        expect(b.cooldown, a.cooldown);
        expect(b.delay, a.delay);
        expect(b.excludeRecursion, a.excludeRecursion);
        expect(b.preventRecursion, a.preventRecursion);
        expect(b.delayUntilRecursion, a.delayUntilRecursion);
        expect(b.ignoreBudget, a.ignoreBudget);
        expect(b.automationId, a.automationId);
        expect(b.triggers, a.triggers);
        expect(b.stickyDepth, a.stickyDepth);
        expect(b.extensions['someFutureStField'],
            a.extensions['someFutureStField']);
      }
    });
  });

  group('V2 character_book decode', () {
    test('reads base fields + the ST extensions.* interchange mapping', () {
      final book = Lorebook.fromJson(_fixture('v2_character_book.json'));
      expect(book.scanDepth, 5);
      expect(book.tokenBudget, 700);
      expect(book.recursiveScanning, true);
      expect(book.extensions['chub'], {'id': 42});

      final e = book.entries.single;
      expect(e.keys, ['maravelle', 'the queen']);
      expect(e.secondaryKeys, ['court', 'throne']);
      expect(e.order, 120); // insertion_order
      expect(e.uid, 3); // id
      // extensions.position (numeric 4) beats the V2 'after_char' string.
      expect(e.position, 4);
      expect(e.probability, 40);
      expect(e.selectiveLogic, SelectiveLogic.notAny);
      expect(e.depth, 3);
      expect(e.role, 1);
      expect(e.vectorized, true);
      expect(e.sticky, 1);
      expect(e.group, 'royals');
      expect(e.groupWeight, 80);
      expect(e.scanDepth, 6);
      expect(e.matchWholeWords, true);
      expect(e.triggers, ['normal']);
      // Unknown card extension data + unmodeled V2 priority survive.
      expect(e.extensions['chub_specific_thing'], {'nested': true});
      expect(e.extensions['priority'], 9);
    });

    test('encodeCharacterBook round-trips the card mapping', () {
      final original = Lorebook.fromJson(_fixture('v2_character_book.json'));
      final restored = Lorebook.fromJson(encodeCharacterBook(original));
      final a = original.entries.single;
      final b = restored.entries.single;
      expect(b.keys, a.keys);
      expect(b.secondaryKeys, a.secondaryKeys);
      expect(b.position, a.position);
      expect(b.probability, a.probability);
      expect(b.selectiveLogic, a.selectiveLogic);
      expect(b.depth, a.depth);
      expect(b.role, a.role);
      expect(b.vectorized, a.vectorized);
      expect(b.sticky, a.sticky);
      expect(b.group, a.group);
      expect(b.groupWeight, a.groupWeight);
      expect(b.scanDepth, a.scanDepth);
      expect(b.matchWholeWords, a.matchWholeWords);
      expect(b.triggers, a.triggers);
      expect(b.order, a.order);
      expect(b.uid, a.uid);
      expect(b.extensions['chub_specific_thing'], {'nested': true});
      expect(restored.scanDepth, original.scanDepth);
      expect(restored.tokenBudget, original.tokenBudget);
      expect(restored.recursiveScanning, original.recursiveScanning);
    });
  });

  group('foreign formats', () {
    test('V3 lorebook: use_regex, string id preserved, decorators kept', () {
      final book = Lorebook.fromJson(_fixture('v3_lorebook.json'));
      final e = book.entries.single;
      expect(e.useRegex, true);
      expect(e.keys, ['dragons?', 'wyrm(s)?']);
      expect(e.order, 10);
      expect(e.uid, isNull);
      expect(e.extensions['id'], 'v3-string-id');
      // Stored content keeps decorators; injection strips them.
      expect(e.content.contains('@@depth 2'), true);
      expect(e.injectableContent, 'Dragons nest in the caldera.');
    });

    test('NovelAI: keys/text/displayName/budgetPriority mapping', () {
      final book = Lorebook.fromJson(_fixture('novelai.json'));
      expect(book.entries.length, 2);
      expect(book.entries[0].name, 'Geography');
      expect(book.entries[0].keys, ['vale', 'peaks']);
      expect(book.entries[0].content.contains('ash-grey'), true);
      expect(book.entries[0].order, 400);
      expect(book.entries[1].enabled, false);
    });

    test('AgnAI: keywords/entry/weight mapping', () {
      final book = Lorebook.fromJson(_fixture('agnai.json'));
      final e = book.entries.single;
      expect(e.name, 'The Old War');
      expect(e.keys, ['old war', 'the burning']);
      expect(e.content.contains('eastern forests'), true);
      expect(e.order, 55);
    });

    test('RisuAI: key/secondkey/alwaysActive/activationPercent mapping', () {
      final book = Lorebook.fromJson(_fixture('risu.json'));
      expect(book.entries.length, 2);
      final e = book.entries[0];
      expect(e.name, 'Lantern Night');
      expect(e.keys, ['festival', 'lantern night']);
      expect(e.secondaryKeys, ['vale', 'city']);
      expect(e.probability, 60);
      expect(e.order, 35);
      expect(book.entries[1].constant, true);
    });
  });

  group('legacy FPAI blob compatibility', () {
    test('old 6-field blob still reads, including bug-era stickyDepth=100', () {
      final legacy = {
        'entries': [
          {
            'name': 'Old Entry',
            'key': 'vale, peaks',
            'keys': ['vale', 'peaks'],
            'content': 'Legacy content',
            'enabled': true,
            'constant': false,
            'sticky_depth': 100,
          },
        ],
      };
      final book = Lorebook.fromJson(legacy);
      final e = book.entries.single;
      expect(e.keys, ['vale', 'peaks']);
      expect(e.content, 'Legacy content');
      // Bug-era values are left untouched — no silent data mutation on read.
      expect(e.stickyDepth, 100);
      expect(e.order, 100); // untouched default
    });

    test('new blob keeps keys[] first so old app versions stay readable', () {
      final blob = Lorebook(
        entries: [LorebookEntry(keys: const ['a', 'b'], content: 'c')],
      ).toJson();
      final entry = (blob['entries'] as List).first as Map<String, dynamic>;
      expect(entry['keys'], ['a', 'b']);
      expect(entry['sticky_depth'], 1);
    });
  });
}
