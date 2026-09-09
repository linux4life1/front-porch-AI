// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// This file is part of Front Porch AI.
//
// Front Porch AI is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// Front Porch AI is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
// GNU Affero General Public License for more details.
//
// You should have received a copy of the GNU Affero General Public License
// along with Front Porch AI. If not, see <https://www.gnu.org/licenses/>.

// Tavily must survive a restart when the macOS keychain comes back empty.
// MCP tokens and OpenRouter keys already live in SharedPreferences for that
// reason. The old keychain-only save deleted the prefs copy, so a keychain
// miss on the next launch left Wikipedia as the only search backend.

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_porch_ai/app_version.dart';
import 'package:front_porch_ai/services/storage/storage.dart';

String get _key => isPreRelease ? 'beta_search_api_key' : 'search_api_key';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Tavily key survives a restart when the keychain is empty', () async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final first = WebSearchSettings()..initializeBase(prefs, () {});
    await first.load();
    await first.setSearchApiKey('tavily-keep-me');

    FlutterSecureStorage.setMockInitialValues({});
    final second = WebSearchSettings()..initializeBase(prefs, () {});
    await second.load();

    expect(
      second.searchApiKey,
      'tavily-keep-me',
      reason:
          'prefs must be the durable copy — the macOS keychain is the '
          'store that does not come back after an ad-hoc / Rawhide relaunch',
    );
    expect(prefs.getString(_key), 'tavily-keep-me');
  });

  test('a keychain-only leftover is copied into prefs on load', () async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({_key: 'from-keychain'});
    final prefs = await SharedPreferences.getInstance();
    final settings = WebSearchSettings()..initializeBase(prefs, () {});
    await settings.load();

    expect(settings.searchApiKey, 'from-keychain');
    expect(prefs.getString(_key), 'from-keychain');
  });
}
