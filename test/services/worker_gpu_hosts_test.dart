// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/services/storage/settings/remote_api_key_vault.dart';
import 'package:http/http.dart' as http;

void main() {
  test(
    'oMLX unloads via /v1/models/{id}/unload then loads to restore',
    () async {
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
    },
  );

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

  test('LM Studio lists loaded instance_id then unloads it', () async {
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
        if (method == 'GET') {
          return http.Response(
            '{"models":[{"key":"qwen/qwen3","loaded_instances":'
            '[{"id":"qwen/qwen3@inst1"}]}]}',
            200,
          );
        }
        return http.Response('{"status":"loaded"}', 200);
      },
    );
    await host.unload();
    await host.restore();
    expect(hits, [
      'GET api/v1/models',
      'POST api/v1/models/unload',
      'POST api/v1/models/load',
    ]);
    expect(bodies[1], contains('"instance_id":"qwen/qwen3@inst1"'));
    expect(bodies[2], contains('"model":"qwen/qwen3"'));
  });

  test('LM Studio falls back to the model key when the list misses', () async {
    final bodies = <String?>[];
    final host = HttpGpuSwapHost(
      kind: LocalSwapKind.lmStudio,
      apiUrl: kLmStudioApiV1,
      modelId: 'qwen/qwen3',
      send: (method, uri, headers, body) async {
        bodies.add(body);
        if (method == 'GET') return http.Response('nope', 404);
        return http.Response('{"status":"ok"}', 200);
      },
    );
    await host.unload();
    expect(bodies[1], contains('"instance_id":"qwen/qwen3"'));
  });

  test('instanceIdFromLmStudioModels reads loaded_instances id', () {
    expect(
      instanceIdFromLmStudioModels(
        '{"models":[{"key":"qwen/qwen3","loaded_instances":'
            '[{"id":"qwen/qwen3@inst1"}]}]}',
        'qwen/qwen3',
      ),
      'qwen/qwen3@inst1',
    );
    expect(instanceIdFromLmStudioModels('{}', 'qwen/qwen3'), isNull);
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

  test('Kobold admin success still waits until the process is ready', () async {
    var readyWaits = 0;
    final host = KoboldProcessHost(
      baseUrl: 'http://127.0.0.1:5001',
      stopProcess: () async {},
      startProcess: () async {},
      waitUntilReady: () async => readyWaits++,
      admin: HttpGpuSwapHost(
        kind: LocalSwapKind.koboldProcess,
        apiUrl: 'http://127.0.0.1:5001',
        modelId: 'unused',
        send: (method, uri, headers, body) async {
          return http.Response('{"success":true}', 200);
        },
      ),
    );
    await host.unload();
    await host.restore();
    expect(readyWaits, 1);
  });

  test(
    'Kobold admin unload clears ready so restore-success wait is not a no-op',
    () async {
      var ready = true;
      var waitSawReady = true;
      final host = KoboldProcessHost(
        baseUrl: 'http://127.0.0.1:5001',
        stopProcess: () async {},
        startProcess: () async {},
        markNotReady: () => ready = false,
        waitUntilReady: () async {
          waitSawReady = ready;
        },
        admin: HttpGpuSwapHost(
          kind: LocalSwapKind.koboldProcess,
          apiUrl: 'http://127.0.0.1:5001',
          modelId: 'unused',
          send: (method, uri, headers, body) async {
            return http.Response('{"success":true}', 200);
          },
        ),
      );
      await host.unload();
      expect(ready, isFalse, reason: 'admin unload must force not-ready');
      await host.restore();
      expect(
        waitSawReady,
        isFalse,
        reason: 'waitUntilReady must not see a stale isReady after admin load',
      );
    },
  );

  test('oMLX load miss throws so occupancy cannot fake a restore', () async {
    final host = HttpGpuSwapHost(
      kind: LocalSwapKind.omlx,
      apiUrl: kOmlxApiV1,
      modelId: 'mlx-qwen',
      send: (method, uri, headers, body) async => http.Response('nope', 404),
    );
    await expectLater(host.restore(), throwsStateError);
  });

  test(
    'Kobold admin restore-fail while process is up force-restarts',
    () async {
      var running = true;
      var stops = 0;
      var starts = 0;
      var readyWaits = 0;
      final host = KoboldProcessHost(
        baseUrl: 'http://127.0.0.1:5001',
        stopProcess: () async {
          stops++;
          running = false;
        },
        startProcess: () async {
          starts++;
          running = true;
        },
        isProcessRunning: () => running,
        waitUntilReady: () async => readyWaits++,
        admin: HttpGpuSwapHost(
          kind: LocalSwapKind.koboldProcess,
          apiUrl: 'http://127.0.0.1:5001',
          modelId: 'unused',
          send: (method, uri, headers, body) async {
            if (body != null && body.contains('unload_model')) {
              return http.Response('{"success":true}', 200);
            }
            return http.Response('{"success":false}', 200);
          },
        ),
      );
      await host.unload();
      expect(stops, 0);
      expect(running, isTrue);
      await host.restore();
      expect(
        stops,
        1,
        reason: 'admin load miss must not no-op on a live process',
      );
      expect(starts, 1);
      expect(readyWaits, 1);
    },
  );

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
