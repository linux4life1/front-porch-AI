// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Unit tests for the AI-creator lorebook mechanics assigner (Stage 1): the
// deterministic category → SillyTavern-field mapping. The model emits prose +
// a category; these assertions are the contract that turns that into an
// always-on premise anchor + priority tiers the runtime engine honors.

import 'package:flutter_test/flutter_test.dart';

import 'package:front_porch_ai/models/lorebook_entry.dart' show SelectiveLogic;
import 'package:front_porch_ai/services/chargen/lorebook_mechanics.dart';

GeneratedLoreEntry _g(
  String category, {
  String content = 'world lore here',
  String secondary = '',
}) =>
    GeneratedLoreEntry(
      name: '$category entry',
      key: 'alpha, beta',
      content: content,
      category: category,
      secondary: secondary,
    );

void main() {
  group('normalizeLoreCategory', () {
    test('canonical values pass through (any casing/space)', () {
      expect(normalizeLoreCategory('premise'), 'premise');
      expect(normalizeLoreCategory('  Faction '), 'faction');
      expect(normalizeLoreCategory('LOCATION'), 'location');
    });

    test('synonyms fold onto the canonical vocabulary', () {
      expect(normalizeLoreCategory('setting'), 'premise');
      expect(normalizeLoreCategory('world overview'), 'premise');
      expect(normalizeLoreCategory('guild'), 'faction');
      expect(normalizeLoreCategory('organization'), 'faction');
      expect(normalizeLoreCategory('place'), 'location');
      expect(normalizeLoreCategory('npc'), 'figure');
      expect(normalizeLoreCategory('event'), 'history');
      expect(normalizeLoreCategory('artifact'), 'item');
      expect(normalizeLoreCategory('rumor'), 'custom');
    });

    test('unknown / empty → unclassified (empty string, not a tier word)', () {
      expect(normalizeLoreCategory(''), '');
      expect(normalizeLoreCategory('   '), '');
      expect(normalizeLoreCategory('zxcv-nonsense'), '');
    });

    test('synonyms match whole words only (no substring collisions)', () {
      expect(normalizeLoreCategory('world overview'), 'premise');
      expect(normalizeLoreCategory('underworld'), '',
          reason: 'must NOT become premise via the substring "world"');
      expect(normalizeLoreCategory('folklore'), '',
          reason: 'must NOT become history via the substring "lore"');
    });
  });

  group('loreOrderForCategory — higher = survives budget / closer to gen', () {
    test('tiers rank world-defining above ambient', () {
      expect(loreOrderForCategory('premise'), 300);
      expect(loreOrderForCategory('faction'), 200);
      expect(loreOrderForCategory('location'), 120);
      expect(loreOrderForCategory('figure'), 120);
      expect(loreOrderForCategory('history'), 120);
      expect(loreOrderForCategory('item'), 120);
      expect(loreOrderForCategory('custom'), 60);
      // Strict tier ordering (the whole point: core lore is never dropped first).
      expect(loreOrderForCategory('premise'),
          greaterThan(loreOrderForCategory('faction')));
      expect(loreOrderForCategory('faction'),
          greaterThan(loreOrderForCategory('location')));
      expect(loreOrderForCategory('location'),
          greaterThan(loreOrderForCategory('custom')));
    });

    test('unclassified (unknown/blank) → neutral default 100', () {
      // Unrecognized categories are treated as normal keyword entries (the tier
      // a flat, category-less entry always had) — not demoted below ambient
      // flavor, not promoted.
      expect(loreOrderForCategory('nonsense'), 100);
      expect(loreOrderForCategory(''), 100);
    });
  });

  group('assignLoreMechanics', () {
    test('premise entry is the always-on anchor (constant + top priority)', () {
      final out = assignLoreMechanics([_g('premise')]);
      expect(out, hasLength(1));
      expect(out.single.constant, isTrue, reason: 'premise is always injected');
      expect(out.single.order, 300);
      expect(out.single.enabled, isTrue);
      expect(out.single.keys, ['alpha', 'beta']); // parsed from the key string
    });

    test('non-premise entries are keyword-gated (not constant), tiered', () {
      final out = assignLoreMechanics([
        _g('faction'),
        _g('location'),
        _g('custom'),
      ]);
      expect(out.every((e) => !e.constant), isTrue);
      expect(out[0].order, 200);
      expect(out[1].order, 120);
      expect(out[2].order, 60);
    });

    test('synonym + unknown categories still map to sane mechanics', () {
      final out = assignLoreMechanics([
        _g('world setting'), // → premise (whole-word "world")
        _g('mysterious guild'), // → faction (whole-word "guild")
        _g('some-unknown-thing'), // → unclassified → neutral 100
      ]);
      expect(out[0].constant, isTrue);
      expect(out[0].order, 300);
      expect(out[1].order, 200);
      expect(out[2].constant, isFalse);
      expect(out[2].order, 100);
    });

    test('at most ONE always-on anchor even if the model emits 2+ premises', () {
      final out = assignLoreMechanics([
        _g('premise'),
        _g('premise'),
        _g('faction'),
      ]);
      expect(out.where((e) => e.constant), hasLength(1),
          reason: 'only the first premise is the always-on anchor');
      // The extra premise stays high-priority but keyword-gated (not always-on).
      expect(out[1].constant, isFalse);
      expect(out[1].order, 300);
    });

    test('empty-content entries from a sloppy model are dropped', () {
      final out = assignLoreMechanics([
        _g('faction', content: '   '),
        _g('location', content: 'real content'),
      ]);
      expect(out, hasLength(1));
      expect(out.single.order, 120);
    });

    test('a realistic mixed set: exactly one always-on anchor, rest gated', () {
      final out = assignLoreMechanics([
        _g('premise'),
        _g('faction'),
        _g('faction'),
        _g('location'),
        _g('custom'),
      ]);
      expect(out.where((e) => e.constant), hasLength(1));
      // Highest-priority survivor is the premise anchor.
      final maxOrder = out.map((e) => e.order).reduce((a, b) => a > b ? a : b);
      expect(maxOrder, 300);
      expect(out.firstWhere((e) => e.order == 300).constant, isTrue);
    });

    test('anchor prevents recursion; other entries recurse (Stage 3)', () {
      final out = assignLoreMechanics([_g('premise'), _g('faction')]);
      expect(out[0].preventRecursion, isTrue,
          reason: 'the always-on backdrop must not auto-drag in what it names');
      expect(out[1].preventRecursion, isFalse,
          reason: 'other entries recurse normally to form interconnections');
    });
  });

  group('assignLoreMechanics — Stage 2 (contextual firing + variety)', () {
    test('secondary keywords populate secondaryKeys (default andAny logic)', () {
      final out = assignLoreMechanics([_g('figure', secondary: 'ship, crew')]);
      expect(out.single.secondaryKeys, ['ship', 'crew']);
      expect(out.single.selectiveLogic, SelectiveLogic.andAny);
    });

    test('no secondary → empty secondaryKeys (fires on primary keys alone)', () {
      expect(assignLoreMechanics([_g('faction')]).single.secondaryKeys, isEmpty);
    });

    test('ambient (custom) shares one group + fires probabilistically', () {
      final out =
          assignLoreMechanics([_g('custom'), _g('custom'), _g('custom')]);
      expect(out.every((e) => e.group == kAmbientLoreGroup), isTrue,
          reason: 'all ambient flavor rotates in one inclusion group');
      expect(out.every((e) => e.probability == kAmbientLoreProbability), isTrue);
    });

    test('core lore is certain (100%) and ungrouped', () {
      final out = assignLoreMechanics([
        _g('premise'),
        _g('faction'),
        _g('location'),
      ]);
      expect(out.every((e) => e.group.isEmpty), isTrue);
      expect(out.every((e) => e.probability == 100), isTrue);
    });
  });

  group('buildSmartLorebook (Stage 3 — interconnected lore)', () {
    test('turns book-level recursion ON so interconnections fire', () {
      final lb = buildSmartLorebook([_g('premise'), _g('faction')]);
      expect(lb, isNotNull);
      expect(lb!.recursiveScanning, isTrue);
      expect(lb.entries, hasLength(2));
    });

    test('returns null when nothing usable was generated', () {
      expect(buildSmartLorebook(const []), isNull);
      expect(buildSmartLorebook([_g('custom', content: '   ')]), isNull);
    });
  });
}
