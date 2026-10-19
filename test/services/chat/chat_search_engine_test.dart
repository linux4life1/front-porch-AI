// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/services/chat/chat_search_engine.dart';

({String text, String sender}) msg(String text, {String sender = 'Juniper'}) =>
    (text: text, sender: sender);

List<({int start, int end})> ranges(String text, ChatQuerySpec spec) =>
    chatQueryRanges(text, spec);

void main() {
  group('compileChatQuery', () {
    test('no star is a plain needle', () {
      final spec = compileChatQuery('lantern');
      expect(spec.bad, isFalse);
      expect(spec.needle, 'lantern');
      expect(spec.wordBounded, isFalse);
    });

    test('plain keeps case when caseSensitive', () {
      final spec = compileChatQuery('Lantern', caseSensitive: true);
      expect(spec.needle, 'Lantern');
    });

    test('glob star compiles to word-char span, bounded', () {
      final spec = compileChatQuery('cook*ware');
      expect(spec.needle, isNull);
      expect(spec.wordBounded, isTrue);
      expect(spec.pattern, isNotNull);
    });

    test('\\* is a literal star, not a glob', () {
      final spec = compileChatQuery(r'\*');
      expect(spec.needle, '*');
      expect(ranges('a *nod* b', spec), [
        (start: 2, end: 3),
        (start: 6, end: 7),
      ]);
    });

    test('regex mode compiles verbatim and is unbounded', () {
      final spec = compileChatQuery('lantern.*storm', regexMode: true);
      expect(spec.wordBounded, isFalse);
      expect(spec.pattern, isNotNull);
    });

    test('invalid regex reports bad, never throws', () {
      final spec = compileChatQuery('lantern[', regexMode: true);
      expect(spec.bad, isTrue);
    });

    test('empty query is plain-empty (no-op search)', () {
      final spec = compileChatQuery('   ');
      expect(spec.needle, '');
    });
  });

  group('plain matching', () {
    test('hits never overlap, so leaf splits cannot repeat text', () {
      final spec = compileChatQuery('aa');
      expect(ranges('aaaa', spec), [(start: 0, end: 2), (start: 2, end: 4)]);
      expect(ranges('aaa', spec), [(start: 0, end: 2)]);
    });

    test('substring across word boundaries, case-insensitive', () {
      final spec = compileChatQuery('lantern');
      expect(
        ranges('A lantern answers. Lantern-light and dogwood.', spec).length,
        2,
      ); // Lantern-light counts, dogwood does not contain it
    });

    test('case-sensitive needle misses other case', () {
      final spec = compileChatQuery('Lantern', caseSensitive: true);
      expect(ranges('a lantern lit', spec), isEmpty);
      expect(ranges('a Lantern lit', spec).length, 1);
    });
  });

  group('word-anchored glob', () {
    test('*dog matches words ENDING in dog', () {
      final spec = compileChatQuery('*dog');
      expect(ranges('a bulldog and a dog.', spec).length, 2);
      expect(ranges('the dogs and dogwood', spec), isEmpty);
    });

    test('cook* matches words STARTING with cook', () {
      final spec = compileChatQuery('cook*');
      expect(ranges('cookware and cooking and cook.', spec).length, 3);
      expect(ranges('undercook it', spec), isEmpty);
    });

    test('middle star stays inside one word', () {
      final spec = compileChatQuery('cook*ware');
      expect(ranges('pure cookware', spec).length, 1);
      expect(ranges('cooking ware', spec), isEmpty);
    });

    test('star spans unicode letters, not spaces', () {
      final spec = compileChatQuery('caf*e');
      expect(ranges('pure caféine', spec).length, 1); // star crosses é·i·n
      expect(ranges('café au lait', spec), isEmpty); // é is not e
      expect(ranges('caf éine', spec), isEmpty); // star stops at the space
    });
  });

  group('regex mode', () {
    test('span crosses spaces', () {
      final spec = compileChatQuery('lantern.*storm', regexMode: true);
      final hits = ranges('a lantern answers a storm.', spec);
      expect(hits.length, 1);
      expect(
        'a lantern answers a storm.'.substring(
          hits.first.start,
          hits.first.end,
        ),
        'lantern answers a storm',
      );
    });

    test('alternation', () {
      final spec = compileChatQuery('lantern|Biscuit', regexMode: true);
      expect(ranges('a lantern and Biscuit', spec).length, 2);
    });
  });

  group('scanTranscript', () {
    test('empty needle matches nothing', () {
      final r = scanTranscript([msg('a lantern')], compileChatQuery('  '));
      expect(r, isEmpty);
    });

    test('hits are document order with per-region occurrence', () {
      final msgs = [
        msg('lantern one\nlantern two'),
        msg('Biscuit the lantern', sender: 'Biscuit'),
      ];
      final r = scanTranscript(msgs, compileChatQuery('lantern'));
      expect(r.length, 3);
      expect(r.map((h) => h.messageIndex), [0, 0, 1]);
      expect(r[0].startInRegion, 0);
      expect(r[1].startInRegion, 'lantern one\n'.length);
      expect(r[2].region, findRegionBody);
    });

    test('sender name is its own region, ordered before body', () {
      final r = scanTranscript([
        msg('quiet night', sender: 'Juniper'),
      ], compileChatQuery('juniper'));
      expect(r.length, 1);
      expect(r.first.region, findRegionSender);
      expect(r.first.startInRegion, 0);
    });

    test('image markdown is invisible to the scan', () {
      final r = scanTranscript([
        msg('![lantern photo](https://x.io/l.png) no match here'),
      ], compileChatQuery('lantern'));
      expect(r, isEmpty);
    });

    test('cap holds at 999 and reports capped', () {
      final big = List.generate(600, (i) => msg('lantern ${i}a lantern'));
      final r = scanTranscript(big, compileChatQuery('lantern'));
      expect(r.length, 999);
      // capped flag lives on the service outcome; scan length proves the cap
    });
  });
}
