// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// #346: the library's search scope is remembered like the sort mode. The
// top level and folders keep separate choices because they offer different
// ones: the top level defaults to Everywhere, a folder to This folder only.

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_porch_ai/services/storage_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'),
        (call) async => call.method == 'getApplicationDocumentsDirectory'
            ? Directory.systemTemp.createTempSync('fpai_test_').path
            : null,
      );

  test('both scopes survive a simulated restart', () async {
    SharedPreferences.setMockInitialValues({});
    final first = StorageService();
    await first.initialized;
    expect(first.uiSettings.topSearchScope, 'allCharacters');
    expect(first.uiSettings.folderSearchScope, 'currentFolder');

    await first.uiSettings.setTopSearchScope('currentFolder');
    await first.uiSettings.setFolderSearchScope('folderRecursive');

    final second = StorageService();
    await second.initialized;
    expect(second.uiSettings.topSearchScope, 'currentFolder');
    expect(second.uiSettings.folderSearchScope, 'folderRecursive');
  });

  test('an unknown stored scope falls back to the default', () async {
    SharedPreferences.setMockInitialValues({
      for (final prefix in ['', 'beta_']) ...{
        '${prefix}library_scope_top': 'everything-ever',
        '${prefix}library_scope_folder': '',
      },
    });
    final storage = StorageService();
    await storage.initialized;
    expect(storage.uiSettings.topSearchScope, 'allCharacters');
    expect(storage.uiSettings.folderSearchScope, 'currentFolder');
  });
}
