// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// A key store that will not give the saved key back (a known problem with
// ad-hoc signed macOS builds) must say so, and must not stop a search that
// never needed the key.

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

CivitaiCredentialStore _unreadable() => CivitaiCredentialStore(
  readKey: (_) async => throw StateError('keychain locked'),
  writeKey: (_, _) async {},
  deleteKey: (_) async {},
);

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    CivitaiCredentialStore.debugStore = _unreadable();
    addTearDown(() => CivitaiCredentialStore.debugStore = null);
  });

  group('the relay', () {
    test(
      'an ordinary search does not need the key, so it does not read it',
      () async {
        final plan = await CivitaiRelay(_unreadable()).planSearch(
          accountId: 'local',
          query: 'clothes',
          adult: false,
          lora: true,
        );
        expect(plan.uri, isNotNull);
        expect(plan.uri!.host, 'civitai.com');
        expect(plan.authorization, isNull);
        expect(plan.needsCredential, isFalse);
      },
    );

    test(
      'an adult search needs it, and says the store is the problem',
      () async {
        await expectLater(
          CivitaiRelay(
            _unreadable(),
          ).planSearch(accountId: 'local', query: 'x', adult: true, lora: true),
          throwsA(
            isA<CivitaiKeyStoreException>().having(
              (e) => e.message,
              'message',
              contains("Couldn't read your saved CivitAI key"),
            ),
          ),
        );
      },
    );
  });

  test('a download says the saved key could not be read', () async {
    final models = Directory.systemTemp.createTempSync('civitai-unreadable');
    addTearDown(() => models.deleteSync(recursive: true));
    SharedPreferences.setMockInitialValues({
      kStudioModelRootsKey: encodeModelRoots({'comfyui': models.path}),
    });
    final result = await installCivitaiRow(
      row: CivitaiModelRow(
        id: 1,
        name: 'x',
        type: 'LORA',
        adult: false,
        versionId: 133005,
        filename: 'MaouBigV1.2.safetensors',
      ),
      backend: 'comfyui',
      lora: true,
      adult: false,
      adultAllowed: true,
      versionFetch:
          ({required versionId, required adult, authorization}) async {
            fail('CivitAI must not be asked without a key');
          },
      saveCall: saveCivitaiToDisk,
      cancel: CivitaiCancel(),
      onProgress: (_, _) {},
    );
    expect(result, isA<CivitaiInstallFailed>());
    expect(
      (result as CivitaiInstallFailed).message,
      contains("Couldn't read your saved CivitAI key"),
    );
  });

  testWidgets('the sheet shows the message, and search still works', (
    tester,
  ) async {
    final models = Directory.systemTemp.createTempSync('civitai-unreadable');
    addTearDown(() => models.deleteSync(recursive: true));
    SharedPreferences.setMockInitialValues({
      kStudioModelRootsKey: encodeModelRoots({'comfyui': models.path}),
    });
    tester.view.physicalSize = const Size(1200, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final asked = <Uri>[];
    await tester.pumpWidget(
      MaterialApp(
        home: StudioCivitaiGet(
          lora: true,
          adult: false,
          adultAllowed: true,
          backend: 'comfyui',
          onInstalled: (_) {},
          searchCall: (uri, headers) async {
            asked.add(uri);
            return (
              status: 200,
              body: jsonEncode({
                'items': [
                  {
                    'id': 1,
                    'name': 'Found anyway',
                    'type': 'LORA',
                    'nsfw': false,
                    'modelVersions': [
                      {'id': 2, 'files': <Object>[], 'images': <Object>[]},
                    ],
                  },
                ],
              }),
            );
          },
        ),
      ),
    );
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(
      find.textContaining("Couldn't read your saved CivitAI key"),
      findsOneWidget,
    );
    expect(find.widgetWithText(TextField, 'API key'), findsOneWidget);

    await tester.enterText(find.widgetWithText(TextField, 'Search LoRAs'), 'x');
    await tester.tap(find.text('Search'));
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(asked, hasLength(1));
    expect(find.text('Found anyway'), findsOneWidget);
    expect(
      find.textContaining("Couldn't read your saved CivitAI key"),
      findsOneWidget,
    );
  });
}
