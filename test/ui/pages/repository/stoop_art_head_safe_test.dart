// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Stoop card art must crop the way the hub does (object-position: center
// top): portrait art in a square tile keeps the head, worlds get a 16:10
// landscape box centred, and the detail page shows the whole image at its
// own height instead of a square crop. A signed-in AuthState makes the
// widget build a real Image; the asset fetch fails in the test sandbox and
// that is fine — the pins are the box and the anchor, not the pixels.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:front_porch_ai/providers/auth_state.dart';
import 'package:front_porch_ai/services/backporch/backporch.dart';
import 'package:front_porch_ai/services/storage_service.dart';
import 'package:front_porch_ai/ui/pages/repository/stoop_avatar.dart';
import 'package:front_porch_ai/ui/pages/repository/stoop_card_tile.dart';
import 'package:front_porch_ai/ui/pages/repository/stoop_detail_top.dart';

class _SignedIn extends AuthState {
  @override
  String? get accessToken => 'test-token';
}

StoopCard _card(String type) => StoopCard(
  id: 'c1',
  name: 'Roxy',
  summary: 'A goat herder on a ridge.',
  type: type,
  nsfw: false,
  score: 0,
  downloadCount: 0,
  modPick: false,
  creator: const StoopCreatorRef(id: 'c', displayName: 'author'),
  primaryAssetId: 'asset-1',
  card: const {},
);

StoopCardDetail _detail() => StoopCardDetail(
  id: 'c1',
  name: 'Roxy',
  summary: 'A goat herder on a ridge.',
  type: 'SOLO',
  nsfw: false,
  score: 0,
  downloadCount: 0,
  version: 1,
  tokenCount: 100,
  creator: const StoopCreatorRef(id: 'c', displayName: 'author'),
  card: const {'name': 'Roxy'},
  tags: const [],
  primaryAssetId: 'asset-1',
  myVote: 0,
);

Future<void> _pump(WidgetTester tester, Widget child) async {
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<AuthState>(create: (_) => _SignedIn()),
        ChangeNotifierProvider<StorageService>(create: (_) => StorageService()),
      ],
      child: MaterialApp(
        home: Scaffold(body: SingleChildScrollView(child: child)),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(seconds: 1));
}

// The outermost Image: on the card page that is the original, whose
// stand-in (the thumb) only exists inside its builders.
Image _art(WidgetTester tester) =>
    tester.widget<Image>(find.byType(Image).first);

StoopAssetImage _source(WidgetTester tester) =>
    _art(tester).image as StoopAssetImage;

double _artBoxRatio(WidgetTester tester) => tester
    .widget<AspectRatio>(
      find.ancestor(
        of: find.byType(Image).first,
        matching: find.byType(AspectRatio),
      ),
    )
    .aspectRatio;

void main() {
  tearDown(() => imageCache.clear());

  testWidgets('character tile: square box, art anchored to the top', (
    tester,
  ) async {
    await _pump(
      tester,
      SizedBox(
        width: 220,
        height: 360,
        child: StoopCardTile(card: _card('SOLO'), onTap: () {}),
      ),
    );
    expect(_artBoxRatio(tester), 1);
    expect(_art(tester).alignment, Alignment.topCenter);
    expect(_art(tester).fit, BoxFit.cover);
    expect(_source(tester).thumb, isTrue, reason: 'tiles load the postcard');
  });

  testWidgets('world tile: 16:10 landscape box, art centred', (tester) async {
    await _pump(
      tester,
      SizedBox(
        width: 220,
        height: 360,
        child: StoopCardTile(card: _card('WORLD'), onTap: () {}),
      ),
    );
    expect(_artBoxRatio(tester), closeTo(1.6, 0.001));
    expect(_art(tester).alignment, Alignment.center);
  });

  testWidgets('detail art is width-fitted and never forced square', (
    tester,
  ) async {
    await _pump(
      tester,
      SizedBox(
        width: 900,
        child: StoopDetailTop(
          detail: _detail(),
          downloadCount: 0,
          onClose: () {},
        ),
      ),
    );
    expect(_art(tester).fit, BoxFit.fitWidth);
    expect(
      _source(tester).thumb,
      isFalse,
      reason: 'the card page shows the original',
    );
    expect(
      find.ancestor(
        of: find.byType(Image).first,
        matching: find.byType(AspectRatio),
      ),
      findsNothing,
      reason: 'the hub shows the whole card image at its own height',
    );
    // The fetch fails here, so the placeholder shows: it must hold a
    // portrait box (280 wide → taller than 280), not collapse or go square.
    final art = tester.getSize(find.byType(ClipRRect).first);
    expect(art.width, 280);
    expect(art.height, greaterThan(280));
  });
}
