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

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'package:front_porch_ai/services/chat/chat.dart' show parseWikiBaseUrl;

import 'settings_base.dart';

/// Canonical wiki URL, or null if unsafe. MediaWiki hosts → origin.
/// Tiddly / other hosts keep the path (`…/NeokosmosWiki/`).
String? canonicalizeWikiUrl(String raw) {
  final u = parseWikiBaseUrl(raw);
  if (u == null) return null;
  if (u.path.isEmpty || u.path == '/') return u.origin;
  return '${u.origin}${u.path}';
}

/// Host label for a saved wiki row (`bleach.fandom.com`).
/// Path-hosted notebooks include the folder (`quietoak.github.io/NeokosmosWiki`).
String wikiHostLabel(String url) {
  final u = parseWikiBaseUrl(url);
  if (u == null) return url.trim();
  if (u.path.isEmpty || u.path == '/') return u.host;
  var path = u.path;
  if (path.endsWith('/')) path = path.substring(0, path.length - 1);
  return '${u.host}$path';
}

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
  String _wikiBaseUrl = '';
  final List<String> _savedWikiUrls = [];
  final Map<String, String> _wikiBySession = {};
  final Map<String, String> _wikiByCharacter = {};

  bool get webSearchDefault => _webSearchDefault;
  String get searchApiKey => _searchApiKey;
  bool get hasApiKey => _searchApiKey.trim().isNotEmpty;

  /// Porch Life default wiki URL. Empty = wiki_search off for chats that
  /// have not pasted their own.
  String get wikiBaseUrl => _wikiBaseUrl;

  /// Unlimited library of saved wiki origins. No cap.
  List<String> get savedWikiUrls => List.unmodifiable(_savedWikiUrls);

  /// This chat's wiki URL: session override if one was saved (including
  /// explicit empty = off), otherwise the Porch Life default.
  String wikiUrlForChat(String? sessionId) {
    if (sessionId != null && _wikiBySession.containsKey(sessionId)) {
      return _wikiBySession[sessionId]!;
    }
    return _wikiBaseUrl;
  }

  bool hasSessionWikiOverride(String sessionId) =>
      _wikiBySession.containsKey(sessionId);

  /// Character default for a **new** 1:1. Null = none stored.
  String? wikiUrlForCharacter(String characterId) {
    if (characterId.isEmpty) return null;
    return _wikiByCharacter[characterId];
  }

  /// Session seed for a brand-new 1:1. Groups return null (don't guess).
  String? wikiUrlToSeedForNewChat({
    required bool isGroup,
    String? characterId,
  }) {
    if (isGroup) return null;
    if (characterId == null || characterId.isEmpty) return null;
    final url = _wikiByCharacter[characterId];
    if (url == null || url.isEmpty) return null;
    return url;
  }

  /// Saved library plus [current] if this chat has a URL not in the list.
  List<String> pickerWikiUrls({String? current}) {
    final out = List<String>.from(_savedWikiUrls);
    final cur = canonicalizeWikiUrl(current ?? '') ?? current?.trim() ?? '';
    if (cur.isNotEmpty && !out.contains(cur)) {
      out.insert(0, cur);
    }
    return out;
  }

  Future<void> load() async {
    _webSearchDefault = prefs?.getBool(k('web_search_default')) ?? false;
    _wikiBaseUrl = prefs?.getString(k('wiki_base_url')) ?? '';
    _savedWikiUrls
      ..clear()
      ..addAll(_decodeUrlList(prefs?.getString(k('wiki_saved_urls'))));
    _wikiBySession
      ..clear()
      ..addAll(_decodeWikiMap(prefs?.getString(k('wiki_urls_by_session'))));
    _wikiByCharacter
      ..clear()
      ..addAll(_decodeWikiMap(prefs?.getString(k('wiki_url_by_character'))));
    await _migrateDefaultIntoSaved();
    final key = k(_apiKeyName);
    // Null prefs = in-memory sandbox. Never read the live macOS keychain.
    if (prefs == null) {
      _searchApiKey = '';
      return;
    }
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
    _searchApiKey = trimmed;
    if (prefs == null) {
      notify();
      return;
    }
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
    notify();
  }

  Future<void> setWikiBaseUrl(String value) async {
    final trimmed = value.trim();
    final key = k('wiki_base_url');
    if (trimmed.isEmpty) {
      _wikiBaseUrl = '';
      await prefs?.remove(key);
      notify();
      return;
    }
    final canonical = canonicalizeWikiUrl(trimmed);
    if (canonical == null) {
      notify();
      return;
    }
    _wikiBaseUrl = canonical;
    await prefs?.setString(key, canonical);
    notify();
  }

  /// Add one wiki to the unlimited library. Rejects unsafe URLs.
  Future<bool> addSavedWikiUrl(String raw) async {
    final canonical = canonicalizeWikiUrl(raw);
    if (canonical == null) return false;
    if (!_savedWikiUrls.contains(canonical)) {
      _savedWikiUrls.add(canonical);
      await _persistSaved();
    }
    if (_wikiBaseUrl.isEmpty) {
      await setWikiBaseUrl(canonical);
    } else {
      notify();
    }
    return true;
  }

  Future<void> removeSavedWikiUrl(String raw) async {
    final canonical = canonicalizeWikiUrl(raw) ?? raw.trim();
    if (canonical.isEmpty) return;
    _savedWikiUrls.removeWhere((u) => u == canonical);
    await _persistSaved();
    if (_wikiBaseUrl == canonical) {
      await setWikiBaseUrl(_savedWikiUrls.isEmpty ? '' : _savedWikiUrls.first);
    } else {
      notify();
    }
  }

  Future<void> setWikiUrlForCharacter(String characterId, String value) async {
    if (characterId.isEmpty) return;
    final canonical = value.trim().isEmpty
        ? ''
        : (canonicalizeWikiUrl(value) ?? '');
    if (canonical.isEmpty) {
      _wikiByCharacter.remove(characterId);
    } else {
      _wikiByCharacter[characterId] = canonical;
    }
    await _persistCharacterMap();
    notify();
  }

  Future<void> setChatWikiUrl(String sessionId, String value) async {
    if (sessionId.isEmpty) {
      await setWikiBaseUrl(value);
      return;
    }
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      _wikiBySession[sessionId] = '';
    } else {
      _wikiBySession[sessionId] = canonicalizeWikiUrl(trimmed) ?? trimmed;
    }
    await _persistWikiMap();
    notify();
  }

  Future<void> applyWikiUrlForSession(String? sessionId, String url) async {
    if (sessionId == null || sessionId.isEmpty) {
      await setWikiBaseUrl(url);
    } else {
      await setChatWikiUrl(sessionId, url);
    }
  }

  Future<void> _persistWikiMap() async {
    final key = k('wiki_urls_by_session');
    if (_wikiBySession.isEmpty) {
      await prefs?.remove(key);
      return;
    }
    await prefs?.setString(key, jsonEncode(_wikiBySession));
  }

  Future<void> _persistCharacterMap() async {
    final key = k('wiki_url_by_character');
    if (_wikiByCharacter.isEmpty) {
      await prefs?.remove(key);
      return;
    }
    await prefs?.setString(key, jsonEncode(_wikiByCharacter));
  }

  Future<void> _persistSaved() async {
    final key = k('wiki_saved_urls');
    if (_savedWikiUrls.isEmpty) {
      await prefs?.remove(key);
      return;
    }
    await prefs?.setString(key, jsonEncode(_savedWikiUrls));
  }

  Future<void> _migrateDefaultIntoSaved() async {
    if (_wikiBaseUrl.isEmpty) return;
    final canonical = canonicalizeWikiUrl(_wikiBaseUrl);
    if (canonical == null) return;
    if (canonical != _wikiBaseUrl) {
      _wikiBaseUrl = canonical;
      await prefs?.setString(k('wiki_base_url'), canonical);
    }
    if (!_savedWikiUrls.contains(canonical)) {
      _savedWikiUrls.add(canonical);
      await _persistSaved();
    }
  }

  static List<String> _decodeUrlList(String? raw) {
    if (raw == null || raw.isEmpty) return [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return [];
      return [
        for (final e in decoded)
          if (e is String && e.trim().isNotEmpty) e.trim(),
      ];
    } catch (_) {
      return [];
    }
  }

  static Map<String, String> _decodeWikiMap(String? raw) {
    if (raw == null || raw.isEmpty) return {};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return {};
      return {
        for (final e in decoded.entries)
          if (e.key is String) e.key as String: '${e.value ?? ''}',
      };
    } catch (_) {
      return {};
    }
  }
}
