// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The pictures in a CivitAI listing on the phone: an X-rated picture is not
// shown with adult results off (though its model is listed), only CivitAI's
// own image host is passed on, and the phone's Content-Security-Policy lets
// pictures load from that host and no other.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import 'package:front_porch_ai/services/image/civitai_client.dart';
import 'package:front_porch_ai/services/image/civitai_credentials.dart';
import 'package:front_porch_ai/services/web/middleware/auth_middleware.dart';
import 'package:front_porch_ai/services/web/middleware/security_headers.dart';
import 'package:front_porch_ai/services/web/routes/civitai_routes.dart';

import 'civitai_route_support.dart';
import 'civitai_test_server.dart';

String _listing(List<Map<String, Object?>> images) => jsonEncode({
  'items': [
    {
      'id': 3,
      'name': 'Soft light',
      'type': 'LORA',
      'nsfw': false,
      'modelVersions': [
        {
          'id': 30,
          'images': images,
          'files': [
            {'name': 'soft.safetensors'},
          ],
        },
      ],
    },
  ],
});

const _cdn = 'https://image.civitai.com';

final _pictures = <Map<String, Object?>>[
  {'url': '$_cdn/pg.jpeg', 'nsfwLevel': 1},
  {'url': '$_cdn/r.jpeg', 'nsfwLevel': 4},
  {'url': '$_cdn/x.jpeg', 'nsfwLevel': 8},
  {'url': '$_cdn/xxx.jpeg', 'nsfwLevel': 16},
  {'url': '$_cdn/legacy-mature.jpeg', 'nsfw': 'Mature'},
  {'url': '$_cdn/legacy-flag.jpeg', 'nsfw': true},
  {'url': '$_cdn/legacy-none.jpeg', 'nsfw': 'None'},
  {'url': '$_cdn/unrated.jpeg'},
];

class _Relay extends CivitaiRelay {
  _Relay(this.uri) : super(_emptyStore());

  final Uri uri;

  @override
  Future<CivitaiSearchPlan> planSearch({
    required String accountId,
    required String query,
    required bool adult,
    required bool lora,
    String baseModel = '',
  }) async => CivitaiSearchPlan(
    uri: uri,
    authorization: null,
    log: 'test',
    needsCredential: false,
  );
}

CivitaiCredentialStore _emptyStore() => CivitaiCredentialStore(
  readKey: (_) async => null,
  writeKey: (_, _) async {},
  deleteKey: (_) async {},
);

void main() {
  group('a picture in a listing', () {
    test('rated X or above is left out unless adult results are on', () {
      final body = _listing(_pictures);

      final off = parseCivitaiModels(body, includeAdult: false).single;
      expect(off.imageUrls, [
        '$_cdn/pg.jpeg',
        '$_cdn/r.jpeg',
        '$_cdn/legacy-none.jpeg',
        '$_cdn/unrated.jpeg',
      ]);
      expect(off.previewUrl, '$_cdn/pg.jpeg');

      final on = parseCivitaiModels(body, includeAdult: true).single;
      expect(on.imageUrls, hasLength(_pictures.length));
    });

    test('an X-rated first picture does not become the preview', () {
      final body = _listing([
        {'url': '$_cdn/x.jpeg', 'nsfwLevel': 8},
        {'url': '$_cdn/pg.jpeg', 'nsfwLevel': 1},
      ]);
      final row = parseCivitaiModels(body, includeAdult: false).single;
      expect(row.previewUrl, '$_cdn/pg.jpeg');
    });
  });

  group('the search route', () {
    Future<Map<String, dynamic>> search(
      CivitaiFileHost host,
      String body,
    ) async {
      host.routes['/models'] = (request) async {
        request.response.headers.contentType = ContentType(
          'application',
          'json',
        );
        request.response.write(body);
        await request.response.close();
      };
      final harness = await CivitaiAuthHarness.create();
      final routes = CivitaiRoutes(
        Router(),
        auth: harness.auth,
        adultAllowed: () => true,
        relay: _Relay(host.uri('/models')),
      );
      final response = await routes.search(
        Request(
          'GET',
          Uri.parse('http://localhost/api/image/civitai/search?q=a&adult=true'),
          context: {kAuthUserIdContextKey: 'local'},
        ),
      );
      expect(response.statusCode, 200);
      return jsonDecode(await response.readAsString()) as Map<String, dynamic>;
    }

    test('passes on only pictures from CivitAI\'s own https host', () async {
      final host = await CivitaiFileHost.start();
      final json = await search(
        host,
        _listing([
          {'url': 'https://tracker.example/pixel.jpeg', 'nsfwLevel': 1},
          {'url': 'https://image.civitai.com.evil.example/a.jpeg'},
          {'url': 'http://image.civitai.com/insecure.jpeg'},
          {'url': '$_cdn/ok.jpeg', 'nsfwLevel': 1},
        ]),
      );

      final item = (json['items'] as List).single as Map<String, dynamic>;
      expect(item['images'], ['$_cdn/ok.jpeg']);
      expect(item['previewUrl'], '$_cdn/ok.jpeg');
    });

    test('has no preview when none of the pictures is on that host', () async {
      final host = await CivitaiFileHost.start();
      final json = await search(
        host,
        _listing([
          {'url': 'https://tracker.example/pixel.jpeg', 'nsfwLevel': 1},
        ]),
      );

      final item = (json['items'] as List).single as Map<String, dynamic>;
      expect(item['images'], isEmpty);
      expect(item['previewUrl'], isNull);
    });
  });

  test(
    'the Content-Security-Policy lets pictures load from that host only',
    () {
      const csp = SecurityHeaders.contentSecurityPolicy;
      final imgSrc = csp
          .split(';')
          .map((d) => d.trim())
          .firstWhere((d) => d.startsWith('img-src'));

      expect(imgSrc, "img-src 'self' data: blob: https://image.civitai.com");
      expect(csp, contains("default-src 'self'"));
      expect(csp, contains("connect-src 'self'"));
    },
  );
}
