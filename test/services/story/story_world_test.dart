// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// This file is part of Front Porch AI.
//
// Front Porch AI is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// Front Porch AI is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
// GNU Affero General Public License for more details.
//
// You should have received a copy of the GNU Affero General Public License
// along with Front Porch AI. If not, see <https://www.gnu.org/licenses/>.

// Stories set in Worlds, slice 1 (docs/design/stories-in-worlds.md §6):
// the project remembers its world, StoryWorldBrief turns a world into the
// setting brief and story lore, and the bible appends its lore to what
// grounds the story instead of replacing it.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/story/story_lore_index.dart';
import 'package:front_porch_ai/services/story/story_world_brief.dart';
import 'package:front_porch_ai/services/story/story_world_context.dart';
import 'package:front_porch_ai/services/story/studio_parse.dart';

/// Greenhollow Estate from the shipped starter asset: a root with six
/// keyword entries and three places with five more between them.
({World root, List<World> places}) greenhollow() {
  final raw = jsonDecode(
    File('assets/worlds/starter/greenhollow.fpworld').readAsStringSync(),
  );
  final pkg = decodeFpWorld(Map<String, dynamic>.from(raw as Map));
  // The importer, not the decoder, writes the envelope's biome onto the row.
  final root = pkg.world..biomeId = pkg.biome?['id']?.toString();
  final places = [
    for (final child in pkg.locations)
      decodeFpWorld(child).world..parentWorldId = root.id,
  ];
  return (root: root, places: places);
}

World world(
  String name, {
  String? parent,
  String description = '',
  List<LorebookEntry> entries = const [],
  bool climate = true,
}) => World(
  id: name.toLowerCase().replaceAll(' ', '-'),
  name: name,
  description: description,
  parentWorldId: parent,
  climateEnabled: climate,
  lorebook: Lorebook(entries: [...entries]),
);

LorebookEntry entry(String name, String content, {bool constant = false}) =>
    LorebookEntry(
      name: name,
      keys: [name],
      content: content,
      constant: constant,
    );

StoryLoreEntry fileEntry() => StoryLoreEntry(
  topic: 'Ledger (1)',
  detail: 'Wages paid quarterly.',
  relatedTo: const ['file:ledger.txt'],
);

