// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Tests for the @-mention autocomplete's pure helpers: the in-progress-token
// detector (mirrors the send-time matcher's boundary rules) and the
// candidate name filter. The panel itself is a thin ListView over these.

import 'package:flutter_test/flutter_test.dart';

import 'package:front_porch_ai/ui/chat_components/widgets/mention_autocomplete.dart';

void main() {
  group('MentionAutocomplete.activeMentionQuery', () {
    test('bare @ at start opens with an empty prefix', () {
      final q = MentionAutocomplete.activeMentionQuery('@', 1);
      expect(q, isNotNull);
      expect(q!.start, 0);
      expect(q.prefix, '');
    });

    test('typed prefix is captured and start points at the @', () {
      final q = MentionAutocomplete.activeMentionQuery('hey @Eve', 8);
      expect(q!.start, 4);
      expect(q.prefix, 'Eve');
    });

    test('cursor mid-text uses only the head', () {
      // Cursor right after "@Ma", trailing text ignored.
      final q = MentionAutocomplete.activeMentionQuery('@Ma and more', 3);
      expect(q!.start, 0);
      expect(q.prefix, 'Ma');
    });

    test('email-like @ never opens the popup', () {
      expect(MentionAutocomplete.activeMentionQuery('me@evelyn', 9), isNull);
      expect(MentionAutocomplete.activeMentionQuery('mail.me@x', 9), isNull);
    });

    test('a completed token (space after) closes the popup', () {
      expect(MentionAutocomplete.activeMentionQuery('@Evelyn hi', 10), isNull);
    });

    test('punctuation before @ still opens (,@ and [@)', () {
      expect(MentionAutocomplete.activeMentionQuery('hey,@Ev', 7), isNotNull);
      expect(MentionAutocomplete.activeMentionQuery('[@Ev', 4), isNotNull);
    });

    test('invalid cursor falls back to end of text', () {
      final q = MentionAutocomplete.activeMentionQuery('@Ma', -1);
      expect(q!.prefix, 'Ma');
    });

    test('accented prefixes stay in the token (unicode charset)', () {
      final q = MentionAutocomplete.activeMentionQuery('@Élo', 4);
      expect(q, isNotNull);
      expect(q!.prefix, 'Élo');
      expect(MentionAutocomplete.nameMatches('Élodie', 'élo'), isTrue);
    });
  });

  group('MentionAutocomplete.nameMatches', () {
    test('empty prefix matches everyone', () {
      expect(MentionAutocomplete.nameMatches('Mara Vance', ''), isTrue);
    });

    test('case-insensitive full-name and token prefix match', () {
      expect(MentionAutocomplete.nameMatches('Mara Vance', 'ma'), isTrue);
      expect(MentionAutocomplete.nameMatches('Mara Vance', 'van'), isTrue);
      expect(MentionAutocomplete.nameMatches('Mara Vance', 'MARA'), isTrue);
    });

    test('non-prefix substrings do not match', () {
      expect(MentionAutocomplete.nameMatches('Mara Vance', 'ara'), isFalse);
      expect(MentionAutocomplete.nameMatches('Evelyn', 'lyn'), isFalse);
    });
  });
}
