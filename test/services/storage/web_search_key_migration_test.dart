// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Tavily lives in SharedPreferences (same durable store as MCP tokens and
// OpenRouter keys). The previous contract deleted the prefs copy after a
// keychain write; that is why a macOS relaunch with an empty keychain
// dropped the key. These tests now pin prefs as source of truth.

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_porch_ai/app_version.dart';
import 'package:front_porch_ai/services/storage/storage.dart';

String get _key => isPreRelease ? 'beta_search_api_key' : 'search_api_key';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'a prefs value is the durable copy and is not deleted on load',
    () async {
      SharedPreferences.setMockInitialValues({_key: '  tavily-legacy  '});
      FlutterSecureStorage.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final settings = WebSearchSettings()..initializeBase(prefs, () {});

      await settings.load();

      expect(settings.searchApiKey, 'tavily-legacy');
      expect(settings.hasApiKey, isTrue);
      expect(prefs.getString(_key), 'tavily-legacy');
    },
  );

  test('prefs wins when both stores have a value', () async {
    SharedPreferences.setMockInitialValues({_key: 'from-prefs'});
    FlutterSecureStorage.setMockInitialValues({_key: 'from-keychain'});
    final prefs = await SharedPreferences.getInstance();
    final settings = WebSearchSettings()..initializeBase(prefs, () {});

    await settings.load();

    expect(settings.searchApiKey, 'from-prefs');
  });

  test('saving writes prefs; clearing removes prefs and keychain', () async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final settings = WebSearchSettings()..initializeBase(prefs, () {});
    await settings.load();

    await settings.setSearchApiKey('tavily-new');
    expect(settings.hasApiKey, isTrue);
    expect(prefs.getString(_key), 'tavily-new');
    expect(await const FlutterSecureStorage().read(key: _key), 'tavily-new');

    await settings.setSearchApiKey('');
    expect(settings.hasApiKey, isFalse);
    expect(prefs.containsKey(_key), isFalse);
    expect(await const FlutterSecureStorage().read(key: _key), isNull);
  });
}
