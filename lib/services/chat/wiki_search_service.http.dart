// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

part of 'wiki_search_service.dart';

mixin _WikiHttp {
  Future<http.Response> Function(http.BaseRequest request)? get sendRequest;

  Future<http.Response> _get(
    Uri uri, {
    required String kind,
    required int cap,
    bool followRedirects = false,
  }) async {
    debugPrint(
      '[Wiki] HTTP start host=${uri.host} kind=$kind path=${uri.path}',
    );
    final request = http.Request('GET', uri)
      ..headers['User-Agent'] = kWikiUserAgent
      ..headers['Accept'] = kind == 'html'
          ? 'text/html,application/xhtml+xml;q=0.9,*/*;q=0.8'
          : 'application/json'
      ..followRedirects = followRedirects
      ..maxRedirects = followRedirects ? 3 : 0;
    final resp = await _send(request, cap: cap, kind: kind);
    debugPrint(
      '[Wiki] status=${resp.statusCode} bodyChars=${resp.bodyBytes.length}',
    );
    return resp;
  }

  Future<http.Response> _send(
    http.Request request, {
    required int cap,
    required String kind,
  }) async {
    final custom = sendRequest;
    if (custom != null) {
      final resp = await custom(request).timeout(kWebSearchTimeout);
      return _maybeCap(resp, cap: cap, kind: kind);
    }
    final client = http.Client();
    try {
      return await (() async {
        final streamed = await client.send(request);
        final finalUrl = streamed.request?.url ?? request.url;
        if (!isSafeOutboundUrl(finalUrl)) {
          debugPrint('[Wiki] miss/fail reason=unsafe redirect');
          return http.Response('', 403);
        }
        final builder = BytesBuilder(copy: false);
        var dropped = false;
        await for (final chunk in streamed.stream) {
          if (builder.length >= cap) {
            dropped = true;
            break;
          }
          final room = cap - builder.length;
          if (chunk.length <= room) {
            builder.add(chunk);
          } else {
            builder.add(chunk.sublist(0, room));
            dropped = true;
            break;
          }
        }
        if (dropped) {
          debugPrint(
            '[${kind == 'html' ? 'Tiddly' : 'Wiki'}] cap would have dropped '
            'bodyChars>=$cap cap=$cap',
          );
          if (kind != 'html') {
            return http.Response('', 413);
          }
        }
        final headers = Map<String, String>.from(streamed.headers);
        if (!headers.keys.any((k) => k.toLowerCase() == 'content-type')) {
          headers['content-type'] = 'text/html; charset=utf-8';
        }
        return http.Response.bytes(
          builder.takeBytes(),
          streamed.statusCode,
          headers: headers,
        );
      })().timeout(kWebSearchTimeout);
    } finally {
      client.close();
    }
  }

  http.Response _maybeCap(
    http.Response resp, {
    required int cap,
    required String kind,
  }) {
    if (resp.bodyBytes.length <= cap) return resp;
    debugPrint(
      '[${kind == 'html' ? 'Tiddly' : 'Wiki'}] cap would have dropped '
      'bodyChars=${resp.bodyBytes.length} cap=$cap',
    );
    if (kind == 'html') {
      return http.Response.bytes(
        resp.bodyBytes.sublist(0, cap),
        resp.statusCode,
        headers: resp.headers,
      );
    }
    return resp;
  }
}
