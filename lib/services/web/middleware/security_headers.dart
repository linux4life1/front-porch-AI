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

import 'package:front_porch_ai/services/web/web_server_deps.dart';

/// Baseline security response headers. HSTS is only emitted over a secure
/// transport (it is meaningless and counter-productive over plain http).
///
/// CSP is header-only (no meta tag). Tight same-origin PWA policy:
/// - no `unsafe-eval` (the production Vite bundle does not need it)
/// - `style-src` allows `'unsafe-inline'` because the React tree uses
///   `style={{…}}` widely
/// - `blob:` on script/worker/media/img for the audio worklet, object URLs,
///   and generated images
/// - `connect-src 'self'` covers same-origin fetch + WebSocket (CSP3)
/// Vite's own dev server is a different origin and is unaffected.
class SecurityHeaders {
  SecurityHeaders(this._deps);

  final WebServerDeps _deps;

  /// Production PWA Content-Security-Policy. Kept as a single const so tests
  /// can assert the header without re-deriving the directive list.
  static const String contentSecurityPolicy =
      "default-src 'self'; "
      "script-src 'self' blob:; "
      "style-src 'self' 'unsafe-inline'; "
      "img-src 'self' data: blob:; "
      "font-src 'self'; "
      "connect-src 'self'; "
      "worker-src 'self' blob:; "
      "media-src 'self' blob:; "
      "object-src 'none'; "
      "base-uri 'self'; "
      "form-action 'self'; "
      "frame-ancestors 'none'";

  shelf.Middleware get middleware => (shelf.Handler inner) {
    return (shelf.Request request) async {
      final response = await inner(request);
      final headers = <String, String>{
        'X-Content-Type-Options': 'nosniff',
        'X-Frame-Options': 'DENY',
        'Referrer-Policy': 'no-referrer',
            'Content-Security-Policy': contentSecurityPolicy,
      };
      if (_deps.isSecure(request)) {
        headers['Strict-Transport-Security'] =
            'max-age=31536000; includeSubDomains';
      }
      return response.change(headers: headers);
    };
  };
}
