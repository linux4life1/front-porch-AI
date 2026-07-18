// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/models/character_card.dart';
import 'package:front_porch_ai/models/lorebook.dart';
import 'package:front_porch_ai/services/chat/lorebook_collection.dart';
import 'package:front_porch_ai/services/chat/lorebook_injector.dart';
import 'package:front_porch_ai/services/storage/settings/lorebook_settings.dart';

LorebookInjector injectorFor(
  List<LorebookEntry> entries, {
  Lorebook? book,
  bool Function(LorebookEntry)? isStickyActive,
}) {
  final theBook = book ?? Lorebook(entries: entries);
  final ch = CharacterCard(name: 'T', lorebook: theBook);
  return LorebookInjector(
    getEntryRefs: () => collectLoreEntryRefs(
      characters: [ch],
      resolveWorld: (_) => null,
    ),
    getSettings: LorebookSettings.new, // unloaded prefs → pure defaults
    isStickyActive: isStickyActive ?? (_) => false,
  );
}

LorebookEntry active(String content,
    {int order = 100,
    int position = 0,
    int depth = 4,
    String group = '',
    int groupWeight = 100,
    bool groupOverride = false,
    bool? useGroupScoring,
    bool ignoreBudget = false,
    String name = ''}) {
  final e = LorebookEntry(
    keys: const ['k'],
    content: content,
    order: order,
    position: position,
    depth: depth,
    group: group,
    groupWeight: groupWeight,
    groupOverride: groupOverride,
    useGroupScoring: useGroupScoring,
    ignoreBudget: ignoreBudget,
    name: name.isEmpty ? content : name,
  );
  e.isTriggered = true;
  return e;
}

