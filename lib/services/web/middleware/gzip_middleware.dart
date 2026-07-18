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

import 'dart:io';

import 'package:shelf/shelf.dart' as shelf;

/// Transparent gzip for buffered text responses (chiefly the JSON API).
///
/// dart:io's `autoCompress` only gzips *chunked* responses, but shelf gives
/// every String/byte body a `Content-Length`, so those responses shipped
/// uncompressed. That's a real cost over a slow uplink: the character-list JSON
/// (names, tags, folders, message counts…) can be tens to hundreds of KB and
/// gzips roughly 5–10×.
///
/// A response is compressed only when it is safe and worthwhile:
///   • the client advertised `Accept-Encoding: gzip`,
///   • the body is buffered (a known `Content-Length`) and ≥ [minBytes],
///   • the `Content-Type` is text-like (JSON, `text/*`, JS, SVG, manifest), and
///   • it isn't already content-encoded.
/// WebSocket upgrades and any streamed or binary response (no `Content-Length`,
/// or a non-text type such as an avatar PNG/JPEG) pass through untouched, so
/// live token streaming and the image thumbnails are unaffected.
class GzipMiddleware {
  const GzipMiddleware({this.minBytes = 1024});

  /// Responses smaller than this are left alone — gzip's framing overhead plus
  /// the CPU aren't worth it for tiny payloads.
  final int minBytes;

  shelf.Middleware get middleware => (shelf.Handler inner) {
    return (shelf.Request request) async {
      final response = await inner(request);

      // Never touch a WebSocket upgrade — its "response" hijacks the socket.
      if (request.headers[HttpHeaders.upgradeHeader] != null) return response;

      final accept = request.headers[HttpHeaders.acceptEncodingHeader] ?? '';
      if (!accept.contains('gzip')) return response;
      if (response.headers.containsKey(HttpHeaders.contentEncodingHeader)) {
        return response;
      }
      final length = response.contentLength;
      if (length == null || length < minBytes) return response;
      if (!_isCompressible(response.mimeType)) return response;

      final chunks = await response.read().toList();
      final raw = chunks.expand((c) => c).toList();
      final compressed = gzip.encode(raw);

      return response.change(
        headers: {
          HttpHeaders.contentEncodingHeader: 'gzip',
          HttpHeaders.contentLengthHeader: '${compressed.length}',
          'Vary': _vary(response.headers['vary']),
        },
        body: compressed,
      );
    };
  };

  static bool _isCompressible(String? mime) {
    if (mime == null) return false;
    return mime == 'application/json' ||
        mime.startsWith('text/') ||
        mime == 'application/javascript' ||
        mime == 'application/manifest+json' ||
        mime == 'image/svg+xml';
  }

  /// Merge `Accept-Encoding` into any existing `Vary` so a shared cache never
  /// hands a gzipped body to a client that didn't ask for one.
  static String _vary(String? existing) {
    if (existing == null || existing.isEmpty) return 'Accept-Encoding';
    if (existing.toLowerCase().contains('accept-encoding')) return existing;
    return '$existing, Accept-Encoding';
  }
}