void main() {
  group('StoryProject world fields', () {
    test('world_id, world_name and a scene place_id round-trip', () {
      final p = StoryProject(
        title: 'The Locked Library',
        worldId: 'conservatory',
        worldName: 'Greenhollow Estate',
      );
      p.acts = [StoryAct(number: 1, title: 'One', description: '')];
      p.scenes[0] = [
        StoryScene(number: 1, location: 'The Kitchens', placeId: 'kitchens'),
      ];
      final back = StoryProject.fromJson(jsonDecode(p.toJsonString()));
      expect(back.worldId, 'conservatory');
      expect(back.worldName, 'Greenhollow Estate');
      expect(back.scenes[0]!.single.placeId, 'kitchens');
      expect(back.scenes[0]!.single.location, 'The Kitchens');
    });

    test('an older project has no world and its scenes no place', () {
      final json = StoryProject(title: 'Old').toJson()
        ..remove('world_id')
        ..remove('world_name');
      final back = StoryProject.fromJson(json);
      expect(back.worldId, isNull);
      expect(back.worldName, '');
      expect(StoryScene.fromJson({'number': 1}).placeId, '');
      expect(back.toJson().containsKey('world_id'), isFalse);
    });
  });

  group('StoryWorldBrief on Greenhollow Estate', () {
    final g = greenhollow();
    final start = g.places.firstWhere((p) => p.id == g.root.defaultPlaceId);
    final brief = StoryWorldBrief(chain: [start, g.root], places: g.places);

    test('the brief names the world, its climate and every place', () {
      final text = brief.brief();
      expect(text, startsWith('World: Greenhollow Estate'));
      expect(text, contains('Climate: Mediterranean.'));
      expect(text, contains('the story starts at The Conservatory'));
      expect(text, contains('- The Conservatory (start):'));
      expect(text, contains('- The Kitchens:'));
      expect(text, contains('- The Old Orchard:'));
      expect(text.length, lessThanOrEqualTo(kStoryWorldBriefChars));
      // No entry in the starter book is constant, so nothing is inlined.
      expect(text, isNot(contains('Always true:')));
      expect(brief.constantCount, 0);
      expect(brief.searchableCount, 11);
    });

    test('its book becomes eleven tagged lore entries, root first', () {
      final lore = brief.loreEntries();
      expect(lore, hasLength(11));
      expect(lore.first.topic, 'The Greenhollow family');
      for (final e in lore) {
        expect(e.relatedTo, contains(StoryWorldBrief.worldTag(g.root.id)));
        expect(e.relatedTo.where((r) => r.startsWith('place:')), hasLength(1));
        expect(isWorldLore(e), isTrue);
        expect(isGroundingLore(e), isTrue);
      }
      final conservatory = lore.where(
        (e) => e.relatedTo.contains(StoryWorldBrief.placeTag(start.id)),
      );
      expect(conservatory, hasLength(2));
      expect(
        lore.where(
          (e) => e.relatedTo.contains(StoryWorldBrief.placeTag(g.root.id)),
        ),
        hasLength(6),
      );
    });

    test('place names resolve ignoring case; the root counts as a place', () {
      expect(brief.placeNamed('the kitchens')?.name, 'The Kitchens');
      expect(brief.placeNamed('Greenhollow Estate')?.id, g.root.id);
      expect(brief.placeNamed('the Gatehouse'), isNull);
      expect(brief.placeNames, hasLength(4));
    });

    test(
      'chainTo walks a place to the root; an unknown place is the world',
      () {
        final kitchens = g.places.firstWhere((p) => p.name == 'The Kitchens');
        expect(brief.chainTo(kitchens.id).map((w) => w.name), [
          'The Kitchens',
          'Greenhollow Estate',
        ]);
        expect(brief.chainTo('').map((w) => w.name), ['Greenhollow Estate']);
        expect(brief.chainTo('gatehouse').map((w) => w.name), [
          'Greenhollow Estate',
        ]);
        expect(brief.placesBody(), contains('(the world at large)'));
        expect(brief.placesBody(), contains('- The Old Orchard: Rows of'));
      },
    );

    test('settingNow is the chain prose without the chat header, and the '
        'preferred tags run nearest first', () {
      final kitchens = g.places.firstWhere((p) => p.name == 'The Kitchens');
      final scene = StoryScene(number: 1, placeId: kitchens.id);
      final now = StoryWorldContext.settingNow(brief, scene);
      expect(now, startsWith('The Kitchens: Big flagstoned kitchens'));
      expect(now, contains('\nGreenhollow Estate: A rambling'));
      expect(now, isNot(contains('Setting — where you are')));
      expect(StoryWorldContext.preferTags(brief, scene), [
        StoryWorldBrief.placeTag(kitchens.id),
        StoryWorldBrief.placeTag(g.root.id),
      ]);
      final nowhere = StoryWorldBrief(chain: const [], places: const []);
      expect(StoryWorldContext.settingNow(nowhere, scene), '');
      expect(StoryWorldContext.preferTags(nowhere, scene), isEmpty);
    });

    test('resolvePlace: a known name sets the id, new: keeps the name, '
        'free text stays free', () {
      final kitchens = g.places.firstWhere((p) => p.name == 'The Kitchens');
      final a = StoryScene(number: 1, location: 'Dawn, the oven lit');
      StoryWorldContext.resolvePlace(brief, a, 'the kitchens');
      expect(a.placeId, kitchens.id);
      expect(a.location, 'The Kitchens — Dawn, the oven lit');

      final b = StoryScene(number: 2, location: 'The Kitchens at dusk');
      StoryWorldContext.resolvePlace(brief, b, 'The Kitchens');
      expect(b.location, 'The Kitchens at dusk');

      final c = StoryScene(number: 3, location: 'Dusk');
      StoryWorldContext.resolvePlace(brief, c, 'new: the Gatehouse');
      expect(c.placeId, '');
      expect(c.location, 'the Gatehouse — Dusk');

      final d = StoryScene(number: 4, location: 'A road');
      StoryWorldContext.resolvePlace(brief, d, 'Somewhere else');
      expect(d.placeId, '');
      expect(d.location, 'A road');

      final e = StoryScene(number: 5, location: '');
      StoryWorldContext.resolvePlace(brief, e, 'The Old Orchard — noon');
      expect(e.placeId, isNot(''));
      expect(e.location, 'The Old Orchard — noon');
    });

    test('a root picked directly starts the story in the world at large', () {
      final atLarge = StoryWorldBrief(chain: [g.root], places: g.places);
      expect(
        atLarge.brief(),
        contains('starts in Greenhollow Estate at large'),
      );
      expect(atLarge.brief(), isNot(contains('(start)')));
    });
  });

  group('StoryWorldBrief rules', () {
    test('a deleted world is an empty brief and no lore', () {
      final gone = StoryWorldBrief(chain: const [], places: const []);
      expect(gone.isEmpty, isTrue);
      expect(gone.brief(), '');
      expect(gone.loreEntries(), isEmpty);
      expect(gone.placeNames, isEmpty);
    });

    test(
      '{{user}} and {{char}} resolve on copy; {{char}} waits for a lead',
      () {
        final town = world(
          'Bletchfield',
          entries: [
            entry('Tea Rooms', '{{user}} first met {{char}} in the Tea Rooms.'),
          ],
        );
        final brief = StoryWorldBrief(chain: [town], places: const []);
        expect(
          brief
              .loreEntries(userName: 'Sam', charName: 'Yoruichi')
              .single
              .detail,
          'Sam first met Yoruichi in the Tea Rooms.',
        );
        final noPersona = brief.loreEntries().single.detail;
        expect(noPersona, startsWith('$kStoryWorldNoPersona first met'));
        expect(noPersona, contains('{{char}}'));
        expect(noPersona, isNot(contains('{{user}}')));
      },
    );

    test('constant entries are inlined; disabled ones never copy', () {
      final era = entry(
        'The war',
        'It is the first winter of the war.',
        constant: true,
      );
      final off = entry('Secret', 'Hidden.')..enabled = false;
      final w = world('Reach', entries: [era, off, entry('Dock', 'A dock.')]);
      final brief = StoryWorldBrief(chain: [w], places: const []);
      expect(
        brief.brief(),
        contains('Always true:\n- The war: It is the first'),
      );
      expect(brief.loreEntries().map((e) => e.topic), ['The war', 'Dock']);
    });

    test('the climate line comes from the chain author and carries traits', () {
      final moon = world('Kestrel', climate: true)
        ..biomeId = 'desert'
        ..atmosphere = WorldAtmosphere.unbreathable
        ..gravity = WorldGravity.low;
      final dome = world('Dome', parent: 'kestrel', climate: false);
      final brief = StoryWorldBrief(chain: [dome, moon], places: [dome]);
      final text = brief.brief();
      expect(text, contains('Climate: Desert.'));
      expect(text, contains('The air is unbreathable'));
      expect(text, contains('Gravity is low'));
      final loreOnly = StoryWorldBrief(
        chain: [world('Shelf', climate: false)],
        places: const [],
      );
      expect(loreOnly.brief(), isNot(contains('Climate:')));
    });

    test('a long world gives up its description before its facts, then '
        'facts from the end, and stays under the cap', () {
      final big = world(
        'Vast',
        description: 'Prose. ' * 800,
        entries: [
          for (var i = 0; i < 40; i++)
            entry('Fact $i', 'Detail ${'x' * 120}', constant: true),
        ],
      );
      final brief = StoryWorldBrief(chain: [big], places: const []);
      final text = brief.brief();
      expect(text.length, lessThanOrEqualTo(kStoryWorldBriefChars));
      expect(text, contains('- Fact 0:'));
      expect(text, isNot(contains('- Fact 39:')));
      expect(text, isNot(contains('Prose. Prose.')));
    });

    test('the place tree indents rooms under their place', () {
      final town = world('Town');
      final hall = world('Hall', parent: 'town', description: 'Big. Old.');
      final attic = world('Attic', parent: 'hall');
      final brief = StoryWorldBrief(
        chain: [attic, hall, town],
        places: [hall, attic],
      );
      expect(brief.brief(), contains('- Hall: Big. Old.\n  - Attic (start)'));
    });
  });

  group('StoryLoreIndex with preferred tags', () {
    final index = StoryLoreIndex(null);
    final entries = [
      StoryLoreEntry(
        topic: 'The bread oven',
        detail: 'Lit before dawn.',
        relatedTo: const ['world:g', 'place:kitchens'],
      ),
      StoryLoreEntry(
        topic: 'The bell',
        detail: 'Rings at ten.',
        relatedTo: const ['world:g', 'place:g'],
      ),
      StoryLoreEntry(
        topic: 'The night vine',
        detail: 'Opens after dark.',
        relatedTo: const ['world:g', 'place:conservatory'],
      ),
      StoryLoreEntry(
        topic: 'The library key',
        detail: 'Two keys hang on the cook\'s ring in the kitchens.',
      ),
    ];

    test('the scene\'s place comes first, its parent next, then the best '
        'match; another room never jumps the queue', () async {
      final hits = await index.search(
        'the cook and the key in the kitchens',
        entries,
        limit: 4,
        preferTags: const ['place:kitchens', 'place:g'],
      );
      expect(hits.map((h) => h.entry.topic), [
        'The bread oven',
        'The bell',
        'The library key',
      ]);
    });

    test('place entries take at most half the slots', () async {
      final hits = await index.search(
        'the key in the kitchens',
        [
          ...entries,
          StoryLoreEntry(
            topic: 'The copper pans',
            detail: 'Twelve of them.',
            relatedTo: const ['world:g', 'place:kitchens'],
          ),
        ],
        limit: 2,
        preferTags: const ['place:kitchens'],
      );
      expect(hits.length, 2);
      expect(hits.first.entry.relatedTo, contains('place:kitchens'));
      expect(hits.last.entry.topic, 'The library key');
    });

    test('without tags the search is what it was', () async {
      final hits = await index.search('the library key', entries, limit: 4);
      expect(hits.map((h) => h.entry.topic), ['The library key']);
    });
  });

  group('lore merge rules', () {
    final fromWorld = [
      StoryLoreEntry(
        topic: 'The bell',
        detail: 'Ten o\'clock.',
        relatedTo: const ['world:g', 'place:g'],
      ),
    ];

    test(
      'mergeParsedLore keeps uploads and the world, appends the rest once',
      () {
        final merged = mergeParsedLore(
          [
            fileEntry(),
            ...fromWorld,
            StoryLoreEntry(topic: 'Old', detail: 'x'),
          ],
          [
            StoryLoreEntry(topic: 'the BELL', detail: 'a duplicate'),
            StoryLoreEntry(topic: 'The key', detail: 'Two keys.'),
            StoryLoreEntry(topic: '', detail: 'no topic'),
          ],
        );
        expect(merged.map((e) => e.topic), [
          'Ledger (1)',
          'The bell',
          'The key',
        ]);
      },
    );

    test('the Studio bible appends <world_lore> to the world\'s entries', () {
      final p = StoryProject(title: 'T')..lore = [...fromWorld, fileEntry()];
      StudioParse.applyFoundation(p, '''
<response>
  <status_quo>A house.</status_quo>
  <character_briefs><brief><name>Marigold</name><role>Protagonist</role>
  <description>The housekeeper.</description></brief></character_briefs>
  <world_lore>
    <entry><topic>The key</topic><detail>Two keys.</detail></entry>
    <entry><topic>The Bell</topic><detail>Already known.</detail></entry>
  </world_lore>
</response>''');
      expect(p.lore.map((e) => e.topic), ['The bell', 'Ledger (1)', 'The key']);
      expect(p.lore.first.relatedTo, contains('world:g'));
    });

    test('refresh replaces world entries and keeps story-grown ones', () {
      final grown = StoryLoreEntry(topic: 'The key', detail: 'Two keys.');
      final newer = StoryLoreEntry(
        topic: 'The bell',
        detail: 'Half past ten now.',
        relatedTo: const ['world:g', 'place:g'],
      );
      final out = StoryWorldBrief.refresh(
        [...fromWorld, grown, fileEntry()],
        [newer],
      );
      expect(out.map((e) => e.detail), [
        'Half past ten now.',
        'Two keys.',
        'Wages paid quarterly.',
      ]);
    });
  });

  // Found in the live review of 2026-10-28: a world with no places lists
  // itself as "the world at large", the planner picks it for every scene,
  // and each row then read "<World> — <room>". The header already names
  // the world; only a place inside it prefixes the location.
  test('a scene set in the world at large keeps its location bare', () {
    final g = greenhollow();
    final atLarge = StoryWorldBrief(chain: [g.root], places: const []);
    final a = StoryScene(number: 1, location: 'The night desk, one lamp');
    StoryWorldContext.resolvePlace(atLarge, a, 'Greenhollow Estate');
    expect(a.placeId, g.root.id);
    expect(a.location, 'The night desk, one lamp');

    // A real place inside still earns its prefix.
    final kitchens = g.places.firstWhere((p) => p.name == 'The Kitchens');
    final full = StoryWorldBrief(chain: [g.root], places: g.places);
    final b = StoryScene(number: 2, location: 'Dawn, the oven lit');
    StoryWorldContext.resolvePlace(full, b, 'The Kitchens');
    expect(b.placeId, kitchens.id);
    expect(b.location, 'The Kitchens — Dawn, the oven lit');
  });
}