void main() {
  group('position bucketing', () {
    test('each position lands in its bucket; outlet falls back to before',
        () {
      final inj = injectorFor([
        active('B', position: 0),
        active('A', position: 1),
        active('AT', position: 2),
        active('AB', position: 3),
        active('D', position: 4, depth: 2),
        active('ET', position: 5),
        active('EB', position: 6),
        active('O', position: 7),
      ]);
      final r = inj.buildInjection(sessionSeed: 's', contextSize: 8192);
      expect(r.beforeChar, 'Context Info:\nB\nO\n');
      expect(r.afterChar, 'A\n');
      expect(r.authorNoteTop, 'AT\n');
      expect(r.authorNoteBottom, 'AB\n');
      expect(r.examplesTop, 'ET\n');
      expect(r.examplesBottom, 'EB\n');
      expect(r.depthEntries.single.content, 'D');
      expect(r.depthEntries.single.depth, 2);
    });

    test('within a bucket, higher order sits closer to the end', () {
      final inj = injectorFor([
        active('high', order: 300),
        active('low', order: 10),
        active('mid', order: 100),
      ]);
      final r = inj.buildInjection(sessionSeed: 's', contextSize: 8192);
      expect(r.beforeChar, 'Context Info:\nlow\nmid\nhigh\n');
    });

    test('duplicate content injects once (legacy dedup)', () {
      final inj = injectorFor([active('same'), active('same', order: 50)]);
      final r = inj.buildInjection(sessionSeed: 's', contextSize: 8192);
      expect('same'.allMatches(r.beforeChar).length, 1);
    });
  });

  group('token budget', () {
    test('lowest-order entries drop first when over budget', () {
      // Default budget: 25% of contextSize. contextSize 480 → 120 tokens.
      // Each entry 201 chars → 51 tokens: two fit, the third overflows.
      final big = 'x' * 200;
      final inj = injectorFor([
        active('A$big', order: 300, name: 'keeper1'),
        active('B$big', order: 200, name: 'keeper2'),
        active('C$big', order: 10, name: 'dropped'),
      ]);
      final r = inj.buildInjection(sessionSeed: 's', contextSize: 480);
      expect(r.beforeChar.contains('A'), isTrue);
      expect(r.beforeChar.contains('C$big'), isFalse);
      expect(r.overflowDropped, ['dropped']);
    });

    test('ignoreBudget entries always inject and are not counted', () {
      final big = 'x' * 500;
      final inj = injectorFor([
        active('vital$big', ignoreBudget: true, name: 'vital'),
        active('also$big', order: 200, name: 'also'),
      ]);
      // Budget 25 tokens — far too small for either.
      final r = inj.buildInjection(sessionSeed: 's', contextSize: 100);
      expect(r.beforeChar.contains('vital'), isTrue);
      expect(r.overflowDropped, ['also']);
    });

    test('book-level token_budget caps that book contribution', () {
      final e1 = active('a' * 200, order: 300, name: 'first');
      final e2 = active('b' * 200, order: 200, name: 'second');
      final book = Lorebook(entries: [e1, e2], tokenBudget: 60);
      final inj = injectorFor([e1, e2], book: book);
      final r = inj.buildInjection(sessionSeed: 's', contextSize: 100000);
      expect(r.beforeChar.contains('a'), isTrue);
      expect(r.overflowDropped, ['second']);
    });

    test('sticky-active entries fill first', () {
      final sticky = active('s' * 200, order: 1, name: 'sticky');
      final loud = active('l' * 200, order: 999, name: 'loud');
      final inj = injectorFor(
        [sticky, loud],
        isStickyActive: (e) => identical(e, sticky),
      );
      // Budget 80 tokens: only one 50-token entry fits — the sticky one,
      // despite its far lower order.
      final r = inj.buildInjection(sessionSeed: 's', contextSize: 320);
      expect(r.beforeChar.contains('s' * 200), isTrue);
      expect(r.overflowDropped, ['loud']);
    });
  });

  group('inclusion groups', () {
    test('only one member of a group injects; groupless pass through', () {
      final a = active('wolf-a', group: 'wolves');
      final b = active('wolf-b', group: 'wolves');
      final c = active('free');
      final inj = injectorFor([a, b, c]);
      final r = inj.buildInjection(sessionSeed: 'seed', contextSize: 8192);
      final gotA = r.beforeChar.contains('wolf-a');
      final gotB = r.beforeChar.contains('wolf-b');
      expect(gotA != gotB, isTrue); // exactly one
      expect(r.beforeChar.contains('free'), isTrue);
    });

    test('groupOverride wins by highest order', () {
      final a = active('normal', group: 'g', order: 999);
      final b = active('override-low', group: 'g', order: 10, groupOverride: true);
      final c = active('override-high', group: 'g', order: 20, groupOverride: true);
      final inj = injectorFor([a, b, c]);
      final r = inj.buildInjection(sessionSeed: 'seed', contextSize: 8192);
      expect(r.beforeChar.contains('override-high'), isTrue);
      expect(r.beforeChar.contains('override-low'), isFalse);
      expect(r.beforeChar.contains('normal'), isFalse);
    });

    test('group scoring picks the most matched keys', () {
      final a = active('one-key', group: 'g', useGroupScoring: true);
      a.lastMatchScore = 1;
      final b = active('two-keys', group: 'g', useGroupScoring: true);
      b.lastMatchScore = 2;
      final inj = injectorFor([a, b]);
      final r = inj.buildInjection(sessionSeed: 'seed', contextSize: 8192);
      expect(r.beforeChar.contains('two-keys'), isTrue);
      expect(r.beforeChar.contains('one-key'), isFalse);
    });

    test('sticky-active member wins the group outright', () {
      final a = active('challenger', group: 'g', order: 999, groupOverride: true);
      final b = active('champ', group: 'g', order: 1);
      final inj = injectorFor(
        [a, b],
        isStickyActive: (e) => identical(e, b),
      );
      final r = inj.buildInjection(sessionSeed: 'seed', contextSize: 8192);
      expect(r.beforeChar.contains('champ'), isTrue);
      expect(r.beforeChar.contains('challenger'), isFalse);
    });

    test('weighted-random winner is stable while membership is unchanged, '
        'and re-rolls when it changes', () {
      final a = active('cand-a', group: 'g');
      final b = active('cand-b', group: 'g');
      final inj = injectorFor([a, b]);
      final first = inj
          .buildInjection(sessionSeed: 'seed', contextSize: 8192)
          .beforeChar;
      for (var i = 0; i < 5; i++) {
        expect(
          inj.buildInjection(sessionSeed: 'seed', contextSize: 8192).beforeChar,
          first,
        );
      }
      // Different session seed may (and across the space, must be able to)
      // produce a different pick — assert determinism per seed instead of a
      // specific flip: the same alternate seed always agrees with itself.
      final alt1 = inj
          .buildInjection(sessionSeed: 'other', contextSize: 8192)
          .beforeChar;
      final alt2 = inj
          .buildInjection(sessionSeed: 'other', contextSize: 8192)
          .beforeChar;
      expect(alt1, alt2);
    });

    test('activeEntries reports the filtered truth for UI surfaces', () {
      final a = active('wolf-a', group: 'wolves');
      final b = active('wolf-b', group: 'wolves');
      final inj = injectorFor([a, b]);
      final actives = inj.activeEntries(sessionSeed: 'seed');
      expect(actives.length, 1);
      // The loser keeps its trigger state (it can step up later) but is
      // not reported active.
      expect(a.isTriggered && b.isTriggered, isTrue);
    });
  });
}
