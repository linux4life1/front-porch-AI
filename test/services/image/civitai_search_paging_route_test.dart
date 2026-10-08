// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The phone's CivitAI search follows CivitAI's cursor past an empty first
// page, hands the phone a cursor for Load more, and sends a "Klein (all)"
// pick as all four Klein bases. A real loopback server plays CivitAI; the
// address it is asked at is the one the real planner built.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import 'package:front_porch_ai/services/image/civitai_client.dart';
import 'package:front_porch_ai/services/image/civitai_credentials.dart';
import 'package:front_porch_ai/services/web/middleware/auth_middleware.dart';
import 'package:front_porch_ai/services/web/routes/civitai_routes.dart';

import 'civitai_route_support.dart';
import 'civitai_test_server.dart';

/// The real plan, pointed at the loopback server instead of civitai.com.
class _LoopbackRelay extends CivitaiRelay {
  _LoopbackRelay(this.host)
    : super(
        CivitaiCredentialStore(
          readKey: (_) async => null,
          writeKey: (_, _) async {},
          deleteKey: (_) async {},
        ),
      );

  final CivitaiFileHost host;

  @override
  Future<CivitaiSearchPlan> planSearch({
    required String accountId,
    required String query,
    required bool adult,
    required bool lora,
    String baseModel = '',
  }) async {
    final real = await super.planSearch(
      accountId: accountId,
      query: query,
      adult: adult,
      lora: lora,
      baseModel: baseModel,
    );
    return CivitaiSearchPlan(
      uri: real.uri!.replace(
        scheme: 'http',
        host: '127.0.0.1',
        port: host.port,
        path: '/models',
      ),
      authorization: real.authorization,
      log: real.log,
      needsCredential: real.needsCredential,
    );
  }
}

Map<String, Object?> _model(int id) => {
  'id': id,
  'name': 'Klein look $id',
  'type': 'LORA',
  'nsfw': false,
  'modelVersions': [
    {
      'id': id * 10,
      'files': [
        {'name': 'look$id.safetensors'},
      ],
    },
  ],
};

void main() {
  late CivitaiFileHost host;
  late List<Uri> asked;

  setUp(() async {
    host = await CivitaiFileHost.start();
    asked = [];
    // Page 1 has no Klein LoRA among its word matches; page 2 has one; the
    // rest are empty, with more always said to follow.
    host.routes['/models'] = (request) async {
      asked.add(request.uri);
      final cursor = request.uri.queryParameters['cursor'];
      final n = cursor == null ? 1 : int.parse(cursor.substring(1));
      request.response.headers.contentType = ContentType.json;
      request.response.write(
        jsonEncode({
          'items': [if (n == 2) _model(2), if (n == 9) _model(9)],
          'metadata': {'nextCursor': 'p${n + 1}'},
        }),
      );
      await request.response.close();
    };
  });

  Future<Map<String, dynamic>> search(String query) async {
    final harness = await CivitaiAuthHarness.create();
    final routes = CivitaiRoutes(
      Router(),
      auth: harness.auth,
      adultAllowed: () => false,
      relay: _LoopbackRelay(host),
    );
    final response = await routes.search(
      Request(
        'GET',
        Uri.parse('http://localhost/api/image/civitai/search?$query'),
        context: {kAuthUserIdContextKey: 'local'},
      ),
    );
    expect(response.statusCode, 200);
    return jsonDecode(await response.readAsString()) as Map<String, dynamic>;
  }

  test('an empty first page is followed to the rows after it, and the phone '
      'gets a cursor for Load more', () async {
    final body = await search(
      'q=look&sheet=lora&adult=false&base=${Uri.encodeQueryComponent('Flux.2 Klein (all)')}',
    );
    final items = body['items'] as List;
    expect(items.map((i) => (i as Map)['id']), [2]);
    expect(asked, hasLength(5), reason: 'five pages, then it stops');
    expect(body['nextCursor'], 'p6');
    for (final uri in asked) {
      expect(uri.queryParametersAll['baseModels'], [
        'Flux.2 Klein 9B',
        'Flux.2 Klein 9B-base',
        'Flux.2 Klein 4B',
        'Flux.2 Klein 4B-base',
      ]);
      expect(uri.queryParameters['limit'], '100');
      expect(uri.queryParameters['query'], 'look');
    }
    expect(asked.first.queryParameters.containsKey('cursor'), isFalse);
    expect(asked[1].queryParameters['cursor'], 'p2');
  });

  test('Load more carries on from the cursor the phone sends back', () async {
    final body = await search(
      'q=look&sheet=lora&adult=false&base=Pony&cursor=p7',
    );
    expect(asked.first.queryParameters['cursor'], 'p7');
    expect(asked.first.queryParametersAll['baseModels'], ['Pony']);
    expect((body['items'] as List).map((i) => (i as Map)['id']), [9]);
  });

  test('nothing in 500 results, with more to come, says so', () async {
    host.routes['/models'] = (request) async {
      final cursor = request.uri.queryParameters['cursor'] ?? 'p1';
      request.response.headers.contentType = ContentType.json;
      request.response.write(
        jsonEncode({
          'items': <Object>[],
          'metadata': {'nextCursor': '${cursor}x'},
        }),
      );
      await request.response.close();
    };
    final body = await search('q=look&sheet=lora&adult=false&base=Pony');
    expect(body['items'], isEmpty);
    expect(body['nextCursor'], isNotNull);
    expect(
      body['note'],
      'No matches in the first 500 results. Try a different word, or Load '
      'more.',
    );
  });
}
