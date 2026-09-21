// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

// Group injection is Swap for character lore too: only the speaking
// card's book, plus group/world lore. Proven red: pass both members
// without speaker and Senjumaru's present-scene row lands on Zinna.

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/chat/lorebook_collection.dart';

const kZinnaScene = 'ZINNA_PRESENT_SCENE_MARKER porch dusk';
const kSenjuScene =
    'SENJUMARU_PRESENT_SCENE_MARKER Present scene: Living World riverside path';
const kGroupWiki = 'GROUP_LORE_MARKER shared porch wiki';
const kWorldWiki = 'WORLD_LORE_MARKER Seireitei geography';

CharacterCard _card(String name, String scene) => CharacterCard(
  name: name,
  lorebook: Lorebook(
    entries: [LorebookEntry(content: scene, constant: true, name: name)],
  ),
);

void main() {
  final zinna = _card('Zinna', kZinnaScene);
  final senju = _card('Senjumaru', kSenjuScene);
  final groupBook = Lorebook(
    entries: [LorebookEntry(content: kGroupWiki, constant: true, name: 'g')],
  );
  final world = World(
    name: 'Living World',
    lorebook: Lorebook(
      entries: [LorebookEntry(content: kWorldWiki, constant: true, name: 'w')],
    ),
  );

  String blob(List<LoreEntryRef> refs) =>
      [for (final r in refs) r.entry.content].join('\n');

  test('Zinna as speaker does not inherit Senjumaru present-scene lore', () {
    final refs = collectLoreEntryRefs(
      characters: [zinna, senju],
      groupLorebook: groupBook,
      chatWorldIds: const ['Living World'],
      resolveWorld: (id) => id == 'Living World' ? world : null,
      inherit: true,
      speaker: zinna,
    );
    final text = blob(refs);
    expect(text, contains(kZinnaScene));
    expect(text, contains(kGroupWiki));
    expect(text, contains(kWorldWiki));
    expect(text, isNot(contains(kSenjuScene)));
  });

  test("Senjumaru's turn may inject her own present-scene lore", () {
    final refs = collectLoreEntryRefs(
      characters: [zinna, senju],
      groupLorebook: groupBook,
      resolveWorld: (_) => null,
      inherit: true,
      speaker: senju,
    );
    final text = blob(refs);
    expect(text, contains(kSenjuScene));
    expect(text, contains(kGroupWiki));
    expect(text, isNot(contains(kZinnaScene)));
  });

  test('scanner (no speaker) still enumerates every member book', () {
    final refs = collectLoreEntryRefs(
      characters: [zinna, senju],
      resolveWorld: (_) => null,
      inherit: true,
    );
    final text = blob(refs);
    expect(text, contains(kZinnaScene));
    expect(text, contains(kSenjuScene));
  });

  test('unknown speaker injects no character books', () {
    final refs = collectLoreEntryRefs(
      characters: [zinna, senju],
      groupLorebook: groupBook,
      resolveWorld: (_) => null,
      inherit: true,
      speaker: CharacterCard(name: 'NotInCast'),
    );
    final text = blob(refs);
    expect(text, contains(kGroupWiki));
    expect(text, isNot(contains(kZinnaScene)));
    expect(text, isNot(contains(kSenjuScene)));
  });

  test('inherit off injects no character books even with a speaker', () {
    final refs = collectLoreEntryRefs(
      characters: [zinna, senju],
      groupLorebook: groupBook,
      resolveWorld: (_) => null,
      inherit: false,
      speaker: zinna,
    );
    final text = blob(refs);
    expect(text, contains(kGroupWiki));
    expect(text, isNot(contains(kZinnaScene)));
    expect(text, isNot(contains(kSenjuScene)));
  });
}
