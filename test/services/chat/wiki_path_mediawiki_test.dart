// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Self-hosted MediaWiki under a non-root path must still hit the Action API.
// Proven: /w/ used to miss both Tiddly and the root-only MW fallback.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'package:front_porch_ai/services/chat/chat.dart';

void main() {
  test('path-hosted MediaWiki uses /w/api.php, not origin only', () {
    final base = parseWikiBaseUrl('https://wiki.example.com/w/')!;
    expect(base.path, '/w/');
    expect(mediawikiActionApiUri(base).path, '/w/api.php');
    expect(mediawikiSearchUri(base, 'Aizen').path, '/w/api.php');
  });

  test('self-hosted MediaWiki under /w/ still lists pages', () async {
    final fetched = <Uri>[];
    final wiki = WikiSearchService(
      getBaseUrl: () => 'https://wiki.example.com/w/',
      sendRequest: (request) async {
        fetched.add(request.url);
        if (request.url.path == '/w/api.php') {
          final action = request.url.queryParameters['action'];
          final list = request.url.queryParameters['list'];
          final meta = request.url.queryParameters['meta'];
          if (action == 'query' && meta == 'siteinfo') {
            return http.Response(
              jsonEncode({
                'query': {
                  'general': {'sitename': 'Path Wiki'},
                },
              }),
              200,
            );
          }
          if (action == 'query' && list == 'allpages') {
            return http.Response(
              jsonEncode({
                'query': {
                  'allpages': [
                    {'title': 'Sosuke Aizen'},
                  ],
                },
              }),
              200,
            );
          }
        }
        if (request.url.path.endsWith('api.php')) {
          return http.Response('nope', 404);
        }
        return http.Response(
          '<html><body>not a tiddler store</body></html>',
          200,
        );
      },
    );
    final catalog = await wiki.listStudioTitles();
    expect(catalog.backend, WikiBackend.mediawiki);
    expect(catalog.titles, contains('Sosuke Aizen'));
    expect(fetched.any((u) => u.path == '/w/api.php'), isTrue);
    expect(
      fetched.where((u) => u.path == '/api.php'),
      isEmpty,
      reason: 'path-hosted MW must not only probe origin /api.php',
    );
  });
}
