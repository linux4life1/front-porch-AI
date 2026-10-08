// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/services/image/civitai_client.dart';
import 'package:front_porch_ai/services/image/civitai_credentials.dart';
import 'package:front_porch_ai/services/web/middleware/auth_middleware.dart';
import 'package:front_porch_ai/services/web/routes/civitai_routes.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import 'civitai_route_support.dart';

class _RecordingRelay extends CivitaiRelay {
  _RecordingRelay(super.store);

  String? seenQuery;
  String? seenBase;
  bool? seenLora;

  @override
  Future<CivitaiSearchPlan> planSearch({
    required String accountId,
    required String query,
    required bool adult,
    required bool lora,
    String baseModel = '',
  }) async {
    seenQuery = query;
    seenBase = baseModel;
    seenLora = lora;
    return const CivitaiSearchPlan(
      uri: null,
      authorization: null,
      log: 'test',
      needsCredential: false,
    );
  }
}

void main() {
  test('search notes name a missing key, a refused key, and an empty list', () {
    expect(
      civitaiSearchNote(
        kind: CivitaiHttpKind.needsCredential,
        hadKey: false,
        rows: 0,
      ),
      'Paste an API key to search adult models.',
    );
    expect(
      civitaiSearchNote(
        kind: CivitaiHttpKind.needsCredential,
        hadKey: true,
        rows: 0,
      ),
      'That API key was refused. Paste a valid key and search again.',
    );
    expect(
      civitaiSearchNote(kind: CivitaiHttpKind.ok, hadKey: true, rows: 0),
      'CivitAI returned no models for that search.',
    );
    expect(
      civitaiSearchNote(kind: CivitaiHttpKind.ok, hadKey: true, rows: 2),
      isEmpty,
    );
  });

  test('the search route forwards base and the text query', () async {
    final relay = _RecordingRelay(
      CivitaiCredentialStore(
        readKey: (_) async => null,
        writeKey: (_, _) async {},
        deleteKey: (_) async {},
      ),
    );
    final harness = await CivitaiAuthHarness.create();
    final routes = CivitaiRoutes(
      Router(),
      auth: harness.auth,
      adultAllowed: () => false,
      relay: relay,
    );
    final response = await routes.search(
      Request(
        'GET',
        Uri.parse(
          'http://localhost/api/image/civitai/search'
          '?q=Clothes&sheet=lora&base=SD%203.5&adult=false',
        ),
        context: {kAuthUserIdContextKey: 'local'},
      ),
    );
    expect(response.statusCode, 200);
    expect(relay.seenQuery, 'Clothes');
    expect(relay.seenBase, 'SD 3.5');
    expect(relay.seenLora, isTrue);
  });

  test(
    'credential status says a key is saved and does not return it',
    () async {
      final box = <String, String>{'civitai_credential_local': 'green-key'};
      final harness = await CivitaiAuthHarness.create();
      final routes = CivitaiRoutes(
        Router(),
        auth: harness.auth,
        adultAllowed: () => false,
        relay: CivitaiRelay(
          CivitaiCredentialStore(
            readKey: (key) async => box[key],
            writeKey: (key, value) async => box[key] = value,
            deleteKey: (key) async => box.remove(key),
          ),
        ),
      );
      final response = await routes.credentialStatus(
        Request(
          'GET',
          Uri.parse('http://localhost/api/image/civitai/credential'),
          context: {kAuthUserIdContextKey: 'local'},
        ),
      );
      expect(response.statusCode, 200);
      final body = jsonDecode(await response.readAsString()) as Map;
      expect(body, {'saved': true});
      expect(body.toString().contains('green-key'), isFalse);
    },
  );
}
