// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:front_porch_ai/providers/auth_state.dart';
import 'package:front_porch_ai/services/backporch/backporch.dart';
import 'package:front_porch_ai/ui/pages/repository/stoop_card_sections.dart';
import 'package:front_porch_ai/ui/pages/repository/stoop_card_tile.dart';
import 'package:front_porch_ai/ui/pages/repository/stoop_detail_top.dart';

const _roxyBlurb =
    'My take on mountain-dwelling goat herders/herbalists race with a '
    'bit mystical touch. Not built to be lewded - but surely someone will '
    'try. Sorry, feet lovers - that was accidental.';

StoopCard _card({String summary = _roxyBlurb, String name = 'Roxy'}) =>
    StoopCard(
      id: 'c1',
      name: name,
      summary: summary,
      type: 'SOLO',
      nsfw: false,
      score: 0,
      downloadCount: 0,
      modPick: false,
      creator: const StoopCreatorRef(id: 'samf', displayName: 'SAMF'),
      primaryAssetId: null,
    );

StoopCardDetail _detail({String summary = _roxyBlurb}) => StoopCardDetail(
  id: 'c1',
  name: 'Roxy',
  summary: summary,
  type: 'SOLO',
  nsfw: false,
  score: 0,
  downloadCount: 0,
  version: 1,
  tokenCount: 5600,
  creator: const StoopCreatorRef(id: 'samf', displayName: 'SAMF'),
  card: const {
    'name': 'Roxy',
    'description': 'A goat herder on a ridge.',
    'personality': 'Dry, principled, not a tease.',
  },
  tags: const ['oc', 'gardener'],
  primaryAssetId: null,
  myVote: 0,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('grid tile keeps two summary lines and does not clip mid-word', (
    tester,
  ) async {
    await tester.pumpWidget(
      ChangeNotifierProvider<AuthState>(
        create: (_) => AuthState(),
        child: MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 220,
              height: 220 / kStoopCardTileAspectRatio,
              child: StoopCardTile(card: _card(), onTap: () {}),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.textContaining('mountain-dwelling'), findsOneWidget);
    final summary = tester.widget<Text>(
      find.textContaining('mountain-dwelling'),
    );
    expect(summary.maxLines, kStoopTileSummaryMaxLines);
    expect(summary.overflow, TextOverflow.ellipsis);
  });

  testWidgets('detail top shows the full listing summary beside the art', (
    tester,
  ) async {
    await tester.pumpWidget(
      ChangeNotifierProvider<AuthState>(
        create: (_) => AuthState(),
        child: MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: StoopDetailTop(
                detail: _detail(),
                downloadCount: 0,
                onClose: () {},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.byKey(const Key('stoop-detail-summary')), findsOneWidget);
    expect(find.text(_roxyBlurb), findsOneWidget);
    expect(find.textContaining('feet lovers'), findsOneWidget);
    expect(find.textContaining('by SAMF'), findsOneWidget);
  });

  testWidgets(
    'card drawers match hub: Description and Personality, not Persona',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: Builder(
                builder: (c) => Column(
                  children: stoopStandardSections(c, {
                    'name': 'Roxy',
                    'description': 'A goat herder on a ridge.',
                    'personality': 'Dry, principled, not a tease.',
                  }, 'Roxy'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Persona'), findsNothing);
      expect(find.text('Description'), findsOneWidget);
      expect(find.text('Personality'), findsOneWidget);
      // Description starts open, like the hub.
      expect(find.text('A goat herder on a ridge.'), findsOneWidget);
      expect(find.text('Dry, principled, not a tease.'), findsNothing);
    },
  );
}
