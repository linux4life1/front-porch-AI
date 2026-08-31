// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// This file is part of Front Porch AI.
//
// Front Porch AI is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:front_porch_ai/providers/auth_state.dart';
import 'package:front_porch_ai/services/backporch/backporch.dart';
import 'package:front_porch_ai/ui/pages/repository/repository.dart';

StoopCard _world({
  Map<String, dynamic> card = const {},
  bool? climateEnabled,
}) => StoopCard(
  id: 'world-1',
  name: 'Lore Shelf',
  summary: 'A place made of facts.',
  type: 'WORLD',
  nsfw: false,
  score: 0,
  downloadCount: 0,
  modPick: false,
  creator: const StoopCreatorRef(id: 'creator-1', displayName: 'Sosuke Aizen'),
  primaryAssetId: null,
  card: card,
  climateEnabled: climateEnabled,
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

void main() {
  group('Stoop WORLD list climate DTO', () {
    test('parses camel and snake flags without a card envelope', () {
      final camel = StoopCard.fromJson({
        'id': 'camel',
        'type': 'WORLD',
        'climateEnabled': false,
      });
      final snake = StoopCard.fromJson({
        'id': 'snake',
        'type': 'WORLD',
        'climate_enabled': true,
      });

      expect(camel.card, isEmpty);
      expect(camel.climateEnabled, isFalse);
      expect(stoopCardClimateEnabled(camel), isFalse);
      expect(snake.climateEnabled, isTrue);
      expect(stoopCardClimateEnabled(snake), isTrue);
      expect(
        camel.withStats(score: 1, downloadCount: 2).climateEnabled,
        isFalse,
      );
    });

    test('an omitted empty envelope never invents climate', () {
      final card = StoopCard.fromJson({'id': 'old-list', 'type': 'WORLD'});

      expect(card.card, isEmpty);
      expect(card.climateEnabled, isNull);
      expect(stoopCardClimateEnabled(card), isFalse);
    });

    test('a genuine legacy envelope without the flag remains climate-on', () {
      final card = _world(
        card: {
          'biome': {'id': 'desert'},
        },
      );

      expect(stoopWorldClimateEnabled(card.card), isTrue);
      expect(stoopCardClimateEnabled(card), isTrue);
    });

    test('an envelope flag remains authoritative over list metadata', () {
      expect(
        stoopCardClimateEnabled(
          _world(card: {'climate_enabled': true}, climateEnabled: false),
        ),
        isTrue,
      );
    });
  });

  testWidgets('a lore-only list row shows WORLD and LORE, not CLIMATE', (
    tester,
  ) async {
    await _pumpTile(tester, _world(climateEnabled: false));

    expect(find.text('WORLD'), findsOneWidget);
    expect(find.text('LORE'), findsOneWidget);
    expect(find.text('CLIMATE'), findsNothing);
  });

  test('both the tile and Mod Pick hero use the list-row resolver', () {
    for (final path in [
      'lib/ui/pages/repository/stoop_card_tile.dart',
      'lib/ui/pages/repository/stoop_browse_view.dart',
    ]) {
      final source = File(path).readAsStringSync();
      expect(
        source,
        contains('climateEnabled: stoopCardClimateEnabled(card)'),
        reason: path,
      );
    }
  });
}
