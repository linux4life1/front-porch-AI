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

/// Tightened, credential-aware CORS.
///
/// The production SPA is served same-origin, so no CORS is needed there. The
/// only legitimate cross-origin caller is the Vite dev server, so we reflect a
/// localhost dev `Origin` and allow credentials (cookies). We never emit
/// `Access-Control-Allow-Origin: *` — that is invalid with credentials and was a
/// security smell in the legacy server.
class CorsMiddleware {
  const CorsMiddleware();

  static final RegExp _devOrigin =
      RegExp(r'^https?://(localhost|127\.0\.0\.1)(:\d+)?$');

  shelf.Middleware get middleware => (shelf.Handler inner) {
        return (shelf.Request request) async {
          final origin = request.headers['origin'];
          final allow = origin != null && _devOrigin.hasMatch(origin);
          final headers = allow
              ? <String, String>{
                  'Access-Control-Allow-Origin': origin,
                  'Access-Control-Allow-Credentials': 'true',
                  'Access-Control-Allow-Methods':
                      'GET, POST, PUT, DELETE, OPTIONS',
                  'Access-Control-Allow-Headers': 'Content-Type',
                  'Vary': 'Origin',
                }
              : const <String, String>{};

          if (request.method == 'OPTIONS') {
            return shelf.Response.ok(null, headers: headers);
          }
          final response = await inner(request);
          return headers.isEmpty ? response : response.change(headers: headers);
        };
      };
}
