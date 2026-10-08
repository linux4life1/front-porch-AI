// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// A word plus a base found nothing: CivitAI takes a page of word matches and
// only then keeps the bases asked for, so the first page can be empty while
// later ones are not. The search asks for big pages, follows CivitAI's
// cursor, and says when there may be more.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:front_porch_ai/services/image/civitai_bases.dart';
import 'package:front_porch_ai/services/image/civitai_client.dart';
import 'package:front_porch_ai/services/image/civitai_credentials.dart';
import 'package:front_porch_ai/services/image/civitai_search_pages.dart';

Map<String, Object?> _model(int id, {bool adult = false}) => {
  'id': id,
  'name': 'Model $id',
  'type': 'LORA',
  'nsfw': adult,
  'modelVersions': [
    {
      'id': id * 10,
      'files': [
        {'name': 'm$id.safetensors'},
      ],
    },
  ],
};

String _page(List<Map<String, Object?>> items, {String? next}) => jsonEncode({
  'items': items,
  'metadata': {'nextCursor': ?next},
});

/// CivitAI as a list of answers, one per cursor (null for the first page).
class _Pages {
  _Pages(this.answers);

  final Map<String?, ({int status, String body})> answers;
  final List<Uri> asked = [];

  Future<({int status, String body})> get(
    Uri uri,
    Map<String, String> headers,
  ) async {
    asked.add(uri);
    return answers[uri.queryParameters['cursor']] ??
        (status: 500, body: 'no such page');
  }
}

final Uri _first = civitaiModelsUri(
  query: 'clothes',
  adult: false,
  hasCredential: false,
  lora: true,
  baseModels: const ['Flux.2 Klein 9B'],
)!;

