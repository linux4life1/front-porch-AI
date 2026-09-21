// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Security boundaries for model-supplied web-search input and outbound HTTP.
//
// Guards proven red before passing:
//   * bypass prepareQuery in lookup → the request carried all 2,048 runes
//   * set followRedirects back to true → both redirect tests failed

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'package:front_porch_ai/services/chat/chat.dart';

void main() {
  test('model query is hard-capped before cache, receipt, or HTTP', () async {
    final fetched = <Uri>[];
    final search = WebSearchService(
      getApiKey: () => 'tavily-test-key',
      fetch: (uri, key) async {
        fetched.add(uri);
        return '{"results":[]}';
      },
    );
    final oversized = '${'🔎' * 2048}   trailing words';

    final result = await search.lookup(oversized);

    expect(result.query.runes, hasLength(kWebSearchQueryMaxChars));
    expect(fetched, hasLength(1));
    expect(
      fetched.single.queryParameters['q']!.runes,
      hasLength(kWebSearchQueryMaxChars),
    );
    expect(
      result.query,
      WebSearchService.prepareQuery(oversized),
      reason: 'the receipt and the wire must describe the same bounded query',
    );
  });

  test('Tavily request refuses redirects and keeps its key on-host', () async {
    final requests = <http.BaseRequest>[];
    final search = WebSearchService(
      getApiKey: () => 'tavily-secret',
      sendRequest: (request) async {
        requests.add(request);
        return http.Response(
          'redirect body must not be parsed',
          302,
          headers: {'location': 'https://attacker.invalid/steal'},
          request: request,
        );
      },
    );

    final result = await search.lookup('porch weather');

    expect(result.ok, isFalse);
    expect(requests, hasLength(1), reason: 'a redirect must not issue a hop');
    final request = requests.single as http.Request;
    expect(request.followRedirects, isFalse);
    expect(request.maxRedirects, 0);
    expect(request.url, Uri.parse(kTavilySearchEndpoint));
    expect(request.url.scheme, 'https');
    expect(request.url.host, 'api.tavily.com');
    expect(request.headers['Authorization'], 'Bearer tavily-secret');
    expect(jsonDecode(request.body)['query'], 'porch weather');
  });

  test('Wikipedia request refuses redirects and never carries a key', () async {
    final requests = <http.BaseRequest>[];
    final search = WebSearchService(
      getApiKey: () => '',
      sendRequest: (request) async {
        requests.add(request);
        return http.Response(
          'redirect body must not be parsed',
          307,
          headers: {'location': 'http://127.0.0.1/private'},
          request: request,
        );
      },
    );

    final result = await search.lookup('Wandenreich');

    expect(result.ok, isFalse);
    expect(requests, hasLength(1), reason: 'a redirect must not issue a hop');
    final request = requests.single;
    expect(request.followRedirects, isFalse);
    expect(request.maxRedirects, 0);
    expect(request.url.scheme, 'https');
    expect(request.url.host, 'en.wikipedia.org');
    expect(request.url.path, Uri.parse(kWikipediaSearchEndpoint).path);
    expect(request.url.queryParameters['q'], 'Wandenreich');
    expect(
      request.headers.keys.map((key) => key.toLowerCase()),
      isNot(contains('authorization')),
    );
  });
}
