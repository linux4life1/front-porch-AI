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
///
/// The key lives in SharedPreferences — the same durable store as OpenRouter
/// keys and MCP tokens. macOS keychain was the previous store; ad-hoc /
/// Rawhide launches often come back empty (the reason MCP left the
/// keychain). A leftover keychain value is copied into prefs on load.
/// No key → Wikipedia.
class WebSearchSettings with SettingsBase {
  WebSearchSettings({
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
    final fromPrefs = prefs?.getString(key)?.trim() ?? '';
    if (fromPrefs.isNotEmpty) {
      _searchApiKey = fromPrefs;
      if (prefs?.getString(key) != fromPrefs) {
        await prefs?.setString(key, fromPrefs);
      }
      return;
    }
    try {
      final secured = (await _secureStorage.read(key: key))?.trim() ?? '';
      if (secured.isEmpty) {
        _searchApiKey = '';
        return;
      }
      _searchApiKey = secured;
      await prefs?.setString(key, secured);
    } catch (e, st) {
      _searchApiKey = '';
      debugPrint('[WebSearch] keychain read failed (prefs empty): $e\n$st');
    }
  }

  Future<void> setWebSearchDefault(bool value) async {
    _webSearchDefault = value;
    await prefs?.setBool(k('web_search_default'), value);
    notify();
  }

  Future<void> setSearchApiKey(String value) async {
    final key = k(_apiKeyName);
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      await prefs?.remove(key);
    } else {
      await prefs?.setString(key, trimmed);
    }
    try {
      if (trimmed.isEmpty) {
        await _secureStorage.delete(key: key);
      } else {
        await _secureStorage.write(key: key, value: trimmed);
      }
    } catch (e, st) {
      debugPrint('[WebSearch] keychain write failed (prefs kept): $e\n$st');
    }
    _searchApiKey = trimmed;
    notify();
  }
}
