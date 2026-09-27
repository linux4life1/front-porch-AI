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

part of '../chat_service.dart';

/// Model-initiated `web_search` / `wiki_search` — builders. Web search on/off
/// is the Porch Life global, read live. Wiki search is this chat's URL.
extension ChatServiceWebSearch on ChatService {
  WebSearchService _buildWebSearchService() {
    return WebSearchService(
      getApiKey: () => _storageService.webSearchSettings.searchApiKey,
      getGlobalDefault: () =>
          _storageService.webSearchSettings.webSearchDefault,
    );
  }

  WikiSearchService _buildWikiSearchService() {
    return WikiSearchService(
      getBaseUrl: () =>
          _storageService.webSearchSettings.wikiUrlForChat(_currentSessionId),
    );
  }

  String get _wikiBaseUrlImpl =>
      _storageService.webSearchSettings.wikiUrlForChat(_currentSessionId);

  bool get webSearchEnabled =>
      _storageService.webSearchSettings.webSearchDefault;

  bool get wikiLookupAvailable => parseWikiBaseUrl(_wikiBaseUrlImpl) != null;

  void _armForcedLookup({String? webQuery, String? wikiQuery}) {
    final web = webQuery?.trim() ?? '';
    final wiki = wikiQuery?.trim() ?? '';
    _pendingForcedWebQuery = web.isEmpty ? null : web;
    _pendingForcedWikiQuery = wiki.isEmpty ? null : wiki;
  }

  void _clearForcedLookup() {
    _pendingForcedWebQuery = null;
    _pendingForcedWikiQuery = null;
  }

  /// Banner text when [raw] is a lookup command that must not send.
  /// Null when the line is ordinary chat or a lookup that can run.
  String? lookupCommandBlock(String raw) {
    final parsed = parseLookupForce(raw);
    if (!parsed.attempted) return null;
    if (parsed.error != null) return parsed.error;
    return lookupForceUnavailable(
      webQuery: parsed.webQuery,
      wikiQuery: parsed.wikiQuery,
      webEnabled: _storageService.webSearchSettings.webSearchDefault,
      hasWiki: parseWikiBaseUrl(_wikiBaseUrlImpl) != null,
    );
  }

  void announceLookupForce(String message) {
    _setGuestStatus(message, isError: true);
  }

  Future<void> _applyForcedLookup(_GenTurn t, List<String> scraps) async {
    final webQuery = t.forcedWebQuery;
    final wikiQuery = t.forcedWikiQuery;
    if ((webQuery == null || webQuery.isEmpty) &&
        (wikiQuery == null || wikiQuery.isEmpty)) {
      return;
    }
    _webSearchService.beginUserSend();
    _wikiSearchService.beginUserSend();
    final forced = await runForcedLookups(
      web: _webSearchService,
      wiki: _wikiSearchService,
      webQuery: webQuery,
      wikiQuery: wikiQuery,
    );
    final injection = forced.injection;
    if (injection != null && injection.isNotEmpty) scraps.add(injection);
    if (forced.searchReceipt != null) t.searchReceipt = forced.searchReceipt;
    if (forced.wikiReceipt != null) t.wikiReceipt = forced.wikiReceipt;
  }

  Future<void> _setWikiBaseUrlImpl(String url) async {
    await _storageService.webSearchSettings.applyWikiUrlForSession(
      _currentSessionId,
      url,
    );
    final canonical = url.trim().isEmpty
        ? ''
        : (parseWikiBaseUrl(url)?.origin ?? '');
    if (_activeGroup == null &&
        _activeCharacter != null &&
        canonical.isNotEmpty) {
      await _storageService.webSearchSettings.setWikiUrlForCharacter(
        _activeCharacter!.stableGroupId,
        canonical,
      );
    }
    notifyListeners();
  }

  /// New 1:1 session: seed this chat from the character's last picked wiki.
  /// Groups stay session-only — do not guess a host character.
  Future<void> _seedWikiForNewSession() async {
    final sid = _currentSessionId;
    if (sid == null || sid.isEmpty) return;
    final url = _storageService.webSearchSettings.wikiUrlToSeedForNewChat(
      isGroup: _activeGroup != null,
      characterId: _activeCharacter?.stableGroupId,
    );
    if (url == null) return;
    await _storageService.webSearchSettings.setChatWikiUrl(sid, url);
  }

  /// Forks keep the parent's per-chat wiki (including explicit off).
  Future<void> _copyWikiForForkedSession(String oldSessionId) async {
    final sid = _currentSessionId;
    if (sid == null || sid.isEmpty) return;
    if (!_storageService.webSearchSettings.hasSessionWikiOverride(
      oldSessionId,
    )) {
      return;
    }
    await _storageService.webSearchSettings.setChatWikiUrl(
      sid,
      _storageService.webSearchSettings.wikiUrlForChat(oldSessionId),
    );
  }
}
