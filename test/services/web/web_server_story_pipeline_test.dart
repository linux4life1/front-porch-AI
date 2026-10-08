// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The app makes a new story pipeline when the chat backend switches (a
// pipeline binds its backend when it is made) and Provider disposes the old
// one. A running web server must follow the switch. It used to keep the
// pipeline it started with, so the phone's Director saves answered 500 and
// story jobs from the phone ran on the backend the server started with.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/services/embedding_service.dart';
import 'package:front_porch_ai/services/memory_service.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/services/web/web_server_host.dart';

void _setupPathProviderMock() {
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
        if (methodCall.method == 'getApplicationDocumentsDirectory') {
          return Directory.systemTemp.createTempSync('fpai_webstory_').path;
        }
        return null;
      });
}

/// A signed-in client of the real server on loopback.
class _Client {
  _Client(this.port);

  final int port;
  final _http = HttpClient();
  String? _cookie;

  Future<(int, Object?)> send(
    String method,
    String path, [
    Object? body,
  ]) async {
    final req = await _http.open(method, '127.0.0.1', port, path);
    final cookie = _cookie;
    if (cookie != null) req.headers.set(HttpHeaders.cookieHeader, cookie);
    if (body != null) {
      req.headers.contentType = ContentType.json;
      req.write(jsonEncode(body));
    }
    final res = await req.close();
    final text = await res.transform(utf8.decoder).join();
    final set = res.headers[HttpHeaders.setCookieHeader];
    if (set != null && set.isNotEmpty) _cookie = set.first.split(';').first;
    final json = res.headers.contentType?.mimeType == 'application/json';
    return (res.statusCode, json ? jsonDecode(text) : text);
  }

  void close() => _http.close(force: true);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    // The test binding otherwise answers every HttpClient with a canned 400.
    HttpOverrides.global = null;
    SharedPreferences.setMockInitialValues(const {});
    _setupPathProviderMock();
  });

  test('after a backend switch the running server uses the new story '
      'pipeline, not the disposed one', () async {
    final db = AppDatabase.forTesting();
    final storage = StorageService();
    await storage.initialized;
    final repo = StoryRepository(db);
    final memory = MemoryService(EmbeddingService(storage), storage, db);
    // KoboldCpp is the chat backend until the stored choice is read, so the
    // app's first pipeline is bound to it.
    final first = StoryPipelineService(
      repo,
      KoboldService(storage),
      memory,
      db,
    );
    final switched = StoryPipelineService(
      repo,
      OpenRouterService(),
      memory,
      db,
    );
    final host = WebServerHost(storage)
      ..setDatabase(db)
      ..setStoryRepository(repo)
      ..setStoryPipelineService(first);
    expect(await host.startSafely(0), isTrue);
    final client = _Client(host.port);
    addTearDown(() async {
      client.close();
      await host.stop();
      switched.dispose();
      await db.close();
    });

    final (setup, _) = await client.send('POST', '/api/auth/setup', {
      'username': 'porch',
      'password': 'porch-password',
    });
    expect(setup, 200);
    final (_, created) = await client.send('POST', '/api/stories', {
      'title': 'Porch Saga',
    });
    final id = (created! as Map)['id'] as String;
    final (_, project) = await client.send('GET', '/api/stories/$id');
    final (saved, _) = await client.send('POST', '/api/stories/$id', {
      ...(project! as Map),
      'director_plan': {
        'directive': 'Make Dov the one who put out the light.',
        'evaluation': 'One change.',
        'scope': 'local',
        'review': 'consistent',
        'actions': [
          {
            'type': 'MODIFY_STORY',
            'summary': 'Dov put out the light.',
            'enabled': true,
          },
        ],
      },
    });
    expect(saved, 200);

    // The switch, as main.providers.dart and Provider do it: the host is
    // given the new pipeline and the old one is disposed.
    host.setStoryPipelineService(switched);
    first.dispose();
    var told = 0;
    switched.addListener(() => told++);

    final (protect, _) = await client.send(
      'POST',
      '/api/stories/$id/director/protect',
      {'protect': false},
    );
    final (action, _) = await client.send(
      'POST',
      '/api/stories/$id/director/action',
      {'index': 0, 'enabled': false},
    );
    final (discard, _) = await client.send(
      'POST',
      '/api/stories/$id/director/discard',
    );
    expect([protect, action, discard], [200, 200, 200]);
    expect(
      told,
      3,
      reason: 'each change is told by the pipeline the app now uses',
    );
  });
}
