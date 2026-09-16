// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/services/storage/settings/remote_api_key_vault.dart';
import 'package:http/http.dart' as http;

void main() {
  test('oMLX unloads via /v1/models/{id}/unload then loads to restore', () async {
    final hits = <String>[];
    final host = HttpGpuSwapHost(
      kind: LocalSwapKind.omlx,
      apiUrl: kOmlxApiV1,
      modelId: 'mlx-qwen',
      apiKey: 'omlx-key',
      send: (method, uri, headers, body) async {
        hits.add('$method ${uri.pathSegments.join('/')}');
        expect(headers['Authorization'], 'Bearer omlx-key');
        return http.Response('{"status":"ok"}', 200);
      },
    );
    await host.unload();
    await host.restore();
    expect(hits, [
      'POST v1/models/mlx-qwen/unload',
      'POST v1/models/mlx-qwen/load',
    ]);
  });

  test('oMLX falls back to the admin twin when v1 unload misses', () async {
    final hits = <String>[];
    final host = HttpGpuSwapHost(
      kind: LocalSwapKind.omlx,
      apiUrl: kOmlxApiV1,
      modelId: 'org/model',
      send: (method, uri, headers, body) async {
        hits.add('$method ${uri.pathSegments.join('/')}');
        if (uri.pathSegments.contains('v1')) {
          return http.Response('nope', 404);
        }
        return http.Response('{"status":"ok"}', 200);
      },
    );
    await host.unload();
    expect(hits.last, 'POST admin/api/models/org/model/unload');
  });

  test('LM Studio uses /api/v1/models/unload then /load', () async {
    final hits = <String>[];
    final bodies = <String?>[];
    final host = HttpGpuSwapHost(
      kind: LocalSwapKind.lmStudio,
      apiUrl: kLmStudioApiV1,
      modelId: 'qwen/qwen3',
      apiKey: 'lms-token',
      send: (method, uri, headers, body) async {
        hits.add('$method ${uri.pathSegments.join('/')}');
        bodies.add(body);
        expect(headers['Authorization'], 'Bearer lms-token');
        return http.Response('{"status":"loaded"}', 200);
      },
    );
    await host.unload();
    await host.restore();
    expect(hits, ['POST api/v1/models/unload', 'POST api/v1/models/load']);
    expect(bodies[0], contains('instance_id'));
    expect(bodies[1], contains('"model":"qwen/qwen3"'));
  });

  test('Kobold process uses admin reload_config when it succeeds', () async {
    final hits = <String>[];
    var stops = 0;
    var starts = 0;
    final host = KoboldProcessHost(
      baseUrl: 'http://127.0.0.1:5001',
      stopProcess: () async => stops++,
      startProcess: () async => starts++,
      admin: HttpGpuSwapHost(
        kind: LocalSwapKind.koboldProcess,
        apiUrl: 'http://127.0.0.1:5001',
        modelId: 'unused',
        send: (method, uri, headers, body) async {
          hits.add('$method ${uri.pathSegments.join('/')} $body');
          return http.Response('{"success":true}', 200);
        },
      ),
    );
    await host.unload();
    await host.restore();
    expect(hits, [
      'POST api/admin/reload_config {"filename":"unload_model"}',
      'POST api/admin/reload_config {"filename":"initial_model"}',
    ]);
    expect(stops, 0);
    expect(starts, 0);
  });

  test('Kobold process stop/start is the lever when admin is off', () async {
    var stops = 0;
    var starts = 0;
    final host = KoboldProcessHost(
      baseUrl: 'http://127.0.0.1:5001',
      stopProcess: () async => stops++,
      startProcess: () async => starts++,
      admin: HttpGpuSwapHost(
        kind: LocalSwapKind.koboldProcess,
        apiUrl: 'http://127.0.0.1:5001',
        modelId: 'unused',
        send: (method, uri, headers, body) async {
          return http.Response('{"success":false}', 200);
        },
      ),
    );
    await host.unload();
    expect(stops, 1);
    await host.restore();
    expect(starts, 1);
  });
}
