// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// /search and /wiki require `--` and the words to look up. A roleplay line
// after a bare /search is not a query. Proven red by deleting parseLookupForce
// (this file fails to compile) and by treating the text after /search as the
// query (the smile case expects a rejection, not webQuery).

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'package:front_porch_ai/services/chat/chat.dart';

void main() {
  test('bare /search before roleplay is not a lookup', () {
    final parsed = parseLookupForce('/search *I smile softly at you*');
    expect(parsed.attempted, isTrue);
    expect(parsed.accepted, isFalse);
    expect(parsed.webQuery, isNull);
    expect(parsed.wikiQuery, isNull);
    expect(parsed.error, contains('--'));
  });

  test('words after -- are the only query', () {
    final parsed = parseLookupForce(
      '*I smile softly at you* /search -- Wandenreich',
    );
    expect(parsed.accepted, isTrue);
    expect(parsed.body, '*I smile softly at you*');
    expect(parsed.webQuery, 'Wandenreich');
    expect(parsed.userText, '*I smile softly at you*');
  });

  test('a command with no other line stores the query as the message', () {
    final parsed = parseLookupForce('/wiki -- the harvest rite');
    expect(parsed.accepted, isTrue);
    expect(parsed.wikiQuery, 'the harvest rite');
    expect(parsed.userText, 'the harvest rite');
  });

  test('both commands keep their own words', () {
    final parsed = parseLookupForce(
      'what was that /wiki -- the rite /search -- Wandenreich',
    );
    expect(parsed.accepted, isTrue);
    expect(parsed.body, 'what was that');
    expect(parsed.wikiQuery, 'the rite');
    expect(parsed.webQuery, 'Wandenreich');
  });

  test('a /search in the middle of a line stays in the story', () {
    final parsed = parseLookupForce('she said /search and smiled');
    expect(parsed.attempted, isFalse);
  });

  test('/search -- with no words is rejected', () {
    final parsed = parseLookupForce('hello /search --');
    expect(parsed.attempted, isTrue);
    expect(parsed.accepted, isFalse);
  });

  test('web search that is off blocks /search and leaves /wiki alone', () {
    final blocked = lookupForceUnavailable(
      webQuery: 'Wandenreich',
      wikiQuery: null,
      webEnabled: false,
      hasWiki: true,
    );
    expect(blocked, contains('Web Search'));
    expect(
      lookupForceUnavailable(
        webQuery: null,
        wikiQuery: 'the rite',
        webEnabled: false,
        hasWiki: true,
      ),
      isNull,
    );
  });

  test('no wiki blocks /wiki', () {
    final blocked = lookupForceUnavailable(
      webQuery: null,
      wikiQuery: 'the rite',
      webEnabled: true,
      hasWiki: false,
    );
    expect(blocked, contains('wiki'));
  });

  test(
    'a forced web lookup fetches the named words, not the roleplay',
    () async {
      final uris = <Uri>[];
      final web = WebSearchService(
        getApiKey: () => '',
        sendRequest: (request) async {
          uris.add(request.url);
          return http.Response(
            jsonEncode({
              'pages': [
                {'title': 'Wandenreich', 'excerpt': 'An army in Bleach.'},
              ],
            }),
            200,
          );
        },
      );
      final wiki = WikiSearchService(getBaseUrl: () => '');
      final outcome = await runForcedLookups(
        web: web,
        wiki: wiki,
        webQuery: 'Wandenreich',
        wikiQuery: null,
      );
      expect(uris, isNotEmpty);
      expect(uris.single.query, contains('Wandenreich'));
      expect(uris.single.toString(), isNot(contains('smile')));
      expect(outcome.searchReceipt?['query'], 'Wandenreich');
      expect(outcome.searchReceipt?['ok'], isTrue);
      expect(outcome.injection, contains('Wandenreich'));
      expect(web.httpCalls, 1);
    },
  );
}
