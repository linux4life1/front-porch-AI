// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/opencode/opencode.dart';
import 'package:front_porch_ai/services/waifu/waifu.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:path/path.dart' as p;

/// The mode, scope and tools switches must change what OpenCode does, not
/// only what the sidebar shows.
void main() {
  late Directory root;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('waifu_honest_');
  });

  tearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });

  const backend = OpenCodePorchBackend(
    baseUrl: 'http://127.0.0.1:5001/v1',
    apiKey: 'x',
    modelId: 'local',
  );

  group('a scope change reaches the serve and keeps the session', () {
    late HttpServer serve;
    late List<String> hits;
    late OpenCodeManager manager;
    late int spawns;
    late WaifuSession session;

    setUp(() async {
      // The test binding swaps in an HttpClient that answers 400; this group
      // talks to a real socket.
      HttpOverrides.global = null;
      hits = [];
      spawns = 0;
      // Plays the OpenCode HTTP API on a real loopback socket.
      serve = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      serve.listen((req) async {
        hits.add('${req.method} ${req.uri.path}');
        await utf8.decoder.bind(req).join();
        req.response.headers.contentType = ContentType.json;
        if (req.method == 'POST' && req.uri.path == '/session') {
          req.response.write(jsonEncode({'id': 'ses_1', 'title': 'Mira'}));
        } else if (req.uri.path == '/session/ses_1') {
          req.response.write(jsonEncode({'id': 'ses_1', 'title': 'Mira'}));
        } else {
          req.response.statusCode = 404;
        }
        await req.response.close();
      });
      final closetRoot = p.join(root.path, 'closet');
      final closet = OpenCodeCloset(closetRoot);
      await closet.ensureLayout();
      await File(closet.binaryPath).writeAsString('BIN');
      manager = OpenCodeManager(
        rootPath: closetRoot,
        remoteLookup: () async => null,
        pickPort: () async => serve.port,
        healthGet: (base) async => (healthy: true, version: '1.18.30'),
        spawn: (req) async {
          spawns++;
          return OpenCodeProcessHandle.fake(pid: spawns);
        },
      );
      session = WaifuSession(
        folderRoot: p.join(root.path, 'porch'),
        coworker: CharacterCard(name: 'Mira'),
      );
      await Directory(session.folderRoot).create();
    });

    tearDown(() async {
      await manager.stop();
      await serve.close(force: true);
    });

    Future<Map<String, dynamic>> config() async =>
        jsonDecode(await File(manager.closet.configFilePath).readAsString())
            as Map<String, dynamic>;

    test('Jail to Disk restarts the serve and resumes the session', () async {
      final seat = WaifuOpenCodeSeat(
        session: session,
        manager: manager,
        backend: backend,
      );
      expect(await seat.ensure(), isNotNull);
      expect(seat.sessionId, 'ses_1');
      expect(spawns, 1);
      expect((await config())['permission']['external_directory'], 'deny');

      await seat.ensure();
      expect(spawns, 1, reason: 'nothing changed, nothing restarts');

      session.pathMode = WaifuPathMode.wholeDisk;
      expect(seat.needsReseat, isTrue);
      await seat.ensure();
      expect(spawns, 2);
      expect(seat.sessionId, 'ses_1');
      expect(hits.where((h) => h == 'POST /session'), hasLength(1));
      expect(hits, contains('GET /session/ses_1'));
      final cfg = await config();
      expect(cfg['permission']['external_directory'], 'ask');
      expect(cfg['agent']['waifu']['prompt'], contains('elsewhere'));
    });

    test('library tools need a restart; Plan, Build and Yolo do not', () async {
      final seat = WaifuOpenCodeSeat(
        session: session,
        manager: manager,
        backend: backend,
      );
      await seat.ensure();
      session.mode = WaifuMode.yolo;
      expect(seat.needsReseat, isFalse);
      session.mode = WaifuMode.plan;
      expect(seat.needsReseat, isFalse);
      session.mcpOptIn = true;
      expect(seat.needsReseat, isTrue);
    });
  });

  test(
    'Plan cannot edit or run commands; Build asks; Yolo is not baked in',
    () {
      final closet = OpenCodeCloset(root.path);
      Map<String, dynamic> agent(WaifuMode mode, String name) =>
          (buildWaifuOpenCodeConfigMap(
                    closet: closet,
                    coworker: CharacterCard(name: 'Mira'),
                    backend: backend,
                    pathMode: WaifuPathMode.folderJail,
                    mode: mode,
                  )['agent']
                  as Map)[name]
              as Map<String, dynamic>;

      final plan = agent(WaifuMode.plan, 'plan');
      expect(plan['permission']['edit'], 'deny');
      expect(plan['permission']['bash'], 'deny');
      expect(plan['permission']['task'], 'deny');
      expect(plan['permission']['read'], 'ask');
      expect(plan['prompt'], contains('Plan mode'));
      expect(plan['prompt'], isNot(contains('keep calling write')));

      final build = agent(WaifuMode.yolo, 'waifu');
      expect(build['permission']['edit'], 'ask');
      expect(build['permission']['bash']['rm -fr *'], 'deny');
      expect(build['prompt'], contains('Stay inside the project folder'));
    },
  );

  test('Yolo answers asks in Dart, so a switch lands mid-session', () async {
    final hits = <http.Request>[];
    final asked = <String>[];
    final session = WaifuSession(
      folderRoot: root.path,
      coworker: CharacterCard(name: 'Mira'),
      mode: WaifuMode.yolo,
    );
    final harness = WaifuHarness(
      session: session,
      sessionId: 'ses_1',
      client: OpenCodeClient(
        baseUri: Uri.parse('http://127.0.0.1:4096'),
        directory: root.path,
        clientFactory: () => MockClient((req) async {
          hits.add(req);
          return http.Response('true', 200);
        }),
      ),
      onAsk: (req) async {
        asked.add(req.toolName);
        return WaifuAskDecision.deny;
      },
    );
    Future<String> ask(String id) async {
      dispatchOpenCodeEvent(
        openCodeEventFromJson({
          'type': 'permission.asked',
          'properties': {
            'id': id,
            'sessionID': 'ses_1',
            'permission': 'edit',
            'patterns': ['a.txt'],
          },
        })!,
        harness,
      );
      await pumpEventQueue();
      final reply = hits.lastWhere((r) => r.url.path.contains(id));
      return jsonDecode(reply.body)['response'] as String;
    }

    expect(await ask('per_1'), 'once');
    expect(asked, isEmpty);
    harness.applyMode(WaifuMode.build);
    expect(await ask('per_2'), 'reject');
    expect(asked, ['edit']);
  });

  test('a model without tool calls cannot start a turn', () async {
    final session = WaifuSession(
      folderRoot: root.path,
      coworker: CharacterCard(name: 'Mira'),
    )..toolsSupported = false;
    final harness = WaifuHarness(session: session);
    await harness.send('build it');
    expect(session.running, isFalse);
    final last = session.transcript.last;
    expect(last.kind, WaifuMsgKind.stage);
    expect(last.detail, kWaifuToolsUnsupported);
  });

  test('safety copy names only stops that exist', () {
    for (final mode in WaifuPathMode.values) {
      final text = '${waifuYoloWarning(mode)} ${waifuHonestyBody(mode)}';
      expect(text, isNot(contains('hard stops stay awake')));
      expect(text, contains('nothing guards secret files'));
    }
  });

  group('the project store', () {
    test('forget removes the last-open copy too', () async {
      final store = WaifuStore(p.join(root.path, 'store'));
      final folder = p.join(root.path, 'porch');
      await store.saveLast(
        WaifuSession(
          folderRoot: folder,
          coworker: CharacterCard(name: 'M'),
        ),
      );
      await store.forgetProject(folder);
      expect(await store.loadSession(folder), isNull);
      expect(await store.loadPorchConsent(folder), isNull);
      expect(await store.loadLast(), isNull);
    });

    test('Chat Settings survive save and load', () async {
      final store = WaifuStore(p.join(root.path, 'store'));
      final folder = p.join(root.path, 'porch');
      final session = WaifuSession(
        folderRoot: folder,
        coworker: CharacterCard(name: 'M'),
      )..genSettings = (ChatGenerationSettings()..contextSize = 32768);
      await store.saveLast(session);
      final back = await store.loadSession(folder);
      expect(back!.genSettings.contextSize, 32768);
    });
  });
}
