// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// WORLD Stoop tiles and detail sections: climate ON shows a CLIMATE pill
// and Climate/Traits sections; climate OFF shows LORE and a lore-only line.
// Source of truth is the .fpworld envelope on the card payload.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:front_porch_ai/providers/auth_state.dart';
import 'package:front_porch_ai/services/backporch/backporch.dart';
import 'package:front_porch_ai/ui/pages/repository/stoop_card_sections.dart';
import 'package:front_porch_ai/ui/pages/repository/stoop_card_tile.dart';

StoopCard _world({required Map<String, dynamic> envelope}) => StoopCard(
  id: 'w1',
  name: 'Mars Colony',
  summary: 'A dusty red frontier town.',
  type: 'WORLD',
  nsfw: false,
  score: 0,
  downloadCount: 0,
  modPick: false,
  creator: const StoopCreatorRef(id: 'c', displayName: 'author'),
  primaryAssetId: null,
  card: envelope,
);

Future<void> _pumpTile(WidgetTester tester, StoopCard card) async {
  await tester.pumpWidget(
    ChangeNotifierProvider<AuthState>(
      create: (_) => AuthState(),
      child: MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 220,
            height: 360,
            child: StoopCardTile(card: card, onTap: () {}),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

Future<void> _pumpSections(
  WidgetTester tester,
  Map<String, dynamic> envelope,
) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) =>
              ListView(children: stoopWorldSections(context, envelope)),
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets('WORLD tile with climate_enabled true shows WORLD+CLIMATE', (
    tester,
  ) async {
    await _pumpTile(tester, _world(envelope: {'climate_enabled': true}));
    expect(find.text('WORLD'), findsOneWidget);
    expect(find.text('CLIMATE'), findsOneWidget);
    expect(find.text('LORE'), findsNothing);
  });

  testWidgets('WORLD tile with climate_enabled false shows WORLD+LORE', (
    tester,
  ) async {
    await _pumpTile(tester, _world(envelope: {'climate_enabled': false}));
    expect(find.text('WORLD'), findsOneWidget);
    expect(find.text('LORE'), findsOneWidget);
    expect(find.text('CLIMATE'), findsNothing);
  });

  testWidgets('WORLD tile missing climate key defaults to CLIMATE', (
    tester,
  ) async {
    await _pumpTile(tester, _world(envelope: {'name': 'Old Place'}));
    expect(find.text('WORLD'), findsOneWidget);
    expect(find.text('CLIMATE'), findsOneWidget);
    expect(find.text('LORE'), findsNothing);
  });

  testWidgets(
    'stoopWorldSections climate off: lore-only line, no Climate/Traits',
    (tester) async {
      await _pumpSections(tester, {
        'name': 'Soul Society',
        'description': 'The afterlife realm.',
        'climate_enabled': false,
        'biome': {'displayName': 'leftover'},
        'place_traits': {'gravity': 'normal'},
      });
      expect(
        find.text('Lore only -- no climate, weather, or place traits.'),
        findsOneWidget,
      );
      expect(find.text('Climate'), findsNothing);
      expect(find.text('Traits'), findsNothing);
      expect(find.text('About this place'), findsOneWidget);
    },
  );

  testWidgets(
    'stoopWorldSections climate on: Climate present when biome has displayName',
    (tester) async {
      await _pumpSections(tester, {
        'name': 'Mars Colony',
        'description': 'Thin air, heavy dust.',
        'climate_enabled': true,
        'biome': {'displayName': 'Arid highland'},
      });
      expect(
        find.text('Lore only -- no climate, weather, or place traits.'),
        findsNothing,
      );
      expect(find.text('Climate'), findsOneWidget);
    },
  );
}
