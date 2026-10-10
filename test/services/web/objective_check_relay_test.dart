// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The phone's goal-check overlay, through the app's own web server. A real
// ChatService sends a turn to a loopback backend that holds the goal-check
// request open. While it is held the server must push `processing` with
// `objective: true` (the phone's overlay and its Skip button read only that
// event), the polled chat state must say a check is running, and the phone's
// Skip must call it off: the reply lands, the quest stays, and a final
// `processing {active: false}` dismisses the overlay. Realism is off, so the
// goal check is the only thing that can raise the overlay.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/services/web/web_server_host.dart';

import '../../../integration_test/support/fake_backend.dart';
import '../../helpers/chat_db_teardown.dart';

void _setupPathProviderMock() {
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (MethodCall call) async {
        if (call.method == 'getApplicationDocumentsDirectory') {
          return Directory.systemTemp.createTempSync('fpai_goal_relay_').path;
        }
        return null;
      });
}

/// No engine on disk and no download: this test never starts KoboldCpp.
class _QuietBackend extends BackendManager {
  _QuietBackend(super.storage);

  @override
  String? get backendPath => '/tmp/fake-koboldcpp';

  @override
  Future<void> checkBackendAvailability() async {}

  @override
  Future<void> ensureEngineInstalled() async {}
}

class _Client {
  _Client(this.port);

  final int port;
  final _http = HttpClient();
  String? cookie;

  Future<(int, Object?)> send(
    String method,
    String path, [
    Object? body,
  ]) async {
    final req = await _http.open(method, '127.0.0.1', port, path);
    if (cookie case final c?) req.headers.set(HttpHeaders.cookieHeader, c);
    if (body != null) {
      req.headers.contentType = ContentType.json;
      req.write(jsonEncode(body));
    }
    final res = await req.close();
    final text = await res.transform(utf8.decoder).join();
    final set = res.headers[HttpHeaders.setCookieHeader];
    if (set != null && set.isNotEmpty) cookie = set.first.split(';').first;
    return (res.statusCode, text.isEmpty ? null : jsonDecode(text));
  }

  void close() => _http.close(force: true);
}

Future<void> _until(bool Function() done, String what) async {
  final deadline = DateTime.now().add(const Duration(seconds: 10));
  while (!done()) {
    if (DateTime.now().isAfter(deadline)) fail('timed out waiting for $what');
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  _setupPathProviderMock();

  test('the goal check raises the phone overlay over the relay, and the '
      "phone's Skip ends it with the reply landing", () async {
    HttpOverrides.global = null;
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({
      'update_auto_check': false,
      'backend_type': 'openRouter',
      'realism_default': false,
      'pockets_enabled': false,
      'journal_enabled': false,
      // Text evals, so the check asks no tool question. This fake refuses
      // tools, and the probe's "inconclusive" notify would raise the overlay
      // by accident; a real backend whose tool answer is already known (or
      // which answers tools) sends no such notify, as the live capture saw.
      'prefer_text_evals': true,
    });
    final backend = await FakeBackendServer.start(
      replyPieces: ['The lemonade is ', 'still cold.'],
    );
    final hold = Completer<void>();
    backend
      ..objectiveCheckVerdict = '1: YES'
      ..holdObjectiveCheck = hold;

    final db = AppDatabase.forTesting(sameIsolate: true);
    final storage = StorageService();
    await storage.initialized;
    final kobold = KoboldService(storage);
    final provider = LLMProvider(
      kobold,
      OpenRouterService(apiUrl: '', apiKey: '', modelName: ''),
      storage,
      _QuietBackend(storage),
    );
    final characters = CharacterRepository(db, storage);
    final chat =
        ChatService(
            kobold,
            UserPersonaService(db),
            storage,
            WorldRepository(storage, db),
          )
          ..setDatabase(db)
          ..setCharacterRepository(characters)
          ..setLLMProvider(provider)
          ..testLlmServiceOverride = OpenRouterService(
            apiUrl: '${backend.baseUrl}/v1',
            modelName: 'smoke-model',
          );
    final host = WebServerHost(storage)
      ..setDatabase(db)
      ..setChatService(chat)
      ..setCharacterRepository(characters);
    expect(await host.startSafely(0), isTrue);
    final client = _Client(host.port);
    final (signedUp, _) = await client.send('POST', '/api/auth/setup', {
      'username': 'porch',
      'password': 'porch-password',
    });
    expect(signedUp, 200);
    final processing = <Map<String, dynamic>>[];
    final ws = await WebSocket.connect(
      'ws://127.0.0.1:${host.port}/api/ws',
      headers: {HttpHeaders.cookieHeader: client.cookie!},
    );
    ws.listen((m) {
      final e = jsonDecode(m as String) as Map<String, dynamic>;
      if (e['event'] == 'processing') processing.add(e);
    });
    addTearDown(() async {
      if (!hold.isCompleted) hold.complete();
      await ws.close();
      client.close();
      await host.stop();
      await disposeChatThenCloseDb(chat, db);
      provider.dispose();
      await backend.close();
    });

    await chat.setActiveCharacter(
      CharacterCard(
        name: 'Jennifer',
        description: 'Exists only inside the goal-check relay test.',
        firstMessage: 'Welcome to the porch.',
        frontPorchExtensions: FrontPorchExtensions(
          realismEnabled: false,
          needsSimEnabled: false,
          chaosModeEnabled: false,
        ),
      )..dbId = 'char-goal-relay',
    );
    await chat.setObjective('Share porch lemonade before sunset');
    await chat.updateCheckFrequency(chat.activeObjectives.single, 1);
    final quest = chat.activeObjectives.single;

    final sent = chat.sendMessage('Want some lemonade?');
    await backend.objectiveCheckHeld.future.timeout(
      const Duration(seconds: 10),
    );
    await _until(
      () => processing.any((e) => e['active'] == true),
      'a processing event while the goal check is held',
    );
    expect(processing.first, containsPair('objective', true));
    expect(processing.first, containsPair('realism', false));
    final (_, state) = await client.send('GET', '/api/chat/state');
    expect((state! as Map)['isCheckingCompletion'], isTrue);

    final (skipped, _) = await client.send(
      'POST',
      '/api/chat/skip-objective-check',
    );
    expect(skipped, 200);
    await sent.timeout(const Duration(seconds: 10));
    await _until(
      () => processing.last['active'] == false,
      'the processing event that dismisses the overlay',
    );

    expect(chat.isCheckingCompletion, isFalse);
    expect(chat.messages.last.displayText, 'The lemonade is still cold.');
    expect(chat.activeObjectives.map((o) => o.id), [
      quest.id,
    ], reason: 'the held check would have answered YES and retired the quest');
    final (_, after) = await client.send('GET', '/api/chat/state');
    expect((after! as Map)['isCheckingCompletion'], isFalse);
  }, timeout: const Timeout(Duration(seconds: 60)));
}
