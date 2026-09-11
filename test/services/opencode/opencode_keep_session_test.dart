// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/services/waifu/waifu.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test(
    'promptAsync names the porch model so a swap can reuse the session',
    () async {
      final hits = <http.Request>[];
      final client = OpenCodeClient(
        baseUri: Uri.parse('http://127.0.0.1:4096'),
        directory: '/tmp/porch',
        clientFactory: () => MockClient((req) async {
          hits.add(req);
          return http.Response('', 204);
        }),
      );
      await client.promptAsync(
        sessionId: 'ses_keep',
        parts: [
          {'type': 'text', 'text': 'keep going'},
        ],
        agent: 'waifu',
        providerID: kOpenCodePorchProvider,
        modelID: kOpenCodePorchModelSlot,
      );
      expect(hits.single.url.path, '/session/ses_keep/prompt_async');
      final body = jsonDecode(hits.single.body) as Map;
      expect(body['model']['providerID'], kOpenCodePorchProvider);
      expect(body['model']['modelID'], kOpenCodePorchModelSlot);
      expect(body['parts'][0]['text'], 'keep going');
    },
  );

  test(
    'patchConfig updates the live serve without creating a session',
    () async {
      final hits = <http.Request>[];
      final client = OpenCodeClient(
        baseUri: Uri.parse('http://127.0.0.1:4096'),
        directory: '/tmp/porch',
        clientFactory: () => MockClient((req) async {
          hits.add(req);
          return http.Response('{}', 200);
        }),
      );
      await client.patchConfig({
        'model': 'porch/current',
        'provider': {
          'porch': {
            'options': {'baseURL': 'http://localhost:8000/v1'},
          },
        },
      });
      expect(hits.single.method, 'PATCH');
      expect(hits.single.url.path, '/config');
      expect(hits.any((r) => r.url.path == '/session'), isFalse);
    },
  );

  test(
    'retarget rewrites config in place and does not POST /session',
    () async {
      final dir = await Directory.systemTemp.createTemp('waifu_retarget_');
      addTearDown(() async {
        if (await dir.exists()) await dir.delete(recursive: true);
      });
      final hits = <http.Request>[];
      final client = OpenCodeClient(
        baseUri: Uri.parse('http://127.0.0.1:4096'),
        directory: dir.path,
        clientFactory: () => MockClient((req) async {
          hits.add(req);
          return http.Response('{}', 200);
        }),
      );
      await waifuRetargetOpenCode(
        closet: OpenCodeCloset(dir.path),
        client: client,
        coworker: CharacterCard(name: 'Mira'),
        pathMode: WaifuPathMode.folderJail,
        mode: WaifuMode.build,
        backend: const OpenCodePorchBackend(
          baseUrl: 'http://localhost:8000/v1',
          apiKey: 'x',
          modelId: 'mlx-community/Qwen',
        ),
      );
      expect(
        hits.any((r) => r.method == 'POST' && r.url.path == '/session'),
        isFalse,
      );
      expect(
        hits.any((r) => r.method == 'PATCH' && r.url.path == '/config'),
        isTrue,
      );
      final raw = await File(
        OpenCodeCloset(dir.path).configFilePath,
      ).readAsString();
      expect(raw, contains('localhost:8000'));
      expect(raw, contains('mlx-community/Qwen'));
    },
  );
}
