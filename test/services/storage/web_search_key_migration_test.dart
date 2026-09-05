// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// One-way migration for the Tavily key: plaintext SharedPreferences must be
// copied into platform secure storage and then removed.
//
// Guard proven red before passing: skip the legacy remove after secure write
// → the plaintext-key assertion failed.

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_porch_ai/app_version.dart';
import 'package:front_porch_ai/services/storage/storage.dart';

String get _key => isPreRelease ? 'beta_search_api_key' : 'search_api_key';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('migrates the plaintext Tavily key and deletes the old copy', () async {
    SharedPreferences.setMockInitialValues({_key: '  tavily-legacy  '});
    FlutterSecureStorage.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final settings = WebSearchSettings()..initializeBase(prefs, () {});

    await settings.load();

    expect(settings.searchApiKey, 'tavily-legacy');
    expect(settings.hasApiKey, isTrue);
    expect(prefs.containsKey(_key), isFalse);
    expect(await const FlutterSecureStorage().read(key: _key), 'tavily-legacy');
  });

  test('an existing secure key wins and stale plaintext is removed', () async {
    SharedPreferences.setMockInitialValues({_key: 'stale-plaintext'});
    FlutterSecureStorage.setMockInitialValues({_key: 'secure-current'});
    final prefs = await SharedPreferences.getInstance();
    final settings = WebSearchSettings()..initializeBase(prefs, () {});

    await settings.load();

    expect(settings.searchApiKey, 'secure-current');
    expect(prefs.containsKey(_key), isFalse);
    expect(
      await const FlutterSecureStorage().read(key: _key),
      'secure-current',
    );
  });

  test(
    'saving and clearing never recreates the plaintext preference',
    () async {
      SharedPreferences.setMockInitialValues({});
      FlutterSecureStorage.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final settings = WebSearchSettings()..initializeBase(prefs, () {});
      await settings.load();

      await settings.setSearchApiKey('tavily-new');
      expect(settings.hasApiKey, isTrue);
      expect(prefs.containsKey(_key), isFalse);
      expect(await const FlutterSecureStorage().read(key: _key), 'tavily-new');

      await settings.setSearchApiKey('');
      expect(settings.hasApiKey, isFalse);
      expect(prefs.containsKey(_key), isFalse);
      expect(await const FlutterSecureStorage().read(key: _key), isNull);
    },
  );
}
