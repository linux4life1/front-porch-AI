// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The desktop CivitAI sheet: the key box, the adult switch, overlapping
// searches, closing mid-download. HTTP is a function the test hands in, so a
// test decides when an answer arrives; what the downloader does with bytes is
// covered against a real file host in the service tests.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_porch_ai/services/image/image.dart';
import 'package:front_porch_ai/services/image/studio_model_roots.dart';
import 'package:front_porch_ai/ui/image_studio/studio_civitai_get.dart';
import 'package:front_porch_ai/ui/image_studio/studio_civitai_install.dart';

typedef _Answer = ({int status, String body});

class _Call {
  _Call(this.uri, this.headers);

  final Uri uri;
  final Map<String, String> headers;
  final Completer<_Answer> done = Completer<_Answer>();
}

void main() {
  const keyName = 'civitai_credential_local';
  const secure = FlutterSecureStorage();

  late List<_Call> calls;
  late Directory models;

  Future<_Answer> search(Uri uri, Map<String, String> headers) {
    final call = _Call(uri, headers);
    calls.add(call);
    return call.done.future;
  }

  List<dynamic> fixtureFiles() {
    final raw =
        jsonDecode(
              File(
                'test/fixtures/civitai/version_133005.json',
              ).readAsStringSync(),
            )
            as Map<String, dynamic>;
    return raw['files'] as List<dynamic>;
  }

  _Answer results(String name) => (
    status: 200,
    body: jsonEncode({
      'items': [
        {
          'id': 102565,
          'name': name,
          'type': 'LORA',
          'nsfw': false,
          'modelVersions': [
            {'id': 133005, 'files': fixtureFiles(), 'images': <Object>[]},
          ],
        },
      ],
    }),
  );

  CivitaiVersionFetch fetchVersion() {
    return ({required versionId, required adult, authorization}) async {
      final raw =
          jsonDecode(
                File(
                  'test/fixtures/civitai/version_133005.json',
                ).readAsStringSync(),
              )
              as Map<String, dynamic>;
      return CivitaiVersionLookup(
        CivitaiLookupKind.ok,
        parseCivitaiVersion(jsonEncode(raw)),
      );
    };
  }

  Future<void> open(
    WidgetTester tester, {
    bool adult = false,
    bool adultAllowed = true,
    CivitaiSaveCall? saveCall,
    ValueChanged<String>? onInstalled,
  }) async {
    tester.view.physicalSize = const Size(1200, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.of(context).push<void>(
                MaterialPageRoute<void>(
                  builder: (_) => StudioCivitaiGet(
                    lora: true,
                    adult: adult,
                    adultAllowed: adultAllowed,
                    backend: 'comfyui',
                    onInstalled: onInstalled ?? (_) {},
                    searchCall: search,
                    versionFetch: fetchVersion(),
                    saveCall: saveCall ?? saveCivitaiToDisk,
                  ),
                ),
              ),
              child: const Text('open sheet'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open sheet'));
    await _flush(tester);
  }

  Future<void> typeQuery(WidgetTester tester, String text) async {
    await tester.enterText(
      find.widgetWithText(TextField, 'Search LoRAs'),
      text,
    );
  }

  setUp(() {
    calls = [];
    models = Directory.systemTemp.createTempSync('civitai-sheet');
    addTearDown(() => models.deleteSync(recursive: true));
    SharedPreferences.setMockInitialValues({
      kStudioModelRootsKey: encodeModelRoots({'comfyui': models.path}),
    });
    FlutterSecureStorage.setMockInitialValues({keyName: 'green-key'});
  });

  group('the key box', () {
    testWidgets('Replace then an empty Search does not delete the key', (
      tester,
    ) async {
      await open(tester);
      expect(find.text('API key saved'), findsOneWidget);
      await tester.tap(find.text('Replace'));
      await _flush(tester);
      expect(find.widgetWithText(TextField, 'API key'), findsOneWidget);
      await tester.tap(find.text('Search'));
      await _flush(tester);
      final stored = await tester.runAsync(() => secure.read(key: keyName));
      expect(stored, 'green-key');
    });

    testWidgets('Remove key asks first, and only removes when told to', (
      tester,
    ) async {
      await open(tester);
      await tester.tap(find.text('Remove key'));
      await _flush(tester);
      expect(find.text('Remove the CivitAI key?'), findsOneWidget);
      await tester.tap(find.text('Keep it'));
      await _flush(tester);
      expect(find.text('API key saved'), findsOneWidget);
      expect(
        await tester.runAsync(() => secure.read(key: keyName)),
        'green-key',
      );

      await tester.tap(find.text('Remove key'));
      await _flush(tester);
      await tester.tap(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text('Remove key'),
        ),
      );
      await _flush(tester);
      expect(find.text('API key saved'), findsNothing);
      expect(find.widgetWithText(TextField, 'API key'), findsOneWidget);
      expect(await tester.runAsync(() => secure.read(key: keyName)), isNull);
    });

    testWidgets('a typed key is saved by Save key, into the key store only', (
      tester,
    ) async {
      FlutterSecureStorage.setMockInitialValues({});
      await open(tester);
      await tester.enterText(
        find.widgetWithText(TextField, 'API key'),
        'typed-key',
      );
      await tester.tap(find.text('Save key'));
      await _flush(tester);
      expect(
        await tester.runAsync(() => secure.read(key: keyName)),
        'typed-key',
      );
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getKeys().where((k) => k.contains('civitai')), isEmpty);
      expect(find.text('API key saved'), findsOneWidget);
    });
  });

  group('the models folder', () {
    testWidgets(
      'a saved folder that is gone is said on opening, with a way to pick it again',
      (tester) async {
        SharedPreferences.setMockInitialValues({
          kStudioModelRootsKey: encodeModelRoots({
            'comfyui': '${models.path}/vanished',
          }),
        });
        await open(tester);
        for (
          var i = 0;
          i < 20 && find.text(kStudioSavedFolderGone).evaluate().isEmpty;
          i++
        ) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 50)),
          );
          await tester.pump(const Duration(milliseconds: 50));
        }
        expect(find.text(kStudioSavedFolderGone), findsOneWidget);
        expect(find.text('Pick the ComfyUI models folder'), findsOneWidget);
      },
    );
  });

  group('the adult box follows the app setting', () {
    testWidgets(
      'with adult themes off there is no box, and civitai.com is searched',
      (tester) async {
        await open(tester, adult: true, adultAllowed: false);
        expect(
          find.text('Include adult models from civitai.red'),
          findsNothing,
        );
        await typeQuery(tester, 'x');
        await tester.tap(find.text('Search'));
        await _flush(tester);
        expect(calls, hasLength(1));
        expect(calls.single.uri.host, 'civitai.com');
        expect(calls.single.uri.queryParameters.containsKey('nsfw'), isFalse);
        expect(calls.single.headers.containsKey('Authorization'), isFalse);
        calls.single.done.complete(results('Plain'));
        await _flush(tester);
      },
    );

    testWidgets(
      'with adult themes on the box shows and civitai.red is searched',
      (tester) async {
        await open(tester, adult: true, adultAllowed: true);
        expect(
          find.text('Include adult models from civitai.red'),
          findsOneWidget,
        );
        await typeQuery(tester, 'x');
        await tester.tap(find.text('Search'));
        await _flush(tester);
        expect(calls.single.uri.host, 'civitai.red');
        expect(calls.single.uri.queryParameters['nsfw'], 'true');
        expect(calls.single.headers['Authorization'], 'Bearer green-key');
        calls.single.done.complete(results('Adult'));
        await _flush(tester);
      },
    );
  });

  group('overlapping searches', () {
    testWidgets('a slow older answer never replaces a newer one', (
      tester,
    ) async {
      await open(tester);
      await typeQuery(tester, 'first');
      await tester.tap(find.text('Search'));
      await _flush(tester);
      await typeQuery(tester, 'second');
      await tester.tap(find.text('Search'));
      await _flush(tester);
      expect(calls, hasLength(2));

      calls[1].done.complete(results('Second model'));
      await _flush(tester);
      expect(find.text('Second model'), findsOneWidget);

      calls[0].done.complete(results('First model'));
      await _flush(tester);
      expect(find.text('First model'), findsNothing);
      expect(find.text('Second model'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Enter in the box searches again while one is running', (
      tester,
    ) async {
      await open(tester);
      await typeQuery(tester, 'first');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await _flush(tester);
      await typeQuery(tester, 'second');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await _flush(tester);
      expect(calls, hasLength(2));
      expect(calls.last.uri.queryParameters['query'], 'second');
      for (final call in calls) {
        call.done.complete(results('Row'));
      }
      await _flush(tester);
    });

    testWidgets('closing the sheet mid-search leaves nothing to throw', (
      tester,
    ) async {
      await open(tester);
      await typeQuery(tester, 'x');
      await tester.tap(find.text('Search'));
      await _flush(tester);
      expect(calls, hasLength(1));
      await tester.tap(find.byTooltip('Close'));
      await _flush(tester);
      expect(find.byType(StudioCivitaiGet), findsNothing);
      calls.single.done.complete(results('Late'));
      await _flush(tester);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
      'a search that fails after the sheet closed leaves nothing to throw',
      (tester) async {
        await open(tester);
        await typeQuery(tester, 'x');
        await tester.tap(find.text('Search'));
        await _flush(tester);
        await tester.tap(find.byTooltip('Close'));
        await _flush(tester);
        calls.single.done.completeError(const SocketException('gone'));
        await _flush(tester);
        expect(tester.takeException(), isNull);
      },
    );
  });

  group('a download in progress', () {
    late CivitaiCancel seen;
    late Completer<String> hold;
    late Completer<void> reached;

    Future<String> holdingSave(
      CivitaiDownloadPlan plan, {
      void Function(int received, int? total)? onProgress,
      CivitaiCancel? cancel,
    }) {
      seen = cancel!;
      reached.complete();
      onProgress?.call(10, 100);
      cancel.onCancel(() {
        if (!hold.isCompleted) {
          hold.completeError(
            const CivitaiDownloadException(CivitaiFailure.cancelled),
          );
        }
      });
      return hold.future;
    }

    Future<void> startDownload(
      WidgetTester tester, {
      ValueChanged<String>? onInstalled,
    }) async {
      hold = Completer<String>();
      reached = Completer<void>();
      await open(tester, saveCall: holdingSave, onInstalled: onInstalled);
      await typeQuery(tester, 'maou');
      await tester.tap(find.text('Search'));
      await _flush(tester);
      calls.single.done.complete(results('Maou (Both Forms)'));
      await _flush(tester);
      await tester.tap(find.text('Download'));
      // The folder check and the plan touch the disk for real.
      for (var i = 0; i < 40 && !reached.isCompleted; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)),
        );
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(reached.isCompleted, isTrue, reason: 'the download never started');
    }

    testWidgets('shows how far along it is, with a Cancel', (tester) async {
      await startDownload(tester);
      expect(find.textContaining('Downloading'), findsOneWidget);
      expect(find.text('Cancel download'), findsOneWidget);
      hold.completeError(
        const CivitaiDownloadException(CivitaiFailure.cancelled),
      );
      await _flush(tester);
    });

    testWidgets('Close stops the download', (tester) async {
      await startDownload(tester);
      expect(seen.isCancelled, isFalse);
      await tester.tap(find.byTooltip('Close'));
      await _flush(tester);
      expect(seen.isCancelled, isTrue);
      expect(find.byType(StudioCivitaiGet), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Cancel download stops it and stays on the sheet', (
      tester,
    ) async {
      await startDownload(tester);
      await tester.tap(find.text('Cancel download'));
      await _flush(tester);
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await _flush(tester);
      expect(seen.isCancelled, isTrue);
      expect(find.byType(StudioCivitaiGet), findsOneWidget);
      expect(find.text('Cancel download'), findsNothing);
      expect(find.text('Download'), findsOneWidget);
    });

    testWidgets('Search cannot start while it runs, and Enter does nothing', (
      tester,
    ) async {
      await startDownload(tester);
      final button = tester.widget<TextButton>(
        find.widgetWithText(TextButton, 'Search'),
      );
      expect(button.onPressed, isNull);
      await typeQuery(tester, 'other');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await _flush(tester);
      expect(calls, hasLength(1));
      hold.completeError(
        const CivitaiDownloadException(CivitaiFailure.cancelled),
      );
      await _flush(tester);
    });

    testWidgets('a finished download reports the file and closes', (
      tester,
    ) async {
      final installed = <String>[];
      await startDownload(tester, onInstalled: installed.add);
      hold.complete('${models.path}/loras/MaouBigV1.2.safetensors');
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await _flush(tester);
      expect(installed, ['MaouBigV1.2.safetensors']);
      expect(find.byType(StudioCivitaiGet), findsNothing);
    });

    testWidgets(
      'a config folder that is not a models folder offers Use this folder',
      (tester) async {
        final outside = Directory.systemTemp.createTempSync('civitai-outside');
        addTearDown(() => outside.deleteSync(recursive: true));
        final real = outside.resolveSymbolicLinksSync();
        await startDownload(tester);
        hold.completeError(
          CivitaiDownloadException(
            CivitaiFailure.unsafe,
            'Not in your models folder.',
            real,
          ),
        );
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)),
        );
        await _flush(tester);
        expect(
          find.textContaining('Not in your models folder'),
          findsOneWidget,
        );
        expect(find.text(real), findsOneWidget);
        expect(
          await tester.runAsync(studioSavedModelRoots),
          isNot(contains(real)),
        );

        await tester.tap(find.text('Use this folder'));
        // The check and the save touch the disk for real.
        for (var i = 0; i < 20 && find.text(real).evaluate().isNotEmpty; i++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 50)),
          );
          await tester.pump(const Duration(milliseconds: 50));
        }
        await _flush(tester);

        expect(await tester.runAsync(studioSavedModelRoots), contains(real));
        expect(find.text('Use this folder'), findsNothing);
        expect(find.textContaining('Press Download again'), findsOneWidget);
      },
    );

    testWidgets('a refusal that names no folder offers none', (tester) async {
      await startDownload(tester);
      hold.completeError(
        const CivitaiDownloadException(CivitaiFailure.unsafe, 'Not allowed.'),
      );
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await _flush(tester);
      expect(find.textContaining('Not allowed'), findsOneWidget);
      expect(find.text('Use this folder'), findsNothing);
    });

    testWidgets('a refusal shows its own words on the sheet', (tester) async {
      await startDownload(tester);
      hold.completeError(const CivitaiDownloadException(CivitaiFailure.locked));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await _flush(tester);
      expect(find.textContaining('will not send this file'), findsOneWidget);
      expect(find.byType(StudioCivitaiGet), findsOneWidget);
    });
  });
}

/// Lets the async work that needs no real I/O finish, and a route or dialog
/// transition (about 800 ms here) play out. Fixed frames, not pumpAndSettle: the
/// progress bar animates for as long as a search runs.
Future<void> _flush(WidgetTester tester) async {
  for (var i = 0; i < 60; i++) {
    await tester.pump(const Duration(milliseconds: 20));
  }
}
