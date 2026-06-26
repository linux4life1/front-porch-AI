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

import 'package:shelf/shelf.dart' as shelf;
import 'package:shelf_router/shelf_router.dart';
import 'package:shelf_web_socket/shelf_web_socket.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'package:front_porch_ai/services/web/util/json_response.dart';
import 'package:front_porch_ai/services/web/web_server_deps.dart';

/// The single authenticated WebSocket endpoint (`/api/ws`).
///
/// The session cookie is already validated by the auth middleware (the path is
/// under `api/`). We additionally enforce an Origin allowlist on the upgrade:
/// because the cookie is sent automatically, a missing check would allow a
/// malicious page to open a cross-site socket (WS-CSRF/hijack).
class StreamRoutes {
  StreamRoutes(this._deps, Router router) {
    _wsHandler = webSocketHandler(
      (WebSocketChannel channel) => _deps.streamHub!.register(channel),
      pingInterval: const Duration(seconds: 30),
    );
    router.get('/api/ws', _handle);
  }

  final WebServerDeps _deps;
  late final shelf.Handler _wsHandler;

  Future<shelf.Response> _handle(shelf.Request request) async {
    final origin = request.headers['origin'];
    if (origin != null && !_originAllowed(request, origin)) {
      return JsonResponse.forbidden('Cross-origin WebSocket rejected');
    }
    return await _wsHandler(request);
  }

  /// Allow same-origin (origin host == request host) and the localhost dev
  /// origins used by the Vite dev server.
  bool _originAllowed(shelf.Request request, String origin) {
    final o = Uri.tryParse(origin);
    if (o == null) return false;
    if (o.host == 'localhost' || o.host == '127.0.0.1') return true;
    return o.host == request.requestedUri.host;
  }
}
