// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Unit tests for the home-screen library sort helper. Pure functions over
// synthetic CharacterCards + caches — no DB, no widgets.

import 'package:flutter_test/flutter_test.dart';

import 'package:front_porch_ai/models/character_card.dart';
import 'package:front_porch_ai/utils/character_id.dart';
import 'package:front_porch_ai/utils/character_sort.dart';

CharacterCard _card(
  String name, {
  String? imagePath,
  DateTime? createdAt,
}) {
  final c = CharacterCard(name: name, imagePath: imagePath);
  c.createdAt = createdAt;
  return c;
}

List<String> _names(List<CharacterCard> cards) =>
    cards.map((c) => c.name).toList();

void main() {
  group('CharacterSortMode.fromKey', () {
    test('maps persisted keys and defaults unknowns to name', () {
      expect(CharacterSortMode.fromKey('recent'), CharacterSortMode.recent);
      expect(
        CharacterSortMode.fromKey('importDate'),
        CharacterSortMode.importDate,
      );
      expect(CharacterSortMode.fromKey('messages'), CharacterSortMode.messages);
      expect(CharacterSortMode.fromKey('name'), CharacterSortMode.name);
      expect(CharacterSortMode.fromKey('garbage'), CharacterSortMode.name);
    });
  });

  group('sortCharacters', () {
    test('name sorts case-insensitively and does not mutate the input', () {
      final input = [_card('bravo'), _card('Alpha'), _card('charlie')];
      final out = sortCharacters(input, CharacterSortMode.name);
      expect(_names(out), ['Alpha', 'bravo', 'charlie']);
      // Original list order is preserved (helper returns a copy).
      expect(_names(input), ['bravo', 'Alpha', 'charlie']);
    });

    test('recent orders by newest activity, then name for ties', () {
      final a = _card('Ann');
      final b = _card('Bo');
      final c = _card('Cy'); // no activity -> tie with any other inactive
      final d = _card('Ada'); // no activity
      final activity = {
        a.stableGroupId: DateTime(2026, 7, 1),
        b.stableGroupId: DateTime(2026, 7, 5),
      };
      final out = sortCharacters(
        [a, b, c, d],
        CharacterSortMode.recent,
        lastActivity: activity,
      );
      // Bo (Jul 5) > Ann (Jul 1) > the two inactive, name-tiebroken (Ada, Cy).
      expect(_names(out), ['Bo', 'Ann', 'Ada', 'Cy']);
    });

    test('messages orders by count desc, then name for ties', () {
      final a = _card('Ann');
      final b = _card('Bo');
      final c = _card('Cy');
      final counts = {a.stableGroupId: 3, b.stableGroupId: 10};
      // Cy has no entry -> 0.
      final out = sortCharacters(
        [a, b, c],
        CharacterSortMode.messages,
        messageCount: counts,
      );
      expect(_names(out), ['Bo', 'Ann', 'Cy']);
    });

    test('importDate uses DB createdAt, newest first', () {
      final a = _card('Ann', createdAt: DateTime(2026, 1, 1));
      final b = _card('Bo', createdAt: DateTime(2026, 6, 1));
      final c = _card('Cy', createdAt: DateTime(2026, 3, 1));
      final out = sortCharacters([a, b, c], CharacterSortMode.importDate);
      expect(_names(out), ['Bo', 'Cy', 'Ann']);
    });

    test(
      'importDate falls back to legacy filename epoch when createdAt is null',
      () {
        // No createdAt; ordering must come from the `<name>_<epoch>.png` tail.
        final older = _card('Older', imagePath: 'Older_1000.png');
        final newer = _card('Newer', imagePath: 'Newer_9000.png');
        final out = sortCharacters(
          [older, newer],
          CharacterSortMode.importDate,
        );
        expect(_names(out), ['Newer', 'Older']);
      },
    );

    test(
      'importDate: a real createdAt outranks any legacy-filename card, and '
      'nameless/dateless cards sink but stay name-ordered',
      () {
        final dated = _card('Dated', createdAt: DateTime(2020, 1, 1));
        final legacy = _card('Legacy', imagePath: 'Legacy_500.png');
        final none1 = _card('Zed'); // no createdAt, no epoch -> 0
        final none2 = _card('Abe'); // no createdAt, no epoch -> 0
        final out = sortCharacters(
          [none1, legacy, none2, dated],
          CharacterSortMode.importDate,
        );
        // Dated (2020) and Legacy (epoch 500ms = 1970) both beat the zero pile;
        // Dated's 2020 is newer than Legacy's 1970, so Dated first.
        expect(out.first.name, 'Dated');
        expect(out[1].name, 'Legacy');
        // The two true-zero cards trail, name-tiebroken.
        expect(_names(out.sublist(2)), ['Abe', 'Zed']);
      },
    );

    test('empty caches are safe and fall back to name order', () {
      final out = sortCharacters(
        [_card('B'), _card('A')],
        CharacterSortMode.recent,
      );
      expect(_names(out), ['A', 'B']);
    });
  });
}
