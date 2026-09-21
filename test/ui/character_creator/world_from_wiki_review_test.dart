// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Review is a signed shelf of proposed cards. No select-all.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:front_porch_ai/services/world_from_wiki/world_from_wiki.dart';
import 'package:front_porch_ai/ui/character_creator/world_from_wiki/steps/review_step.dart';
import 'package:front_porch_ai/ui/character_creator/world_from_wiki/world_from_wiki_state.dart';

void main() {
  testWidgets('review shelf defaults unsigned and has no select-all', (
    tester,
  ) async {
    final state = WorldFromWikiState();
    addTearDown(state.disposeControllers);
    state.proposed = [
      const WorldProposedCard(
        name: "Baker's Street",
        keys: ["Baker's Street"],
        role: WorldCraftRole.hub,
        sourceTitles: ["Baker's Street"],
      ),
      const WorldProposedCard(
        name: 'Mira the Scout',
        keys: ['Mira'],
        role: WorldCraftRole.leaf,
        sourceTitles: ['Mira the Scout'],
        group: 'river-faith',
      ),
    ];
    state.catalogTitleCount = 80;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: WorldFromWikiReviewStep(state: state)),
      ),
    );

    expect(find.text('All'), findsNothing);
    expect(find.text("Baker's Street"), findsOneWidget);
    expect(find.textContaining('river-faith'), findsOneWidget);
    expect(state.signed, isEmpty);

    await tester.tap(find.byType(CheckboxListTile).first);
    await tester.pump();
    expect(state.signed, {0});
    expect(state.signedCards, hasLength(1));
    expect(state.signedCards.single.name, "Baker's Street");
  });
}
