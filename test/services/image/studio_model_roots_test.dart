// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_porch_ai/services/image/studio_model_roots.dart';

void main() {
  late Directory saved;
  late Directory found;

  Future<void> remember(Map<String, Object> extra, String backend) async {
    SharedPreferences.setMockInitialValues({
      kStudioModelRootsKey: encodeModelRoots({backend: saved.path}),
      ...extra,
    });
  }

  setUp(() {
    saved = Directory.systemTemp.createTempSync('fpai_saved_root');
    found = Directory.systemTemp.createTempSync('fpai_found_root');
    addTearDown(() {
      if (saved.existsSync()) saved.deleteSync(recursive: true);
      found.deleteSync(recursive: true);
    });
  });

  for (final backend in ['a1111', 'drawthings', 'comfyui']) {
    test(
      '$backend: the folder the user saved beats a discovered one',
      () async {
        await remember({}, backend);
        final root = await savedStudioModelRoot(
          backend,
          discover: (_) async => found.path,
        );
        expect(root, saved.path);
      },
    );

    test(
      '$backend: a saved folder that is gone is reported, not swapped for a discovered one',
      () async {
        await remember({}, backend);
        saved.deleteSync(recursive: true);
        var searched = false;
        final root = await savedStudioModelRoot(
          backend,
          discover: (_) async {
            searched = true;
            return found.path;
          },
        );
        expect(root, isNull);
        expect(searched, isFalse);
        expect(await studioSavedRootMissing(backend), isTrue);
      },
    );

    test('$backend: a saved folder that exists is not "missing"', () async {
      await remember({}, backend);
      expect(await studioSavedRootMissing(backend), isFalse);
    });

    test('$backend: nothing saved is not "missing"', () async {
      SharedPreferences.setMockInitialValues({});
      expect(await studioSavedRootMissing(backend), isFalse);
    });

    test('$backend: with nothing saved, discovery decides', () async {
      SharedPreferences.setMockInitialValues({});
      final root = await savedStudioModelRoot(
        backend,
        discover: (_) async => found.path,
      );
      expect(root, found.path);
    });
  }

  test('a ComfyUI on another computer never gets a local folder', () async {
    await remember({'comfy_ui_url': 'http://192.0.2.7:8188'}, 'comfyui');
    final root = await savedStudioModelRoot(
      'comfyui',
      discover: (_) async => found.path,
    );
    expect(root, isNull);
  });

  test('a backend with no models folder gets none', () async {
    await remember({}, 'a1111');
    expect(await savedStudioModelRoot('remote'), isNull);
  });

  test(
    'a ComfyUI on another computer is not "missing" a local folder',
    () async {
      await remember({'comfy_ui_url': 'http://192.0.2.7:8188'}, 'comfyui');
      saved.deleteSync(recursive: true);
      expect(await studioSavedRootMissing('comfyui'), isFalse);
    },
  );

  test('a backend with no models folder is never "missing" one', () async {
    await remember({}, 'a1111');
    expect(await studioSavedRootMissing('remote'), isFalse);
  });

  test('the blocked-download words tell a gone folder from an unset one', () {
    expect(
      civitaiBlockedDownload(
        backend: 'comfyui',
        savedRoot: null,
        savedGone: true,
      ),
      kStudioSavedFolderGone,
    );
    expect(kStudioSavedFolderGone, isNot(contains('/')));
    expect(
      civitaiBlockedDownload(backend: 'comfyui', savedRoot: null),
      'Pick your models folder on this computer first',
    );
    expect(
      civitaiBlockedDownload(
        backend: 'comfyui',
        savedRoot: '/models',
        savedGone: true,
      ),
      isNull,
    );
  });
}
