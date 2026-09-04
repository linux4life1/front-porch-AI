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

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'settings_base.dart';

/// Global default + Tavily API key for model-initiated web search.
///
/// Default OFF. The global is read live at generation time, so flipping it
/// applies to already-open chats. There is no per-chat or sidebar override.
/// The key lives in platform secure storage; no key → Wikipedia.
class WebSearchSettings with SettingsBase {
  WebSearchSettings({
    // Front Porch is a non-sandboxed, directly distributed macOS app. The
    // data-protection keychain needs a provisioned keychain access group,
    // which makes ad-hoc debug builds fail before Dart can start. The legacy
    // login keychain remains encrypted by macOS without that entitlement.
    FlutterSecureStorage secureStorage = const FlutterSecureStorage(
      mOptions: MacOsOptions(usesDataProtectionKeychain: false),
    ),
  }) : _secureStorage = secureStorage;

  static const _apiKeyName = 'search_api_key';

  final FlutterSecureStorage _secureStorage;
  bool _webSearchDefault = false;
  String _searchApiKey = '';

  bool get webSearchDefault => _webSearchDefault;
  String get searchApiKey => _searchApiKey;
  bool get hasApiKey => _searchApiKey.trim().isNotEmpty;

  Future<void> load() async {
    _webSearchDefault = prefs?.getBool(k('web_search_default')) ?? false;
    final key = k(_apiKeyName);
    final legacy = prefs?.getString(key);
    try {
      final secured = (await _secureStorage.read(key: key))?.trim() ?? '';
      if (secured.isNotEmpty) {
        _searchApiKey = secured;
      } else if (legacy != null && legacy.trim().isNotEmpty) {
        _searchApiKey = legacy.trim();
        await _secureStorage.write(key: key, value: _searchApiKey);
      } else {
        _searchApiKey = '';
      }
    } catch (e, st) {
      _searchApiKey = '';
      debugPrint(
        '[WebSearch] secure API-key load/migration failed; '
        'using keyless Wikipedia and retaining any legacy value for retry: '
        '$e\n$st',
      );
      return;
    }
    if (legacy != null) await _removePlaintext(key);
  }

  Future<void> setWebSearchDefault(bool value) async {
    _webSearchDefault = value;
    await prefs?.setBool(k('web_search_default'), value);
    notify();
  }

  Future<void> setSearchApiKey(String value) async {
    final key = k(_apiKeyName);
    final trimmed = value.trim();
    try {
      if (trimmed.isEmpty) {
        await _secureStorage.delete(key: key);
      } else {
        await _secureStorage.write(key: key, value: trimmed);
      }
    } catch (e, st) {
      debugPrint('[WebSearch] secure API-key write failed: $e\n$st');
      rethrow;
    }
    _searchApiKey = trimmed;
    await _removePlaintext(key);
    notify();
  }

  Future<void> _removePlaintext(String key) async {
    try {
      final removed = await prefs?.remove(key);
      if (removed == false) {
        debugPrint('[WebSearch] could not remove legacy plaintext key');
      }
    } catch (e, st) {
      debugPrint('[WebSearch] legacy plaintext-key cleanup failed: $e\n$st');
    }
  }
}
