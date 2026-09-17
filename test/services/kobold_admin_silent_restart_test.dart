// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:http/http.dart' as http;

HttpGpuSwapHost _admin(Future<http.Response> Function(String? body) send) {
  return HttpGpuSwapHost(
    kind: LocalSwapKind.koboldProcess,
    apiUrl: 'http://127.0.0.1:5001',
    modelId: '/tmp/worker.gguf',
    send: (method, uri, headers, body) => send(body),
  );
}

KoboldProcessHost _host({
  required HttpGpuSwapHost admin,
  required Future<void> Function() stopProcess,
  required Future<void> Function() startProcess,
}) {
  return KoboldProcessHost(
    baseUrl: 'http://127.0.0.1:5001',
    requestedModelPath: '/tmp/worker.gguf',
    requestedKcppsPath: '/tmp/worker.kcpps',
    adminRetryDelay: Duration.zero,
    stopProcess: stopProcess,
    startProcess: startProcess,
    admin: admin,
  );
}

void main() {
  test('prepare-worker restore uses admin without a prior unload', () async {
    final hits = <String>[];
    var starts = 0;
    var stops = 0;
    final host = _host(
      stopProcess: () async => stops++,
      startProcess: () async => starts++,
      admin: _admin((body) async {
        hits.add(body ?? '');
        return http.Response('{"success":true}', 200);
      }),
    );
    await host.restore();
    expect(
      hits.single,
      contains('"filename":"worker.gguf"'),
      reason: 'prepare-worker is restore-only — must still hit admin',
    );
    expect(starts, 0, reason: 'admin configured: no silent process restart');
    expect(stops, 0);
  });

  test('connection refused then admin 200 does not restart', () async {
    var refuses = 0;
    var starts = 0;
    final host = _host(
      stopProcess: () async {},
      startProcess: () async => starts++,
      admin: _admin((body) async {
        if (refuses < 2) {
          refuses++;
          throw Exception('Connection refused');
        }
        return http.Response('{"success":true}', 200);
      }),
    );
    await host.restore();
    expect(refuses, 2);
    expect(starts, 0);
  });

  test('persistent connection refused last-resorts after retries', () async {
    var starts = 0;
    var adminHits = 0;
    final host = _host(
      stopProcess: () async {},
      startProcess: () async => starts++,
      admin: _admin((body) async {
        adminHits++;
        throw Exception('Connection refused');
      }),
    );
    await host.restore();
    expect(adminHits, kKoboldAdminRetryAttempts);
    expect(starts, 1);
  });
}
