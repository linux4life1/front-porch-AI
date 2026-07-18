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

import 'dart:async';
import 'dart:convert';

import 'package:shelf/shelf.dart' as shelf;
import 'package:shelf_router/shelf_router.dart';
import 'package:shelf_web_socket/shelf_web_socket.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'package:front_porch_ai/services/backporch/backporch_api.dart';
import 'package:front_porch_ai/services/backporch/stoop_aup.dart';
import 'package:front_porch_ai/services/web/facade/stoop_facade.dart';
import 'package:front_porch_ai/services/web/util/json_response.dart';
import 'package:front_porch_ai/services/web/util/request_body.dart';
import 'package:front_porch_ai/services/web/util/ws_guard.dart';

/// The Stoop (community character hub) endpoints for the web UI.
///
/// Every route is a fixed, allowlisted relay to the Stoop backend — this is
/// NOT an open proxy. The web session cookie gates the whole group (auth
/// middleware), and each Stoop call additionally carries the browser's own
/// Stoop session token in `X-Stoop-Token`; the browser owns that token pair
/// (localStorage), fully independent of the desktop app's Stoop login.
///
/// Upstream status codes and `{error: code}` bodies pass through verbatim so
/// the web UI maps the same machine-readable codes the desktop does
/// (`invalid_credentials`, `two_factor_required`, `email_taken`, …).
class WebStoopRoutes {
  WebStoopRoutes(this._facade, Router router) {
    _wsHandler = webSocketHandler(_relayMessageSocket);

    // Bundled AUP text + auth calls (no Stoop token yet).
    router.get('/api/stoop/aup', _aup);
    router.post('/api/stoop/auth/signup', _authCall('/auth/signup'));
    router.post('/api/stoop/auth/login', _authCall('/auth/login'));
    router.post('/api/stoop/auth/refresh', _authCall('/auth/refresh'));
    router.post('/api/stoop/auth/logout', _authCall('/auth/logout'));

    // Account. Static '/me/…' suffixes are registered before the parameterized
    // card/creator captures elsewhere can never swallow them (different roots),
    // but keep messages/unread above the bare messages POST for clarity.
    router.get('/api/stoop/me', _tokenCall('GET', '/auth/me'));
    router.delete('/api/stoop/me', _tokenCall('DELETE', '/auth/me'));
    router.post(
      '/api/stoop/me/accept-policy',
      _tokenCall('POST', '/auth/accept-policy'),
    );
    router.post(
      '/api/stoop/me/display-name',
      _tokenCall('POST', '/auth/display-name'),
    );
    router.post('/api/stoop/me/nsfw', _tokenCall('POST', '/auth/nsfw'));
    router.post('/api/stoop/2fa/setup', _tokenCall('POST', '/2fa/setup'));
    router.post('/api/stoop/2fa/enable', _tokenCall('POST', '/2fa/enable'));
    router.post('/api/stoop/2fa/disable', _tokenCall('POST', '/2fa/disable'));

    // Browse / cards / creators.
    router.get('/api/stoop/browse', _browse);
    router.get('/api/stoop/cards/<id>', _cardCall('GET', ''));
    router.post('/api/stoop/cards/<id>/vote', _cardCall('POST', '/vote'));
    router.post('/api/stoop/cards/<id>/download', _download);
    router.post('/api/stoop/cards/<id>/report', _report);
    router.get('/api/stoop/creators/<id>', _creatorCall('GET', ''));
    router.post('/api/stoop/creators/<id>/follow', _follow);

    // Signed-in user's lists + messaging thread.
    router.get('/api/stoop/me/following', _tokenCall('GET', '/me/following'));
    router.get('/api/stoop/me/characters', _tokenCall('GET', '/me/characters'));
    router.get('/api/stoop/me/downloads', _tokenCall('GET', '/me/downloads'));
    router.get('/api/stoop/me/messages', _tokenCall('GET', '/me/messages'));
    router.get(
      '/api/stoop/me/messages/unread',
      _tokenCall('GET', '/me/messages/unread'),
    );
    router.post(
      '/api/stoop/me/messages/read',
      _tokenCall('POST', '/me/messages/read'),
    );
    router.post('/api/stoop/me/messages', _tokenCall('POST', '/me/messages'));

    // Avatars (<img> tags) + the live-messaging WebSocket relay.
    router.get('/api/stoop/assets/<id>', _asset);
    router.get('/api/stoop/ws', _ws);
  }

