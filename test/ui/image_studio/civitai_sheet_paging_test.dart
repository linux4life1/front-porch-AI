// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The desktop CivitAI sheet: a word plus a base that CivitAI answers with an
// empty first page still shows what later pages hold, with Load more; and
// the one base picker, where typing only narrows the menu, the pick is what
// is shown and sent, and "Only installed models" hiding it drops it for good.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_porch_ai/services/image/studio_model_roots.dart';
import 'package:front_porch_ai/ui/image_studio/studio_civitai_get.dart';

Map<String, Object?> _model(int id) => {
  'id': id,
  'name': 'Model $id',
  'type': 'LORA',
  'nsfw': false,
  'modelVersions': [
    {
      'id': id * 10,
      'files': [
        {'name': 'm$id.safetensors'},
      ],
      'images': <Object>[],
    },
  ],
};

void main() {
  late List<Uri> asked;
  late Map<String?, String> pages;
  late Directory models;

  Future<({int status, String body})> search(
    Uri uri,
    Map<String, String> headers,
  ) async {
    asked.add(uri);
    final body = pages[uri.queryParameters['cursor']];
    if (body == null) return (status: 500, body: '');
    return (status: 200, body: body);
  }

  String page(List<int> ids, {String? next}) => jsonEncode({
    'items': [for (final id in ids) _model(id)],
    'metadata': {'nextCursor': ?next},
  });

  setUp(() {
    asked = [];
    pages = {};
    models = Directory.systemTemp.createTempSync('civitai-paging');
    addTearDown(() => models.deleteSync(recursive: true));
    final checkpoints = Directory(p.join(models.path, 'checkpoints'))
      ..createSync();
    File(
      p.join(checkpoints.path, 'flux1-dev.safetensors'),
    ).writeAsStringSync('x');
    SharedPreferences.setMockInitialValues({
      kStudioModelRootsKey: encodeModelRoots({'comfyui': models.path}),
    });
    FlutterSecureStorage.setMockInitialValues({});
  });

  /// Real file work (the models folder scan) finishes a little at a time.
  Future<void> settle(WidgetTester tester, [int rounds = 10]) async {
    for (var i = 0; i < rounds; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump(const Duration(milliseconds: 20));
    }
  }

  Future<void> open(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: StudioCivitaiGet(
          lora: true,
          adult: false,
          adultAllowed: false,
          backend: 'comfyui',
          onInstalled: (_) {},
          searchCall: search,
        ),
      ),
    );
    // The folder scan is real file work and takes what the machine takes.
    // Wait for it to end, up to 20 s: 100 rounds (about 2 s) ran out in
    // full-suite runs on a busy machine while the scan was still going.
    final scan = Stopwatch()..start();
    while (find
            .text('Looking through the models folder…')
            .evaluate()
            .isNotEmpty &&
        scan.elapsed < const Duration(seconds: 20)) {
      await settle(tester, 1);
    }
    expect(find.text('Looking through the models folder…'), findsNothing);
  }

  final baseField = find.byKey(const Key('studio-civitai-base'));
  String shown(WidgetTester tester) =>
      tester.widget<TextField>(baseField).controller!.text;

  Future<void> pick(WidgetTester tester, String typed, String label) async {
    await tester.enterText(baseField, typed);
    await tester.pump();
    await tester.tap(find.text(label));
    await tester.pump();
    await tester.pump();
  }

  Future<void> runSearch(WidgetTester tester, String words) async {
    await tester.enterText(
      find.widgetWithText(TextField, 'Search LoRAs'),
      words,
    );
    await tester.tap(find.text('Search'));
    await settle(tester, 5);
  }

  group('searching', () {
    testWidgets('an empty first page goes on to the rows after it, and Load '
        'more carries on', (tester) async {
      pages = {
        null: page(const [], next: 'c2'),
        'c2': page([1], next: 'c3'),
        'c3': page(const [], next: 'c4'),
        'c4': page(const [], next: 'c5'),
        'c5': page(const [], next: 'c6'),
        'c6': page([2]),
      };
      await open(tester);
      await runSearch(tester, 'look');

      expect(asked, hasLength(5));
      expect(find.text('Model 1'), findsOneWidget);
      expect(find.text('Load more'), findsOneWidget);

      await tester.tap(find.text('Load more'));
      await settle(tester, 5);
      expect(asked.last.queryParameters['cursor'], 'c6');
      expect(asked.last.queryParameters['query'], 'look');
      expect(find.text('Model 1'), findsOneWidget);
      expect(find.text('Model 2'), findsOneWidget);
      expect(find.text('Load more'), findsNothing);
    });

    testWidgets('nothing in 500 results with more to come says so, and '
        'Klein (all) sends all four Klein bases', (tester) async {
      pages = {
        null: page(const [], next: 'c1'),
        for (var i = 1; i < 9; i++) 'c$i': page(const [], next: 'c${i + 1}'),
      };
      await open(tester);
      await pick(tester, 'klein', 'Flux.2 Klein (all)');
      await runSearch(tester, 'look');

      expect(
        find.text(
          'No matches in the first 500 results. Try a different word, or '
          'Load more.',
        ),
        findsOneWidget,
      );
      expect(find.text('Load more'), findsOneWidget);
      expect(asked.first.queryParameters['limit'], '100');
      expect(asked.first.queryParametersAll['baseModels'], [
        'Flux.2 Klein 9B',
        'Flux.2 Klein 9B-base',
        'Flux.2 Klein 4B',
        'Flux.2 Klein 4B-base',
      ]);
    });
  });

  group('the base picker', () {
    testWidgets('clearing the typed words brings the whole list back', (
      tester,
    ) async {
      await open(tester);
      await tester.enterText(baseField, 'qwen');
      await tester.pump();
      expect(find.text('Qwen 2.1'), findsOneWidget);
      expect(find.text('Flux.1 Dev'), findsNothing);

      await tester.tap(find.byTooltip('Clear'));
      await tester.pump();
      expect(find.text('Flux.1 Dev'), findsOneWidget);
      expect(find.text('Qwen 2.1'), findsOneWidget);

      await tester.enterText(baseField, 'sdxl');
      await tester.pump();
      expect(find.text('Flux.1 Dev'), findsNothing);
      // Select all and delete.
      await tester.enterText(baseField, '');
      await tester.pump();
      expect(find.text('Flux.1 Dev'), findsOneWidget);
    });

    testWidgets('a picked base survives typing and clearing, is shown, and is '
        'what the search sends', (tester) async {
      pages = {
        null: page([1]),
      };
      await open(tester);
      await pick(tester, 'qwen', 'Qwen 2.1');
      expect(shown(tester), 'Qwen 2.1');

      await tester.enterText(baseField, 'flux');
      await tester.pump();
      await tester.tap(find.byTooltip('Clear'));
      await tester.pump();
      await runSearch(tester, 'look');

      expect(shown(tester), 'Qwen 2.1');
      expect(asked.single.queryParametersAll['baseModels'], ['Qwen 2.1']);
    });

    testWidgets('Only installed drops a hidden pick with a note, and turning '
        'it off does not bring it back', (tester) async {
      pages = {
        null: page([1]),
      };
      await open(tester);

      // An installed base stays picked.
      await pick(tester, 'flux.1', 'Flux.1 Dev');
      await tester.tap(find.text('Only installed models'));
      await tester.pump();
      expect(shown(tester), 'Flux.1 Dev');
      await tester.tap(find.text('Only installed models'));
      await tester.pump();

      await pick(tester, 'klein', 'Flux.2 Klein 9B');
      await tester.tap(find.text('Only installed models'));
      await tester.pump();
      expect(
        find.text("Flux.2 Klein 9B isn't installed — showing Any base."),
        findsOneWidget,
      );
      expect(shown(tester), 'Any base');

      await tester.tap(find.text('Only installed models'));
      await tester.pump();
      expect(shown(tester), 'Any base');
      await runSearch(tester, 'look');
      expect(
        asked.single.queryParametersAll.containsKey('baseModels'),
        isFalse,
      );
    });
  });

  testWidgets('Save key is hidden while a key is saved, and back on Replace', (
    tester,
  ) async {
    FlutterSecureStorage.setMockInitialValues({
      'civitai_credential_local': 'saved-key',
    });
    await open(tester);
    expect(find.text('API key saved'), findsOneWidget);
    expect(find.text('Save key'), findsNothing);

    await tester.tap(find.text('Replace'));
    await tester.pump();
    expect(find.text('Save key'), findsOneWidget);
  });
}
