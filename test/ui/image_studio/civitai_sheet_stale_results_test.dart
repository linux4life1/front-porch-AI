// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Results belong to what was asked. Picking another base, changing the
// words, or unticking adult clears the list and Load more until Search is
// pressed again, so Load more can never carry on an old search (after
// unticking adult, it must not ask civitai.red with the key).

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_porch_ai/ui/image_studio/studio_civitai_get.dart';

String _page(String next) => jsonEncode({
  'items': [
    {
      'id': 1,
      'name': 'Model 1',
      'type': 'LORA',
      'nsfw': false,
      'modelVersions': [
        {
          'id': 10,
          'files': [
            {'name': 'm1.safetensors'},
          ],
          'images': <Object>[],
        },
      ],
    },
  ],
  'metadata': {'nextCursor': next},
});

void main() {
  late List<Uri> asked;

  Future<({int status, String body})> search(
    Uri uri,
    Map<String, String> headers,
  ) async {
    asked.add(uri);
    return (status: 200, body: _page('c${asked.length + 1}'));
  }

  setUp(() {
    asked = [];
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({
      'civitai_credential_local': 'saved-key',
    });
  });

  Future<void> flush(WidgetTester tester) async {
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }
  }

  Future<void> open(WidgetTester tester, {bool adult = false}) async {
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: StudioCivitaiGet(
          lora: true,
          adult: adult,
          adultAllowed: true,
          backend: 'comfyui',
          onInstalled: (_) {},
          searchCall: search,
        ),
      ),
    );
    await flush(tester);
  }

  final words = find.widgetWithText(TextField, 'Search LoRAs');

  Future<int> searched(WidgetTester tester) async {
    await tester.enterText(words, 'look');
    await tester.tap(find.text('Search'));
    await flush(tester);
    expect(find.text('Model 1'), findsOneWidget);
    expect(find.text('Load more'), findsOneWidget);
    return asked.length;
  }

  void cleared() {
    expect(find.text('Model 1'), findsNothing);
    expect(find.text('Load more'), findsNothing);
  }

  testWidgets('picking another base clears the results', (tester) async {
    await open(tester);
    final before = await searched(tester);
    final base = find.byKey(const Key('studio-civitai-base'));
    await tester.enterText(base, 'qwen');
    await tester.pump();
    await tester.tap(find.text('Qwen 2.1'));
    await flush(tester);
    cleared();
    expect(asked, hasLength(before));
  });

  testWidgets('changing the words clears the results', (tester) async {
    await open(tester);
    final before = await searched(tester);
    await tester.enterText(words, 'looks');
    await flush(tester);
    cleared();
    expect(asked, hasLength(before));
  });

  testWidgets('unticking adult clears the results, and nothing more is asked '
      'of civitai.red', (tester) async {
    await open(tester, adult: true);
    final before = await searched(tester);
    expect(asked.every((uri) => uri.host == 'civitai.red'), isTrue);

    await tester.tap(find.text('Include adult models from civitai.red'));
    await flush(tester);
    cleared();
    expect(asked, hasLength(before));

    await tester.tap(find.text('Search'));
    await flush(tester);
    expect(asked.length, greaterThan(before));
    expect(asked[before].host, 'civitai.com');
    for (final uri in asked.skip(before)) {
      expect(uri.host, 'civitai.com');
      expect(uri.queryParameters.containsKey('nsfw'), isFalse);
    }
    expect(asked[before].queryParameters.containsKey('cursor'), isFalse);
  });
}