  final StoopFacade _facade;
  late final shelf.Handler _wsHandler;

  static String? _token(shelf.Request request) =>
      request.headers['x-stoop-token'];

  /// Read an optional JSON object body ({} when empty). Returns null on
  /// malformed JSON so callers can answer 400.
  static Future<Map<String, dynamic>?> _jsonBody(shelf.Request request) async {
    final raw = await RequestBody.readString(request);
    if (raw.trim().isEmpty) return <String, dynamic>{};
    try {
      final decoded = jsonDecode(raw);
      return decoded is Map<String, dynamic> ? decoded : null;
    } catch (_) {
      return null;
    }
  }

  /// Relay [method] [upstreamPath] and pass the upstream response through.
  /// [bodyOverride] replaces reading the request body (a shelf body can only
  /// be read once, so handlers that already parsed it must pass it along).
  Future<shelf.Response> _relay(
    shelf.Request request,
    String method,
    String upstreamPath, {
    bool tokenRequired = true,
    String? query,
    Map<String, dynamic>? bodyOverride,
  }) async {
    final token = _token(request);
    if (tokenRequired && (token == null || token.isEmpty)) {
      return JsonResponse.error(401, 'stoop_not_signed_in');
    }
    Map<String, dynamic>? body = bodyOverride;
    if (body == null && method != 'GET') {
      body = await _jsonBody(request);
      if (body == null) return JsonResponse.badRequest('Invalid JSON body');
    }
    try {
      final res = await _facade.forward(
        method: method,
        upstreamPath: upstreamPath,
        query: query,
        token: token,
        jsonBody: body,
      );
      return shelf.Response(
        res.status,
        body: res.body,
        headers: {'Content-Type': 'application/json; charset=utf-8'},
      );
    } catch (_) {
      return JsonResponse.error(502, 'stoop_unreachable');
    }
  }

  // Route-builder helpers so each registration stays a one-liner.
  shelf.Handler _authCall(String upstreamPath) => (shelf.Request request) =>
      _relay(request, 'POST', upstreamPath, tokenRequired: false);

  shelf.Handler _tokenCall(String method, String upstreamPath) =>
      (shelf.Request request) => _relay(request, method, upstreamPath);

  Future<shelf.Response> Function(shelf.Request, String) _cardCall(
    String method,
    String suffix,
  ) => (shelf.Request request, String id) =>
      _relay(request, method, '/characters/${Uri.encodeComponent(id)}$suffix');

  Future<shelf.Response> Function(shelf.Request, String) _creatorCall(
    String method,
    String suffix,
  ) => (shelf.Request request, String id) =>
      _relay(request, method, '/creators/${Uri.encodeComponent(id)}$suffix');

  /// The bundled AUP text (same source the desktop policy gate renders), so
  /// the web gate shows identical policy content with no duplicated copy.
  shelf.Response _aup(shelf.Request request) => JsonResponse.ok({
    'id': kStoopAupId,
    'intro': kStoopAupIntro,
    'sections': [
      for (final s in kStoopAupSections) {'title': s.title, 'body': s.body},
    ],
  });

  /// Browse passthrough — the query string (sort/type/q/pick/following/page/
  /// take) is forwarded verbatim to the fixed upstream path.
  Future<shelf.Response> _browse(shelf.Request request) =>
      _relay(request, 'GET', '/characters', query: request.url.query);

  /// Download + import into the local library, server-side (the browser has no
  /// filesystem or importer). Success answers `{ok, name, type}`.
  Future<shelf.Response> _download(shelf.Request request, String id) async {
    final token = _token(request);
    if (token == null || token.isEmpty) {
      return JsonResponse.error(401, 'stoop_not_signed_in');
    }
    if (!_facade.canImport) {
      return JsonResponse.error(503, 'library_unavailable');
    }
    try {
      final result = await _facade.downloadAndImport(token, id);
      final ok = result['ok'] == true;
      if (!ok) return JsonResponse.error(422, '${result['error']}');
      return JsonResponse.ok(result);
    } on BackporchApiException catch (e) {
      return JsonResponse.error(e.statusCode, e.code);
    } catch (_) {
      return JsonResponse.error(502, 'stoop_unreachable');
    }
  }

