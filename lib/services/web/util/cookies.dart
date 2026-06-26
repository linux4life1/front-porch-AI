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

/// Cookie parsing/building for the web session cookie. Shared by the auth
/// middleware (read) and auth routes (set/clear).
class Cookies {
  const Cookies._();

  /// The session cookie name.
  static const String sessionCookie = 'fpa_session';

  /// Parse the request `Cookie` header into a name→value map.
  static Map<String, String> parse(shelf.Request request) {
    final header = request.headers['cookie'];
    if (header == null || header.isEmpty) return const {};
    final out = <String, String>{};
    for (final part in header.split(';')) {
      final i = part.indexOf('=');
      if (i <= 0) continue;
      final name = part.substring(0, i).trim();
      final value = part.substring(i + 1).trim();
      if (name.isNotEmpty) out[name] = value;
    }
    return out;
  }

  /// The raw session token from the request cookie, or null.
  static String? sessionToken(shelf.Request request) =>
      parse(request)[sessionCookie];

  /// Build a `Set-Cookie` value for the session.
  ///
  /// [secure] must reflect the actual response scheme — over plain http (e.g.
  /// localhost or bare-LAN) a Secure cookie would never be sent back, so the
  /// caller passes false there and true behind HTTPS/TLS-terminating tunnels.
  static String setSession(
    String token, {
    required bool secure,
    required int maxAgeSeconds,
  }) {
    final parts = [
      '$sessionCookie=$token',
      'Path=/',
      'HttpOnly',
      'SameSite=Lax',
      'Max-Age=$maxAgeSeconds',
    ];
    if (secure) parts.add('Secure');
    return parts.join('; ');
  }

  /// Build a `Set-Cookie` value that immediately clears the session.
  static String clearSession({required bool secure}) {
    final parts = [
      '$sessionCookie=',
      'Path=/',
      'HttpOnly',
      'SameSite=Lax',
      'Max-Age=0',
    ];
    if (secure) parts.add('Secure');
    return parts.join('; ');
  }
}
