// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Role recipe + homemade group slug. Not a series-specific fixture.

import 'package:flutter_test/flutter_test.dart';

import 'package:front_porch_ai/services/llm_service.dart';
import 'package:front_porch_ai/services/world_from_wiki/world_from_wiki.dart';

WorldCraftDraft _d({
  required String name,
  required WorldCraftRole role,
  String group = '',
  String content = 'They keep the quay oven lit through the wet season.',
}) {
  return WorldCraftDraft(
    name: name,
    keys: [name],
    content: content,
    role: role,
    group: group,
  );
}

void main() {
  test('era / hub / leaf / crown field recipe', () {
    final out = applyWorldCraftMechanics([
      _d(name: 'The baking years', role: WorldCraftRole.era),
      _d(name: "Baker's Street", role: WorldCraftRole.hub),
      _d(name: 'Mira the Scout', role: WorldCraftRole.leaf),
      _d(name: 'The Crown Oven', role: WorldCraftRole.crown),
    ]);
    expect(out, hasLength(4));

    final era = out.singleWhere((e) => e.name == 'The baking years');
    expect(era.constant, isTrue);
    expect(era.ignoreBudget, isTrue);
    expect(era.preventRecursion, isTrue);
    expect(era.sticky, 0);
    expect(era.order, 1);
    expect(era.depth, 4);
    expect(era.useRegex, isFalse);
    expect(era.group, isEmpty);

    final hub = out.singleWhere((e) => e.name == "Baker's Street");
    expect(hub.constant, isFalse);
    expect(hub.ignoreBudget, isFalse);
    expect(hub.preventRecursion, isFalse);
    expect(hub.sticky, 3);
    expect(hub.order, inInclusiveRange(145, 210));

    final leaf = out.singleWhere((e) => e.name == 'Mira the Scout');
    expect(leaf.constant, isFalse);
    expect(leaf.preventRecursion, isTrue);
    expect(leaf.sticky, 2);
    expect(leaf.order, inInclusiveRange(60, 140));

    final crown = out.singleWhere((e) => e.name == 'The Crown Oven');
    expect(crown.preventRecursion, isTrue);
    expect(crown.sticky, 2);
    expect(crown.order, inInclusiveRange(240, 250));
  });

  test('group slug round-trips from the scout string', () {
    final out = applyWorldCraftMechanics([
      _d(
        name: 'The River Faith',
        role: WorldCraftRole.hub,
        group: 'river-faith',
      ),
      _d(
        name: 'Mira the Scout',
        role: WorldCraftRole.leaf,
        group: 'river-faith',
      ),
    ]);
    expect(out.map((e) => e.group), everyElement('river-faith'));
    expect(out.every((e) => e.groupOverride), isTrue);
  });

  test('never hub and crown in one group — hub is ungrouped', () {
    final out = applyWorldCraftMechanics([
      _d(
        name: "Baker's Street",
        role: WorldCraftRole.hub,
        group: 'river-faith',
      ),
      _d(
        name: 'The Crown Oven',
        role: WorldCraftRole.crown,
        group: 'river-faith',
      ),
    ]);
    expect(out.singleWhere((e) => e.name == "Baker's Street").group, isEmpty);
    expect(
      out.singleWhere((e) => e.name == 'The Crown Oven').group,
      'river-faith',
    );
  });

  test('at most one era; extras become hub', () {
    final out = applyWorldCraftMechanics([
      _d(name: 'The baking years', role: WorldCraftRole.era),
      _d(name: 'A second era', role: WorldCraftRole.era),
    ]);
    expect(out[0].constant, isTrue);
    expect(out[0].order, 1);
    expect(out[1].constant, isFalse);
    expect(out[1].preventRecursion, isFalse);
    expect(out[1].order, inInclusiveRange(145, 210));
  });

  test('homemade scout cards parse against this index', () {
    final cards = parseWorldScoutToolCalls(
      [
        LlmToolCall(
          name: kWorldScoutToolName,
          arguments: {
            'cards': [
              {
                'name': "Baker's Street",
                'keys': "Baker's Street, the street",
                'role': 'hub',
                'sourceTitles': ["Baker's Street", "Baker's Street (draft)"],
              },
              {
                'name': 'The River Faith',
                'role': 'hub',
                'sourceTitles': ['The River Faith'],
                'group': 'river-faith',
              },
              {
                'name': 'Mira the Scout',
                'role': 'leaf',
                'sourceTitles': ['Mira the Scout', 'Chapter 1: Mira'],
                'group': 'river-faith',
              },
              {
                'name': 'Missing page',
                'role': 'leaf',
                'sourceTitles': ['Not in this book'],
              },
            ],
          },
        ),
      ],
      catalog: [
        "Baker's Street",
        "Baker's Street (draft)",
        'The River Faith',
        'Mira the Scout',
        'Chapter 1: Mira',
      ],
    );
    expect(cards, hasLength(3));
    expect(cards.map((c) => c.name), isNot(contains('Missing page')));
    expect(
      cards.singleWhere((c) => c.name == 'Mira the Scout').group,
      'river-faith',
    );
    expect(cards.singleWhere((c) => c.name == "Baker's Street").sourceTitles, [
      "Baker's Street",
      "Baker's Street (draft)",
    ]);
  });

  test('scout remaps source titles to the index casing', () {
    final cards = parseWorldScoutToolCalls(
      [
        LlmToolCall(
          name: kWorldScoutToolName,
          arguments: {
            'cards': [
              {
                'name': "Baker's Street",
                'role': 'hub',
                'sourceTitles': ["baker's street"],
              },
            ],
          },
        ),
      ],
      catalog: ["Baker's Street"],
    );
    expect(cards.single.sourceTitles, ["Baker's Street"]);
  });
}
