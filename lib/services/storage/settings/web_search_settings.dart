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

import 'settings_base.dart';

/// Global default + Tavily API key for model-initiated web search.
///
/// Default OFF. The live value is OR-ed with the per-chat sidebar flag
/// at check time (not seed time), so flipping this on activates already-
/// open chats. The sidebar is a convenience override, not a prerequisite.
/// No key → Wikipedia fallback (encyclopedia).
class WebSearchSettings with SettingsBase {
  bool _webSearchDefault = false;
  String _searchApiKey = '';

  bool get webSearchDefault => _webSearchDefault;
  String get searchApiKey => _searchApiKey;
  bool get hasApiKey => _searchApiKey.trim().isNotEmpty;

  void load() {
    _webSearchDefault = prefs?.getBool(k('web_search_default')) ?? false;
    _searchApiKey = prefs?.getString(k('search_api_key')) ?? '';
  }

  Future<void> setWebSearchDefault(bool value) async {
    _webSearchDefault = value;
    await prefs?.setBool(k('web_search_default'), value);
    notify();
  }

  Future<void> setSearchApiKey(String value) async {
    _searchApiKey = value;
    await prefs?.setString(k('search_api_key'), value);
    notify();
  }
}
