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
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/backporch/backporch_api.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/services/group_card_importer.dart';
import 'package:front_porch_ai/services/web/facade/stoop_import_kind.dart';

/// A raw upstream response, passed through to the web client verbatim so the
/// browser sees exactly the status codes and machine-readable `error` fields
/// the desktop client sees (`invalid_credentials`, `two_factor_required`, …).
class StoopProxyResult {
  const StoopProxyResult(this.status, this.body);
  final int status;
  final String body;
}

/// Web adapter for The Stoop (the community character hub).
///
/// The browser cannot talk to the Stoop backend directly (its assets and API
/// are Bearer-token authed with no browser CORS surface), so the web client
/// sends its own Stoop session token per-request in an `X-Stoop-Token` header
/// and this facade relays the call. The token pair itself lives in the
/// *browser* (localStorage) — the desktop app's own Stoop session in
/// [BackporchAuthStore] is never shared with, or touched by, web clients.
///
/// Most endpoints are verbatim JSON passthroughs ([forward]); the typed
/// desktop client isn't reused for those because its models parse one way
/// only, and the passthrough must preserve upstream status + error codes
/// byte-for-byte. Downloads are the exception: the card lands in the *local*
/// library, so [downloadAndImport] replicates the desktop import chain
/// (V2CardService PNG re-encode + CharacterRepository, or GroupCardImporter).
class StoopFacade {
  StoopFacade(
    this._storage,
    this._db, {
    CharacterRepository? characters,
    GroupChatRepository? groups,
    WorldRepository? worlds,
    BackporchApi? api,
  }) : _characters = characters,
       _groups = groups,
       _worlds = worlds,
       _api = api ?? BackporchApi();

  final StorageService _storage;
  final AppDatabase _db;
  final CharacterRepository? _characters;
  final GroupChatRepository? _groups;
  final WorldRepository? _worlds;
  final BackporchApi _api;

  /// Upstream REST base, e.g. `https://api.frontporchai.app`.
  String get baseUrl => _api.baseUrl;

  /// Upstream live-messaging WebSocket URL (token appended by the relay).
  /// `replaceFirst` maps http→ws and https→wss.
  String get messageSocketUrl => '${baseUrl.replaceFirst('http', 'ws')}/ws';

  // <img> tags can't attach X-Stoop-Token, so GET /api/stoop/assets/<id>
  // falls back to the Stoop token last seen on an authenticated call for
  // THIS web session (fpa_session cookie). In-memory only — never
  // persisted — and never process-wide: two browsers on the same host
  // must not share a token, and logout must forget it.
  final Map<String, String> _assetTokensByWebSession = {};

  /// Remember [token] for [webSession] so cookie-authenticated <img> fetches
  /// can load avatars. No-op when either is blank — never a process-wide slot.
  void rememberAssetToken({String? webSession, String? token}) {
    final sid = webSession?.trim() ?? '';
    final tok = token?.trim() ?? '';
    if (sid.isEmpty || tok.isEmpty) return;
    _assetTokensByWebSession[sid] = tok;
  }

  /// Drop the remembered token for [webSession] (Stoop logout or web logout).
  void clearAssetToken(String? webSession) {
    final sid = webSession?.trim() ?? '';
    if (sid.isEmpty) return;
    _assetTokensByWebSession.remove(sid);
  }

  String? _tokenForAsset({String? headerToken, String? webSession}) {
    if (headerToken != null && headerToken.isNotEmpty) return headerToken;
    final sid = webSession?.trim() ?? '';
    if (sid.isEmpty) return null;
    return _assetTokensByWebSession[sid];
  }

  /// Relay a JSON call to the Stoop backend and hand back the raw upstream
  /// status + body. [query] is the already-encoded query string to append.
  Future<StoopProxyResult> forward({
    required String method,
    required String upstreamPath,
    String? query,
    String? token,
    String? webSession,
    Map<String, dynamic>? jsonBody,
  }) async {
    rememberAssetToken(webSession: webSession, token: token);
    var uri = Uri.parse('$baseUrl$upstreamPath');
    if (query != null && query.isNotEmpty) uri = uri.replace(query: query);
    final client = http.Client();
    try {
      final req = http.Request(method, uri);
      if (token != null && token.isNotEmpty) {
        req.headers['Authorization'] = 'Bearer $token';
      }
      if (jsonBody != null) {
        req.headers['Content-Type'] = 'application/json';
        req.body = jsonEncode(jsonBody);
      }
      final res = await http.Response.fromStream(
        await client.send(req).timeout(const Duration(seconds: 30)),
      );
      return StoopProxyResult(res.statusCode, res.body);
    } finally {
      client.close();
    }
  }

