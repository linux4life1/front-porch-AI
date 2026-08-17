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

import 'dart:io' show HttpConnectionInfo, InternetAddress;

import 'package:shelf/shelf.dart' as shelf;

/// Whether the immediate TCP peer is loopback (127.0.0.1 / ::1).
///
/// Tailscale-serve and ngrok terminate TLS on the host and proxy to us on
/// loopback. A LAN/tailnet client is never loopback, even if it sends
/// `X-Forwarded-*` headers.
bool requestPeerIsLoopback(shelf.Request request) {
  final conn = request.context['shelf.io.connection_info'];
  return conn is HttpConnectionInfo && conn.remoteAddress.isLoopback;
}

/// Client IP for rate limits and presence.
///
/// `X-Forwarded-For` is honored only when the immediate peer is loopback —
/// the same trust rule as [WebServerDeps.isSecure]. A LAN client cannot
/// rotate that header to mint a fresh rate-limit key.
///
/// When the peer *is* a loopback proxy (ngrok / Tailscale-serve), the
/// proxy *appends* the real client. Only a parsed non-loopback hop counts;
/// empty / unparsed / loopback-only tokens are not a key (`null` → the
/// shared unknown bucket). `X-Real-IP` is ignored: a client can set it
/// and we cannot prove the proxy did.
String? requestClientIp(shelf.Request request) {
  if (requestPeerIsLoopback(request)) {
    final forwarded = request.headers['x-forwarded-for'];
    if (forwarded != null && forwarded.isNotEmpty) {
      return _rightmostParsedNonLoopbackHop(forwarded);
    }
  }
  final conn = request.context['shelf.io.connection_info'];
  if (conn is HttpConnectionInfo) return conn.remoteAddress.address;
  return null;
}

/// The hop the trusted proxy added: rightmost parsed non-loopback token.
/// Unparsed tokens are skipped — they are not a valid IP key.
String? _rightmostParsedNonLoopbackHop(String forwarded) {
  final hops = forwarded.split(',');
  for (var i = hops.length - 1; i >= 0; i--) {
    final hop = hops[i].trim();
    if (hop.isEmpty) continue;
    final parsed = InternetAddress.tryParse(hop);
    if (parsed == null || parsed.isLoopback) continue;
    return hop;
  }
  return null;
}
