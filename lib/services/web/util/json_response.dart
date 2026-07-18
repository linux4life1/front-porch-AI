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

import 'package:shelf/shelf.dart' as shelf;

/// Small JSON response helpers shared by every route group in the rewritten
/// web server. Replaces the ad-hoc `shelf.Response(...jsonEncode...)` and the
/// old `_errorResponse` scattered through the legacy god file.
class JsonResponse {
  const JsonResponse._();

  static const Map<String, String> _jsonHeaders = {
    'Content-Type': 'application/json; charset=utf-8',
  };

  /// 200 OK with a JSON body. [extraHeaders] are merged in (e.g. Set-Cookie).
  static shelf.Response ok(
    Object? data, {
    Map<String, String>? extraHeaders,
  }) {
    return shelf.Response.ok(
      jsonEncode(data),
      headers: _merge(extraHeaders),
    );
  }

  /// Arbitrary status code with `{ "error": message }` plus optional fields.
  static shelf.Response error(
    int status,
    String message, {
    Map<String, Object?> extra = const {},
    Map<String, String>? extraHeaders,
  }) {
    return shelf.Response(
      status,
      body: jsonEncode({'error': message, ...extra}),
      headers: _merge(extraHeaders),
    );
  }

  static shelf.Response unauthorized(String message) => error(401, message);
  static shelf.Response forbidden(String message) => error(403, message);
  static shelf.Response badRequest(String message) => error(400, message);
  static shelf.Response tooManyRequests(
    String message, {
    int? retryAfterSeconds,
  }) {
    return error(
      429,
      message,
      extra: retryAfterSeconds != null
          ? {'retryAfter': retryAfterSeconds}
          : const {},
      extraHeaders: retryAfterSeconds != null
          ? {'Retry-After': '$retryAfterSeconds'}
          : null,
    );
  }

  static Map<String, String> _merge(Map<String, String>? extra) {
    if (extra == null || extra.isEmpty) return _jsonHeaders;
    return {..._jsonHeaders, ...extra};
  }
}