void main() {
  group('the models address', () {
    test('sends every base as its own baseModels value', () {
      final uri = civitaiModelsUri(
        query: 'clothes',
        adult: false,
        hasCredential: false,
        lora: true,
        baseModels: civitaiBaseSends('Flux.2 Klein (all)'),
      )!;
      expect(uri.queryParametersAll['baseModels'], [
        'Flux.2 Klein 9B',
        'Flux.2 Klein 9B-base',
        'Flux.2 Klein 4B',
        'Flux.2 Klein 4B-base',
      ]);
    });

    test('asks for 100 a page only for a word plus a base', () {
      String limit({String query = '', List<String> bases = const []}) =>
          civitaiModelsUri(
            query: query,
            adult: false,
            hasCredential: false,
            lora: true,
            baseModels: bases,
          )!.queryParameters['limit']!;
      expect(limit(query: 'clothes', bases: ['Pony']), '100');
      expect(limit(query: 'clothes'), '20');
      expect(limit(bases: ['Pony']), '20');
      expect(limit(query: '   ', bases: ['Pony']), '20');
    });

    test('carries a cursor, and never browsingLevel', () {
      final uri = civitaiModelsUri(
        query: 'x',
        adult: false,
        hasCredential: false,
        lora: false,
        cursor: '123|456',
      )!;
      expect(uri.queryParameters['cursor'], '123|456');
      expect(uri.queryParameters.containsKey('browsingLevel'), isFalse);
      expect(
        civitaiModelsUri(
          query: 'x',
          adult: false,
          hasCredential: false,
          lora: false,
        )!.queryParameters.containsKey('cursor'),
        isFalse,
      );
    });

    test('adult goes to civitai.red with nsfw=true, the key only in the '
        'header', () async {
      final relay = CivitaiRelay(
        CivitaiCredentialStore(
          readKey: (_) async => 'secret-key-123',
          writeKey: (_, _) async {},
          deleteKey: (_) async {},
        ),
      );
      final plan = await relay.planSearch(
        accountId: 'local',
        query: 'clothes',
        adult: true,
        lora: true,
        baseModel: 'Flux.2 Klein (all)',
      );
      final uri = plan.uri!;
      expect(uri.host, 'civitai.red');
      expect(uri.queryParameters['nsfw'], 'true');
      expect(uri.queryParametersAll['baseModels'], hasLength(4));
      expect(uri.queryParameters['limit'], '100');
      expect(uri.toString(), isNot(contains('secret-key-123')));
      expect(plan.authorization, 'Bearer secret-key-123');
    });
  });

  test('the next cursor is read from metadata, and its end is null', () {
    expect(civitaiNextCursor(_page(const [], next: 'abc')), 'abc');
    expect(civitaiNextCursor(_page(const [])), isNull);
    expect(civitaiNextCursor('{"metadata":{"nextCursor":42}}'), '42');
    expect(civitaiNextCursor('not json'), isNull);
  });

  group('following the pages', () {
    test('an empty first page with a cursor goes on to the rows after it, '
        'with the same words and bases', () async {
      final pages = _Pages({
        null: (status: 200, body: _page(const [], next: 'c2')),
        'c2': (status: 200, body: _page([_model(1), _model(2)])),
      });
      final found = await civitaiSearchPages(
        first: _first,
        headers: const {},
        includeAdult: false,
        get: pages.get,
      );
      expect(found.rows.map((r) => r.id), [1, 2]);
      expect(found.kind, CivitaiHttpKind.ok);
      expect(found.exhausted, isTrue);
      expect(pages.asked, hasLength(2));
      final second = pages.asked.last;
      expect(second.queryParameters['cursor'], 'c2');
      expect(second.queryParameters['query'], 'clothes');
      expect(second.queryParametersAll['baseModels'], ['Flux.2 Klein 9B']);
      expect(found.note(hadKey: false), isEmpty);
    });

    test('stops at 20 rows, keeping where to go on from', () async {
      final pages = _Pages({
        null: (
          status: 200,
          body: _page([for (var i = 0; i < 12; i++) _model(i)], next: 'c2'),
        ),
        'c2': (
          status: 200,
          body: _page([for (var i = 12; i < 24; i++) _model(i)], next: 'c3'),
        ),
        'c3': (status: 200, body: _page([_model(99)])),
      });
      final found = await civitaiSearchPages(
        first: _first,
        headers: const {},
        includeAdult: false,
        get: pages.get,
      );
      expect(found.rows, hasLength(24));
      expect(found.nextCursor, 'c3');
      expect(found.exhausted, isFalse);
      expect(pages.asked, hasLength(2));
    });

    test('stops after 5 pages and says there may be more', () async {
      final pages = _Pages({
        null: (status: 200, body: _page(const [], next: 'c1')),
        for (var i = 1; i < 9; i++)
          'c$i': (status: 200, body: _page(const [], next: 'c${i + 1}')),
      });
      final found = await civitaiSearchPages(
        first: _first,
        headers: const {},
        includeAdult: false,
        get: pages.get,
      );
      expect(pages.asked, hasLength(5));
      expect(found.rows, isEmpty);
      expect(found.nextCursor, 'c5');
      expect(found.scanned, 500);
      expect(
        found.note(hadKey: false),
        'No matches in the first 500 results. Try a different word, or '
        'Load more.',
      );
    });

    test('stops when the time is up', () async {
      final pages = _Pages({
        null: (status: 200, body: _page(const [], next: 'c1')),
        'c1': (status: 200, body: _page(const [], next: 'c2')),
      });
      final found = await civitaiSearchPages(
        first: _first,
        headers: const {},
        includeAdult: false,
        get: pages.get,
        budget: Duration.zero,
      );
      expect(pages.asked, hasLength(1));
      expect(found.nextCursor, 'c1');
    });

    test('a model on two pages is listed once', () async {
      final pages = _Pages({
        null: (status: 200, body: _page([_model(1), _model(2)], next: 'c2')),
        'c2': (status: 200, body: _page([_model(2), _model(3)])),
      });
      final found = await civitaiSearchPages(
        first: _first,
        headers: const {},
        includeAdult: false,
        get: pages.get,
      );
      expect(found.rows.map((r) => r.id), [1, 2, 3]);
    });

    test('a refused second page stops it and keeps the first page', () async {
      final pages = _Pages({
        null: (status: 200, body: _page([_model(1)], next: 'c2')),
        'c2': (status: 401, body: '{}'),
        'c3': (status: 200, body: _page([_model(3)])),
      });
      final found = await civitaiSearchPages(
        first: _first,
        headers: const {'Authorization': 'Bearer k'},
        includeAdult: true,
        get: pages.get,
      );
      expect(pages.asked, hasLength(2));
      expect(found.kind, CivitaiHttpKind.needsCredential);
      expect(found.rows.map((r) => r.id), [1]);
      expect(
        found.note(hadKey: true),
        'That API key was refused. Paste a valid key and search again.',
      );
    });

    test('adult rows are kept only when adult results are on', () async {
      final answers = {
        null: (status: 200, body: _page([_model(1), _model(2, adult: true)])),
      };
      final off = await civitaiSearchPages(
        first: _first,
        headers: const {},
        includeAdult: false,
        get: _Pages(answers).get,
      );
      final on = await civitaiSearchPages(
        first: _first,
        headers: const {},
        includeAdult: true,
        get: _Pages(answers).get,
      );
      expect(off.rows.map((r) => r.id), [1]);
      expect(on.rows.map((r) => r.id), [1, 2]);
    });

    test('Load more starts from the cursor it is given', () async {
      final pages = _Pages({
        'c7': (status: 200, body: _page([_model(7)])),
      });
      final found = await civitaiSearchPages(
        first: _first,
        headers: const {},
        includeAdult: false,
        get: pages.get,
        cursor: 'c7',
      );
      expect(pages.asked.single.queryParameters['cursor'], 'c7');
      expect(found.rows.map((r) => r.id), [7]);
    });
  });

  test('the Klein choice sends all four Klein bases', () {
    expect(kCivitaiKleinAll.sends, hasLength(4));
    expect(civitaiBaseApiValues(), containsAll(kCivitaiKleinAll.sends));
    expect(civitaiBaseApiValues(), isNot(contains(kCivitaiKleinAll.api)));
    expect(civitaiBaseSends('Pony'), ['Pony']);
    expect(civitaiBaseSends(''), isEmpty);
    final installed = filterCivitaiBaseGroups(
      kCivitaiBaseGroups,
      onlyApis: {'Flux.2 Klein 4B'},
    );
    expect(civitaiBaseShown(installed, kCivitaiKleinAll.api), isTrue);
  });
}
