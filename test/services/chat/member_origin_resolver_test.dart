// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Phase 1 of the "one chat, changing cast" unification: pins the best-effort
// rules that reconnect a group member back to its origin library character
// (stamped origin first, unique case-insensitive name fallback, conservative
// null on any ambiguity).

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/models/character_card.dart';
import 'package:front_porch_ai/services/chat/member_origin_resolver.dart';

/// Build a library card whose stableGroupId is the image basename ([id]), or the
/// sanitized name when [id] is omitted.
CharacterCard _card(String name, {String? id}) =>
    CharacterCard(name: name, imagePath: id != null ? '/lib/$id.png' : null);

void main() {
  group('MemberOriginResolver', () {
    final aria = _card('Aria', id: 'aria_card');
    final bob = _card('Bob', id: 'bob');
    final library = [aria, bob];

    test('stamped origin present in library → returns that card', () {
      final r = MemberOriginResolver.resolve(
        stampedOriginStableId: 'aria_card',
        memberName: 'Aria',
        libraryCharacters: library,
      );
      expect(r, same(aria));
    });

    test('stamped origin wins over a different unique name match', () {
      final r = MemberOriginResolver.resolve(
        stampedOriginStableId: 'aria_card',
        memberName: 'Bob', // deliberately a different name
        libraryCharacters: library,
      );
      expect(r, same(aria)); // stamp is authoritative, not Bob
    });

    test('legacy (no stamp) + unique name → name match (case-insensitive)', () {
      final r = MemberOriginResolver.resolve(
        stampedOriginStableId: null,
        memberName: 'bob',
        libraryCharacters: library,
      );
      expect(r, same(bob));
    });

    test('legacy + ambiguous name → null', () {
      final aria2 = _card('Aria', id: 'aria_2');
      final r = MemberOriginResolver.resolve(
        stampedOriginStableId: null,
        memberName: 'Aria',
        libraryCharacters: [aria, aria2],
      );
      expect(r, isNull);
    });

    test('legacy + no name match → null', () {
      final r = MemberOriginResolver.resolve(
        stampedOriginStableId: null,
        memberName: 'Nobody',
        libraryCharacters: library,
      );
      expect(r, isNull);
    });

    test('blank stamp is treated as no stamp → name fallback', () {
      final r = MemberOriginResolver.resolve(
        stampedOriginStableId: '   ',
        memberName: 'Aria',
        libraryCharacters: library,
      );
      expect(r, same(aria));
    });

    test('stamped origin missing from library → best-effort unique name match', () {
      final r = MemberOriginResolver.resolve(
        stampedOriginStableId: 'deleted_card_id',
        memberName: 'Bob',
        libraryCharacters: library,
      );
      expect(r, same(bob)); // stamp not found → name fallback
    });

    test('stamped origin missing + ambiguous name → null', () {
      final aria2 = _card('Aria', id: 'aria_2');
      final r = MemberOriginResolver.resolve(
        stampedOriginStableId: 'deleted_card_id',
        memberName: 'Aria',
        libraryCharacters: [aria, aria2],
      );
      expect(r, isNull);
    });

    test('empty/blank member name + no stamp → null', () {
      expect(
        MemberOriginResolver.resolve(
          stampedOriginStableId: null,
          memberName: '   ',
          libraryCharacters: library,
        ),
        isNull,
      );
    });

    test('name match trims whitespace and ignores case', () {
      final r = MemberOriginResolver.resolve(
        stampedOriginStableId: null,
        memberName: '  ARIA  ',
        libraryCharacters: library,
      );
      expect(r, same(aria));
    });

    test('empty library → null even with a stamp', () {
      expect(
        MemberOriginResolver.resolve(
          stampedOriginStableId: 'aria_card',
          memberName: 'Aria',
          libraryCharacters: const [],
        ),
        isNull,
      );
    });
  });
}
