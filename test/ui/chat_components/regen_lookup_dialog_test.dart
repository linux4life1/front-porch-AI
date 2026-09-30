// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The regenerate lookup row is hidden when neither source is available,
// web is omitted when Web Search is off, and wiki stays disabled until
// this chat has a wiki. An empty box does not invent a query.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:front_porch_ai/ui/chat_components/widgets/regen_critique_field.dart';

void main() {
  Future<void> open(
    WidgetTester tester, {
    required bool web,
    required bool wiki,
    void Function(String critique, {String? webQuery, String? wikiQuery})?
    onLookup,
    void Function(String critique)? onRegen,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => promptRegenCritiqueThen(
                context,
                onRegen ?? (_) {},
                webEnabled: web,
                wikiEnabled: wiki,
                onLookup: onLookup,
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets('no sources means no lookup row', (tester) async {
    await open(tester, web: false, wiki: false);
    expect(find.byKey(const Key('regen-lookup-query')), findsNothing);
    expect(find.byKey(const Key('regen-lookup-web')), findsNothing);
  });

  testWidgets('web on and no wiki leaves her wiki disabled', (tester) async {
    String? gotWeb;
    String? gotWiki;
    await open(
      tester,
      web: true,
      wiki: false,
      onLookup: (c, {String? webQuery, String? wikiQuery}) {
        gotWeb = webQuery;
        gotWiki = wikiQuery;
      },
    );
    expect(find.byKey(const Key('regen-lookup-web')), findsOneWidget);
    final wikiChip = tester.widget<InkWell>(
      find.descendant(
        of: find.byKey(const Key('regen-lookup-wiki')),
        matching: find.byType(InkWell),
      ),
    );
    expect(wikiChip.onTap, isNull);
    await tester.enterText(
      find.byKey(const Key('regen-lookup-query')),
      'Wandenreich',
    );
    await tester.tap(find.byKey(const Key('regen-critique-confirm')));
    await tester.pumpAndSettle();
    expect(gotWeb, 'Wandenreich');
    expect(gotWiki, isNull);
  });

  testWidgets('web off shows only her wiki', (tester) async {
    String? gotWiki;
    await open(
      tester,
      web: false,
      wiki: true,
      onLookup: (c, {String? webQuery, String? wikiQuery}) =>
          gotWiki = wikiQuery,
    );
    expect(find.byKey(const Key('regen-lookup-web')), findsNothing);
    expect(find.byKey(const Key('regen-lookup-wiki')), findsOneWidget);
    await tester.enterText(
      find.byKey(const Key('regen-lookup-query')),
      'the harvest rite',
    );
    await tester.tap(find.byKey(const Key('regen-critique-confirm')));
    await tester.pumpAndSettle();
    expect(gotWiki, 'the harvest rite');
  });

  testWidgets('an empty lookup box is an ordinary regen', (tester) async {
    String? got;
    var lookupRan = false;
    await open(
      tester,
      web: true,
      wiki: true,
      onRegen: (c) => got = c,
      onLookup: (c, {webQuery, wikiQuery}) => lookupRan = true,
    );
    await tester.tap(find.byKey(const Key('regen-critique-confirm')));
    await tester.pumpAndSettle();
    expect(got, '');
    expect(lookupRan, isFalse);
  });
}
