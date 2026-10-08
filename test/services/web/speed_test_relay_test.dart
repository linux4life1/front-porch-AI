// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

// The phone's speed test, through the app's own web server: the question it
// asks first, start, Cancel, the progress over the stream hub, the card's
// state and its one line, and a chat message refused while it runs. The
// server is the real one (sign-in, routes, facades, hub) over the app's real
// provider and KoboldCpp service, on the loopback KoboldCpp of
// speed_test_rig.dart.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/services/web/web_server_host.dart';
import 'package:front_porch_ai/utils/utils.dart';

import '../../golden/support/fakes_services.dart';
import '../../helpers/chat_db_teardown.dart';
import '../kobold/speed_test_rig.dart';

class _Models extends FakeModelManager {
  @override
  Future<GGUFModelInfo?> getModelArchitectureInfo(String filePath) =>
      GGUFParser.getModelArchitectureInfo(filePath);
}

class _Hardware extends FakeHardwareService {
  _Hardware()
    : super(
        hardwareInfo: HardwareInfo(
          gpuName: SpeedTestRig.card,
          vramMb: 24564,
          ramMb: 65536,
          vendor: 'Nvidia',
          hasCuda: true,
        ),
      );

  @override
  FreeMemoryMb? get freeBeforeEngine => (graphics: 23000, system: 60000);

  @override
  set freeBeforeEngine(FreeMemoryMb? value) {}
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

({double read, double write}) _speeds(Map<String, dynamic> c) =>
    (read: kcppsBatchOf(c).physical >= 2048 ? 1600.0 : 1000.0, write: 200.0);

void main() {
  late Directory root;
  late SpeedTestRig rig;
  late WebServerHost host;
  late _Client client;
  late List<Map<String, dynamic>> events;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('fpai speed test relay');
    rig = await SpeedTestRig.start(root, _speeds);
    final db = AppDatabase.forTesting();
    final chat =
        ChatService(
            rig.kobold,
            UserPersonaService(db),
            rig.storage,
            WorldRepository(rig.storage, db),
          )
          ..setDatabase(db)
          ..setCharacterRepository(CharacterRepository(db, rig.storage))
          ..setLLMProvider(rig.llm);
    host = WebServerHost(rig.storage)
      ..setDatabase(db)
      ..setChatService(chat)
      ..setCharacterRepository(CharacterRepository(db, rig.storage))
      ..setLlmProvider(rig.llm)
      ..setKoboldService(rig.kobold)
      ..setModelManager(_Models())
      ..setHardwareService(_Hardware());
    expect(await host.startSafely(0), isTrue);
    client = _Client(host.port);
    final (signedUp, _) = await client.send('POST', '/api/auth/setup', {
      'username': 'porch',
      'password': 'porch-password',
    });
    expect(signedUp, 200);
    events = [];
    final ws = await WebSocket.connect(
      'ws://127.0.0.1:${host.port}/api/ws',
      headers: {HttpHeaders.cookieHeader: client.cookie!},
    );
    ws.listen((m) {
      final e = jsonDecode(m as String) as Map<String, dynamic>;
      if (e['event'] == 'speed_test') events.add(e);
    });
    addTearDown(() async {
      await ws.close();
      client.close();
      await host.stop();
      await disposeChatThenCloseDb(chat, db);
      await rig.close();
      await root.delete(recursive: true);
    });
  });

  Future<Map<String, dynamic>> card() async {
    final (status, body) = await client.send('GET', '/api/backend/local-model');
    expect(status, 200);
    return (body! as Map).cast<String, dynamic>();
  }

  test('the phone asks, starts, follows and ends the test the desktop runs, '
      'and the card says how it ended', () async {
    expect((await card())['speedTest']['unavailable'], isNull);
    final (_, asked) = await client.send(
      'GET',
      '/api/backend/local-model/speed-test',
    );
    expect((asked! as Map)['refused'], isNull);
    expect((asked as Map)['ask'], startsWith('This takes '));

    final (status, started) = await client.send(
      'POST',
      '/api/backend/local-model/speed-test',
    );
    expect(status, 200);
    expect((started! as Map)['started'], isTrue);
    await rig.finished();
    await Future<void>.delayed(const Duration(milliseconds: 100));

    final states = [for (final e in events) e['speedTest']['state']];
    expect(states, contains('running'));
    expect(states.last, 'done');
    expect(
      events.any((e) => e['speedTest']['steps'] == rig.test.steps),
      isTrue,
      reason: 'the step count reaches the phone',
    );
    final test = (await card())['speedTest'] as Map;
    expect(test['state'], 'done');
    expect(
      test['line'],
      matches(RegExp(r'^Replies now come about \d+% sooner\.$')),
    );
    expect(jsonEncode(test), isNot(contains('MMQ')));
  });

  test('Cancel from the phone stops it, and nothing is saved', () async {
    rig.engine.beforeTiming = (n) async {
      if (n == 1) {
        final (status, _) = await client.send(
          'POST',
          '/api/backend/local-model/speed-test/cancel',
        );
        expect(status, 200);
      }
    };
    await client.send('POST', '/api/backend/local-model/speed-test');
    await rig.finished();
    final test = (await card())['speedTest'] as Map;
    expect(test['state'], 'stopped');
    expect(test['line'], 'Stopped. Your settings were not changed.');
    expect(rig.storage.presetSettings.modelPresetMap[rig.model], isNull);
  });

  test("a chat message from the phone is refused while it runs, with the "
      "desktop's words", () async {
    final holding = Completer<void>();
    final release = Completer<void>();
    rig.engine.beforeTiming = (n) async {
      if (n != 1) return;
      holding.complete();
      await release.future;
    };
    await client.send('POST', '/api/backend/local-model/speed-test');
    await holding.future;
    final (status, body) = await client.send('POST', '/api/chat/send', {
      'text': 'Are you still there?',
    });
    expect(status, 400);
    expect(jsonEncode(body), contains('Testing speed settings, '));
    final (_, refused) = await client.send(
      'POST',
      '/api/backend/local-model/speed-test',
    );
    expect((refused! as Map)['started'], isFalse);
    release.complete();
    await rig.finished();
  });
}