  /// Report a card. The upstream endpoint is `/reports` with the card id in
  /// the body, so inject it from the path (the client sends category/reason).
  Future<shelf.Response> _report(shelf.Request request, String id) async {
    final body = await _jsonBody(request);
    if (body == null) return JsonResponse.badRequest('Invalid JSON body');
    return _relay(
      request,
      'POST',
      '/reports',
      bodyOverride: {
        'characterId': id,
        'category': '${body['category'] ?? 'OTHER'}',
        'reason': '${body['reason'] ?? ''}',
      },
    );
  }

  /// Follow/unfollow — one web endpoint, `{follow: bool}` picks the upstream
  /// verb (POST to follow, DELETE to unfollow), mirroring the desktop client.
  Future<shelf.Response> _follow(shelf.Request request, String id) async {
    final body = await _jsonBody(request);
    if (body == null) return JsonResponse.badRequest('Invalid JSON body');
    final want = body['follow'] == true;
    return _relay(
      request,
      want ? 'POST' : 'DELETE',
      '/creators/${Uri.encodeComponent(id)}/follow',
      bodyOverride: const {},
    );
  }

  /// Card avatars. `<img>` tags can't send headers, so the facade falls back
  /// to the token remembered from the session's earlier authenticated calls.
  Future<shelf.Response> _asset(shelf.Request request, String id) async {
    try {
      final asset = await _facade.assetBytes(id, token: _token(request));
      if (asset == null) return JsonResponse.error(401, 'stoop_not_signed_in');
      final (status, bytes, contentType) = asset;
      if (status < 200 || status >= 300) {
        return JsonResponse.error(status, 'asset_$status');
      }
      return shelf.Response.ok(
        bytes,
        headers: {
          'Content-Type': contentType,
          // Immutable per asset id; lets grids re-render without re-fetching.
          'Cache-Control': 'private, max-age=3600',
        },
      );
    } catch (_) {
      return JsonResponse.error(502, 'stoop_unreachable');
    }
  }

  Future<shelf.Response> _ws(shelf.Request request) async {
    final origin = request.headers['origin'];
    if (origin != null && !wsOriginAllowed(request, origin)) {
      return JsonResponse.forbidden('Cross-origin WebSocket rejected');
    }
    return await _wsHandler(request);
  }

  /// Bidirectional relay between the browser and the Stoop messaging socket.
  ///
  /// The browser's first frame must be `{"token": "<stoop access token>"}` —
  /// sent as a frame rather than a query parameter so the token never appears
  /// in a request line. The upstream connection then carries it the way the
  /// desktop client does (`?token=`, a WebSocket-handshake limitation of the
  /// backend protocol). After auth, frames pass through untouched both ways:
  /// `message`/`typing` events down, `typing` signals up.
  void _relayMessageSocket(WebSocketChannel browser, _) {
    WebSocketChannel? upstream;
    var closed = false;
    Timer? authTimeout;

    void shutDown() {
      if (closed) return;
      closed = true;
      authTimeout?.cancel();
      upstream?.sink.close();
      browser.sink.close();
    }

    authTimeout = Timer(const Duration(seconds: 10), shutDown);

    browser.stream.listen(
      (frame) {
        if (upstream != null) {
          upstream!.sink.add(frame);
          return;
        }
        authTimeout?.cancel();
        String token = '';
        try {
          final decoded = jsonDecode(frame as String);
          if (decoded is Map) token = '${decoded['token'] ?? ''}';
        } catch (_) {}
        if (token.isEmpty) {
          shutDown();
          return;
        }
        final up = WebSocketChannel.connect(
          Uri.parse(
            '${_facade.messageSocketUrl}?token=${Uri.encodeQueryComponent(token)}',
          ),
        );
        upstream = up;
        up.ready.then(
          (_) {
            if (closed) return;
            up.stream.listen(
              browser.sink.add,
              onDone: shutDown,
              onError: (_) => shutDown(),
            );
          },
          onError: (_) => shutDown(),
        );
      },
      onDone: shutDown,
      onError: (_) => shutDown(),
    );
  }
}
