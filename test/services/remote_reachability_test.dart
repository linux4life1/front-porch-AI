// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:front_porch_ai/services/services.dart';

void main() {
  group('remoteBackendStatusLabel', () {
    test('unconfigured is never Ready', () {
      // A server that answered before a model was picked is connected (it
      // used to read the red "Not configured" beside "Found 1 model").
      final answered = remoteBackendStatusLabel(
        configured: false,
        reachability: RemoteReachability.reachable,
      );
      expect(answered, isNot('Ready'));
      expect(answered, 'Connected — pick a model');
      expect(
        remoteBackendStatusLabel(
          configured: false,
          reachability: RemoteReachability.unknown,
        ),
        'Not configured',
      );
    });

    test('configured without a ping is not the green Ready badge', () {
      expect(
        remoteBackendStatusLabel(
          configured: true,
          reachability: RemoteReachability.unknown,
        ),
        'Configured',
      );
    });

    test('only a successful ping is Ready', () {
      expect(
        remoteBackendStatusLabel(
          configured: true,
          reachability: RemoteReachability.reachable,
        ),
        'Ready',
      );
    });

    test('a failed ping is configured but unreachable', () {
      expect(
        remoteBackendStatusLabel(
          configured: true,
          reachability: RemoteReachability.unreachable,
        ),
        'Configured but unreachable',
      );
    });
  });

  group('pingRemoteModels', () {
    test('200 on GET /models is success', () async {
      final client = MockClient((request) async {
        expect(request.method, 'GET');
        expect(request.url.path, '/api/v1/models');
        return http.Response('{"data":[]}', 200);
      });
      final result = await pingRemoteModels(
        apiUrl: 'https://openrouter.ai/api/v1',
        apiKey: 'sk-test',
        client: client,
      );
      expect(result.ok, isTrue);
      expect(result.message, contains('successful'));
    });

    test('non-200 is failure', () async {
      final client = MockClient(
        (_) async => http.Response('{"error":{"message":"Unauthorized"}}', 401),
      );
      final result = await pingRemoteModels(
        apiUrl: 'https://openrouter.ai/api/v1',
        apiKey: 'sk-bad',
        client: client,
      );
      expect(result.ok, isFalse);
      expect(result.message, contains('Unauthorized'));
    });

    test('empty key on a remote URL is failure without a request', () async {
      var called = false;
      final client = MockClient((_) async {
        called = true;
        return http.Response('{}', 200);
      });
      final result = await pingRemoteModels(
        apiUrl: 'https://openrouter.ai/api/v1',
        apiKey: '',
        client: client,
      );
      expect(called, isFalse);
      expect(result.ok, isFalse);
      expect(result.message, contains('API key'));
    });
  });
}
