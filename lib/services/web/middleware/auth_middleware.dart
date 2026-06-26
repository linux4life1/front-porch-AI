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

import 'dart:io' show HttpConnectionInfo;

import 'package:shelf/shelf.dart' as shelf;

import 'package:front_porch_ai/services/web/util/cookies.dart';
import 'package:front_porch_ai/services/web/util/json_response.dart';
import 'package:front_porch_ai/services/web/web_server_deps.dart';

/// Context key under which the authenticated account id is attached.
const String kAuthUserIdContextKey = 'fpa.auth.userId';

/// Cookie-session auth gate for the rewritten server.
///
/// Replaces the legacy Bearer-token + `?token=` query-string scheme: the browser
/// sends the HttpOnly session cookie automatically (including on the WS upgrade),
/// so no token ever appears in a URL or log. Static assets and the unauthenticated
/// auth/health endpoints pass through; everything else under `api/` requires a
/// valid session and gets the account id attached for handlers.
class WebAuthMiddleware {
  WebAuthMiddleware(this._deps);

  final WebServerDeps _deps;

  /// Paths reachable without a session (also covers first-run setup).
  static const Set<String> _publicApiPaths = {
    'api/health',
    'api/auth/state',
    'api/auth/login',
    'api/auth/setup',
  };

  shelf.Middleware get middleware => (shelf.Handler inner) {
        return (shelf.Request request) async {
          final path = request.url.path;

          // Static assets and the public auth/health endpoints: no session.
          if (!path.startsWith('api/') || _publicApiPaths.contains(path)) {
            return inner(request);
          }

          final token = Cookies.sessionToken(request);
          final userId =
              token == null ? null : await _deps.auth.sessions.validate(token);
          if (userId == null) {
            return JsonResponse.unauthorized('Authentication required');
          }

          // Report presence for the desktop lock/settings UI (host dedupes).
          final cb = _deps.onClientActive;
          if (cb != null) {
            final ip = _clientIp(request);
            cb(ip, _describeClient(request.headers['user-agent'], ip));
          }

          return inner(
            request.change(context: {kAuthUserIdContextKey: userId}),
          );
        };
      };

  String? _clientIp(shelf.Request request) {
    final fwd = request.headers['x-forwarded-for'];
    if (fwd != null && fwd.isNotEmpty) return fwd.split(',').first.trim();
    final conn = request.context['shelf.io.connection_info'];
    return conn is HttpConnectionInfo ? conn.remoteAddress.address : null;
  }

  /// Compact "Browser on OS" label from a User-Agent (with the IP appended).
  static String _describeClient(String? ua, String? ip) {
    final suffix = ip != null ? ' ($ip)' : '';
    if (ua == null || ua.isEmpty) return 'Unknown$suffix';
    String browser = 'Browser';
    for (final b in const ['Edg', 'OPR', 'Firefox', 'Chrome', 'Safari']) {
      if (ua.contains(b)) {
        browser = b == 'Edg' ? 'Edge' : (b == 'OPR' ? 'Opera' : b);
        break;
      }
    }
    String os = '';
    for (final o in const ['Android', 'iPhone', 'iPad', 'Windows', 'Mac', 'Linux']) {
      if (ua.contains(o)) {
        os = o == 'Mac' ? 'macOS' : (o == 'iPhone' || o == 'iPad' ? 'iOS' : o);
        break;
      }
    }
    return os.isEmpty ? '$browser$suffix' : '$browser on $os$suffix';
  }
}
