// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/waifu/waifu.dart';

/// A session follows its own library card, not whichever card shares its
/// name.
void main() {
  final miraA = CharacterCard(name: 'Mira', personality: 'A')..dbId = 'a';
  final miraB = CharacterCard(name: 'Mira', personality: 'B')..dbId = 'b';

  test('two cards with the same name: the id picks the right one', () {
    final saved = CharacterCard(name: 'Mira')..dbId = 'b';
    expect(waifuFindCard([miraA, miraB], saved), same(miraB));
  });

  test('a renamed card is still found by its id', () {
    final renamed = CharacterCard(name: 'Mira Two')..dbId = 'a';
    final saved = CharacterCard(name: 'Mira')..dbId = 'a';
    expect(waifuFindCard([miraB, renamed], saved), same(renamed));
  });

  test('a deleted card does not fall back to a namesake', () {
    final saved = CharacterCard(name: 'Mira')..dbId = 'gone';
    expect(waifuFindCard([miraA, miraB], saved), isNull);
  });

  test('a session saved before ids still matches by name', () {
    expect(waifuFindCard([miraA], CharacterCard(name: 'Mira')), same(miraA));
  });

  test('the wizard highlights only the picked card', () {
    expect(waifuSameCard(miraA, miraB), isFalse);
    expect(
      waifuSameCard(miraA, CharacterCard(name: 'Mira')..dbId = 'a'),
      isTrue,
    );
    expect(waifuSameCard(miraA, CharacterCard(name: 'Mira')), isTrue);
  });
}
