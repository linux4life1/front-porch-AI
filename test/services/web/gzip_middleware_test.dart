// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Unit coverage for GzipMiddleware — the transparent gzip layer for buffered
// text/JSON responses. Verifies it compresses when (and only when) it should,
// round-trips losslessly, and never touches streams, binaries, or WebSocket
// upgrades.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shelf/shelf.dart' as shelf;

import 'package:front_porch_ai/services/web/middleware/gzip_middleware.dart';

void main() {
  final middleware = const GzipMiddleware().middleware;

  // A large JSON payload (well over the 1 KB floor) so size never gates the
  // compressible cases.
  final bigJson = jsonEncode({'blob': 'x' * 5000});

  shelf.Handler wrap(shelf.Response Function() build) =>
      middleware((_) async => build());

  shelf.Request get(Map<String, String> headers) =>
      shelf.Request('GET', Uri.parse('http://localhost/api/characters'),
          headers: headers);

  shelf.Response jsonResponse(String body) => shelf.Response.ok(
        body,
        headers: {'Content-Type': 'application/json; charset=utf-8'},
      );

  test('compresses a large JSON body when the client accepts gzip', () async {
    final res = await wrap(() => jsonResponse(bigJson))(
      get({'Accept-Encoding': 'gzip'}),
    );

    expect(res.headers[HttpHeaders.contentEncodingHeader], 'gzip');
    expect(res.headers['vary'], contains('Accept-Encoding'));

    // Body must be the gzip of the original JSON, and losslessly recoverable.
    final compressed = (await res.read().toList()).expand((c) => c).toList();
    expect(compressed.length, lessThan(bigJson.length));
    expect(res.headers[HttpHeaders.contentLengthHeader], '${compressed.length}');
    expect(utf8.decode(gzip.decode(compressed)), bigJson);
  });

  test('leaves the body untouched when the client does not accept gzip', () async {
    final res = await wrap(() => jsonResponse(bigJson))(get(const {}));

    expect(res.headers.containsKey(HttpHeaders.contentEncodingHeader), isFalse);
    expect(await res.readAsString(), bigJson);
  });

  test('does not compress a body under the size floor', () async {
    final small = jsonEncode({'ok': true});
    final res = await wrap(() => jsonResponse(small))(
      get({'Accept-Encoding': 'gzip'}),
    );

    expect(res.headers.containsKey(HttpHeaders.contentEncodingHeader), isFalse);
    expect(await res.readAsString(), small);
  });

  test('does not compress a non-text content type (e.g. an image)', () async {
    final bytes = List<int>.filled(5000, 7);
    final res = await wrap(
      () => shelf.Response.ok(bytes, headers: {'Content-Type': 'image/png'}),
    )(get({'Accept-Encoding': 'gzip'}));

    expect(res.headers.containsKey(HttpHeaders.contentEncodingHeader), isFalse);
  });

  test('passes a WebSocket upgrade request through untouched', () async {
    // Even a large JSON-typed response must not be read/compressed on an
    // upgrade request — reading it would break the socket hijack.
    final res = await wrap(() => jsonResponse(bigJson))(
      get({'Accept-Encoding': 'gzip', 'Upgrade': 'websocket'}),
    );

    expect(res.headers.containsKey(HttpHeaders.contentEncodingHeader), isFalse);
    expect(await res.readAsString(), bigJson);
  });

  test('does not double-encode an already-encoded response', () async {
    final res = await wrap(
      () => shelf.Response.ok(
        List<int>.filled(5000, 65),
        headers: {
          'Content-Type': 'application/json',
          HttpHeaders.contentEncodingHeader: 'br',
        },
      ),
    )(get({'Accept-Encoding': 'gzip'}));

    expect(res.headers[HttpHeaders.contentEncodingHeader], 'br');
  });
}
