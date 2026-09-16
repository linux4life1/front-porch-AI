// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Hold punch list: climate-on miss must not become Temperate, name-miss
// leftover must not stick to a signed role, unsigned API cards are rejected.

import 'package:flutter_test/flutter_test.dart';

import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/chat/chat.dart';
import 'package:front_porch_ai/services/world_from_wiki/world_from_wiki.dart';

void main() {
  test('climate on + miss does not stamp Temperate', () {
    final world = worldFromWikiDraft(
      name: 'The quay',
      description: 'A notebook world.',
      entries: const [],
      climateEnabled: true,
    );
    expect(world.climateEnabled, isFalse);
    expect(world.biomeId, isNull);
    expect(world.biomeJson, isNull);
    expect(world.toJson()['climate_enabled'], isFalse);
    expect(world.toJson().containsKey('biome_id'), isFalse);
    expect(world.toJson().containsKey('biome_json'), isFalse);
    expect(
      Biome.resolve(biomeId: world.biomeId, biomeJson: world.biomeJson).id,
      Biome.temperate.id,
      reason: 'resolve still defaults, so climateEnabled must stay off',
    );
  });

  test('climate on + custom biome stays custom, not Temperate', () {
    final world = worldFromWikiDraft(
      name: 'The quay',
      description: 'A notebook world.',
      entries: const [],
      climateEnabled: true,
      biome: {
        'displayName': 'Southern current',
        'description': 'Warm sea under the hull.',
      },
    );
    expect(world.climateEnabled, isTrue);
    expect(world.biomeId, 'custom');
    expect(world.biomeJson, contains('Southern current'));
    expect(
      Biome.resolve(biomeId: world.biomeId, biomeJson: world.biomeJson).id,
      isNot(Biome.temperate.id),
    );
  });

  test('name miss does not stick leftover prose to the signed role', () {
    const card = WorldProposedCard(
      name: 'Mira the Scout',
      keys: ['Mira'],
      role: WorldCraftRole.leaf,
      sourceTitles: ['Ceolwynn'],
    );
    final drafts = matchWorldWriteBatch(
      const [card],
      const [
        WorldLoreWrite(
          name: 'Baker Street leftover',
          keys: ['baker'],
          content: 'Wrong quay oven prose for a scout.',
        ),
      ],
    );
    expect(drafts, isEmpty);
  });

  test('name hit still keeps the signed role', () {
    const card = WorldProposedCard(
      name: 'Mira the Scout',
      keys: ['Mira'],
      role: WorldCraftRole.leaf,
      sourceTitles: ['Ceolwynn'],
    );
    final drafts = matchWorldWriteBatch(
      const [card],
      const [
        WorldLoreWrite(
          name: 'Mira the Scout',
          keys: ['Mira'],
          content: 'She watches the quay from the roof.',
        ),
      ],
    );
    expect(drafts, hasLength(1));
    expect(drafts.single.role, WorldCraftRole.leaf);
    expect(drafts.single.content, contains('quay'));
  });

  test('unsigned or empty client card lists are rejected', () {
    expect(parseSignedWorldWriteCards(null), isEmpty);
    expect(parseSignedWorldWriteCards(<dynamic>[]), isEmpty);
    expect(
      parseSignedWorldWriteCards([
        {
          'name': 'Page 1',
          'role': 'hub',
          'sourceTitles': ['Page 1'],
        },
      ]),
      isEmpty,
      reason: 'unsigned ToC rows must not start a write',
    );
    final signed = parseSignedWorldWriteCards([
      {
        'name': "Baker's Street",
        'role': 'hub',
        'sourceTitles': ['Alnhama'],
        'signed': true,
      },
    ]);
    expect(signed, hasLength(1));
    expect(signed.single.name, "Baker's Street");
  });

  test('a ToC-sized signed dump is rejected', () {
    final dump = [
      for (var i = 0; i < kWorldScoutCardMax + 1; i++)
        {
          'name': 'Page $i',
          'role': 'hub',
          'sourceTitles': ['Page $i'],
          'signed': true,
        },
    ];
    expect(parseSignedWorldWriteCards(dump), isEmpty);
  });

  test('abort leftovers cannot be saved; written shelf can', () {
    final entry = LorebookEntry(
      name: "Baker's Street",
      keys: const ["Baker's Street"],
      content: 'They keep the quay oven lit.',
    );
    expect(
      worldFromWikiCanSave(aborted: true, lorebooksOn: true, entries: [entry]),
      isFalse,
    );
    expect(
      worldFromWikiCanSave(
        aborted: false,
        lorebooksOn: true,
        entries: const [],
      ),
      isFalse,
    );
    expect(
      worldFromWikiCanSave(aborted: false, lorebooksOn: true, entries: [entry]),
      isTrue,
    );
    expect(
      worldFromWikiCanSave(
        aborted: false,
        lorebooksOn: false,
        entries: const [],
      ),
      isTrue,
    );
  });
}