  /// Re-wrap browser-supplied image bytes as the backend's multipart avatar
  /// upload (`POST /me/avatar`), passing the upstream status + body through
  /// verbatim like [forward].
  Future<StoopProxyResult> forwardAvatarUpload({
    required String token,
    required Uint8List bytes,
    required String contentType,
    String? webSession,
  }) async {
    rememberAssetToken(webSession: webSession, token: token);
    // Default to jpg, not png: the web client's canvas crop always emits
    // JPEG, so a stripped/unknown Content-Type is still almost surely jpeg.
    final ext = contentType.contains('png')
        ? 'png'
        : contentType.contains('webp')
        ? 'webp'
        : 'jpg';
    final req = http.MultipartRequest('POST', Uri.parse('$baseUrl/me/avatar'))
      ..headers['Authorization'] = 'Bearer $token'
      ..files.add(
        http.MultipartFile.fromBytes('avatar', bytes, filename: 'avatar.$ext'),
      );
    final res = await http.Response.fromStream(
      await req.send().timeout(const Duration(seconds: 60)),
    );
    return StoopProxyResult(res.statusCode, res.body);
  }

  /// Fetch a card asset (avatar) for serving to the browser. [token] comes
  /// from the request header when the client fetches via JS; `<img>` tags
  /// fall back to the token remembered for [webSession]. Returns null when
  /// no token is known yet (the route answers 401 and the image simply hides).
  Future<(int status, Uint8List bytes, String contentType)?> assetBytes(
    String assetId, {
    String? token,
    String? webSession,
  }) async {
    final t = _tokenForAsset(headerToken: token, webSession: webSession);
    if (t == null || t.isEmpty) return null;
    final client = http.Client();
    try {
      final res = await client
          .get(
            Uri.parse('$baseUrl/assets/$assetId/raw'),
            headers: {'Authorization': 'Bearer $t'},
          )
          .timeout(const Duration(seconds: 30));
      return (
        res.statusCode,
        res.bodyBytes,
        res.headers['content-type'] ?? 'image/png',
      );
    } finally {
      client.close();
    }
  }

  /// Whether the local library services needed by [downloadAndImport] were
  /// injected. When false the download route answers 503 instead of failing
  /// halfway through an import.
  bool get canImport => _characters != null && _groups != null;

  /// Download a card from The Stoop and import it into the local library —
  /// the same chain the desktop detail page runs: group cards through
  /// [GroupCardImporter]; solo cards re-encoded to a V2 PNG (card JSON +
  /// fetched avatar) and imported via [CharacterRepository.importCharacter].
  ///
  /// Returns `{ok, name, type}` on success or `{ok: false, error}` on a
  /// payload/import failure. Upstream HTTP errors propagate as
  /// [BackporchApiException] so the route can pass the status through.
  Future<Map<String, dynamic>> downloadAndImport(
    String token,
    String cardId, {
    String? clientType,
    String? webSession,
  }) async {
    rememberAssetToken(webSession: webSession, token: token);
    final characters = _characters;
    final groups = _groups;
    if (characters == null || groups == null) {
      return {'ok': false, 'error': 'library_unavailable'};
    }

    final payload = await _api.download(token, cardId);
    final cardJson = payload['card'] as Map<String, dynamic>?;
    if (cardJson == null) return {'ok': false, 'error': 'no_card_data'};

    final kind = stoopImportKind(
      clientType: clientType,
      payloadType: payload['type'] as String?,
      card: cardJson,
    );

    // World cards carry the .fpworld envelope — import as a new place (lore +
    // climate + traits + cover), same as the desktop detail page.
    if (kind == 'WORLD') {
      final worlds = _worlds;
      if (worlds == null) return {'ok': false, 'error': 'library_unavailable'};
      final imported = await worlds.importWorldJson(cardJson);
      return {'ok': true, 'name': imported.name, 'type': 'WORLD'};
    }

    // Group cards carry a members list; solo cards are V2 character JSON.
    final isGroup = kind == 'GROUP';
    if (isGroup) {
      final importer = GroupCardImporter(groups, _storage, _db);
      final result = await importer.importCard(GroupCard.fromJson(cardJson));
      if (!result.created) return {'ok': false, 'error': 'no_usable_members'};
      return {'ok': true, 'name': result.groupName, 'type': 'GROUP'};
    }

    Directory? tmp;
    try {
      tmp = await Directory.systemTemp.createTemp('stoop_web_dl');
      final jsonPath = p.join(tmp.path, 'card.json');
      await File(jsonPath).writeAsString(jsonEncode(cardJson));
      final v2 = V2CardService();
      final card = await v2.readCardFromJsonFile(jsonPath);
      if (card == null) return {'ok': false, 'error': 'parse_failed'};
      String? avatarPath;
      final assetId = payload['primaryAssetId'] as String?;
      if (assetId != null) {
        final bytes = await _api.assetBytes(token, assetId);
        avatarPath = p.join(tmp.path, 'avatar.png');
        await File(avatarPath).writeAsBytes(bytes);
      }
      final pngPath = p.join(tmp.path, 'card.png');
      await v2.saveCardAsPng(card, pngPath, avatarPath);
      final imported = await characters.importCharacter(File(pngPath));
      if (imported == null) return {'ok': false, 'error': 'import_failed'};
      return {'ok': true, 'name': imported.name, 'type': 'SOLO'};
    } finally {
      await tmp?.delete(recursive: true).catchError((_) => tmp!);
    }
  }
}
