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
  bool Function()? isProcessRunning,
  Duration retryDelay = Duration.zero,
  KoboldAdminSwapLock? swapLock,
  String model = '/tmp/worker.gguf',
}) {
  return KoboldProcessHost(
    baseUrl: 'http://127.0.0.1:5001',
    requestedModelPath: model,
    requestedKcppsPath: '/tmp/worker.kcpps',
    adminRetryDelay: retryDelay,
    isProcessRunning: isProcessRunning,
    swapLock: swapLock,
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

  test(
    'two sequential unload-restore cycles do not start the process',
    () async {
      var starts = 0;
      var stops = 0;
      final host = _host(
        isProcessRunning: () => true,
        stopProcess: () async => stops++,
        startProcess: () async => starts++,
        admin: _admin((body) async => http.Response('{"success":true}', 200)),
      );
      await host.unload();
      await host.restore();
      await host.unload();
      await host.restore();
      expect(starts, 0);
      expect(stops, 0);
    },
  );

  test('unload refuse while process is up does not stop the process', () async {
    var stops = 0;
    var starts = 0;
    final host = _host(
      isProcessRunning: () => true,
      stopProcess: () async => stops++,
      startProcess: () async => starts++,
      admin: _admin((body) async {
        throw Exception('Connection refused');
      }),
    );
    await host.unload();
    expect(stops, 0, reason: 'live process must not die on a transient blip');
    expect(starts, 0);
  });

  test(
    'restore refuse while process is up does not last-resort restart',
    () async {
      var starts = 0;
      var stops = 0;
      final host = _host(
        isProcessRunning: () => true,
        stopProcess: () async => stops++,
        startProcess: () async => starts++,
        admin: _admin((body) async {
          throw Exception('Connection refused');
        }),
      );
      await expectLater(host.restore(), throwsA(isA<Exception>()));
      expect(starts, 0, reason: 'live process: wait/retry, do not restart');
      expect(stops, 0);
    },
  );

  test(
    'refuses longer than 1s recover without restart while process is up',
    () async {
      final began = DateTime.now();
      var starts = 0;
      var stops = 0;
      final host = _host(
        isProcessRunning: () => true,
        retryDelay: const Duration(milliseconds: 250),
        stopProcess: () async => stops++,
        startProcess: () async => starts++,
        admin: _admin((body) async {
          if (DateTime.now().difference(began) <
              const Duration(milliseconds: 1100)) {
            throw Exception('Connection refused');
          }
          return http.Response('{"success":true}', 200);
        }),
      );
      await host.unload();
      await host.restore();
      expect(
        DateTime.now().difference(began) >= const Duration(seconds: 1),
        isTrue,
      );
      expect(starts, 0);
      expect(stops, 0);
    },
  );

  test('shared lock finishes restore before the next unload starts', () async {
    final lock = KoboldAdminSwapLock();
    var restoreOpen = false;
    var unloadSawRestore = false;
    final mouth = _host(
      swapLock: lock,
      isProcessRunning: () => true,
      model: '/tmp/mouth.gguf',
      stopProcess: () async {},
      startProcess: () async {},
      admin: _admin((body) async {
        if (body != null && body.contains('unload_model')) {
          if (restoreOpen) unloadSawRestore = true;
          return http.Response('{"success":true}', 200);
        }
        restoreOpen = true;
        await Future<void>.delayed(const Duration(milliseconds: 40));
        restoreOpen = false;
        return http.Response('{"success":true}', 200);
      }),
    );
    final restore = mouth.restore();
    final unload = mouth.unload();
    await Future.wait([restore, unload]);
    expect(unloadSawRestore, isFalse);
  });

  test('two occupancy cycles share admin and do not restart', () async {
    var starts = 0;
    final lock = KoboldAdminSwapLock();
    KoboldProcessHost lane(String model) => _host(
      model: model,
      swapLock: lock,
      isProcessRunning: () => true,
      stopProcess: () async {},
      startProcess: () async => starts++,
      admin: _admin((body) async => http.Response('{"success":true}', 200)),
    );
    final occ = GpuSwapOccupancy(
      mouth: lane('/tmp/mouth.gguf'),
      worker: lane('/tmp/worker.gguf'),
    );
    await occ.hold(() async {});
    await occ.ensureMouth();
    await occ.hold(() async {});
    await occ.ensureMouth();
    expect(starts, 0);
    expect(occ.steps.where((s) => s.startsWith('unload-mouth')).length, 2);
  });
}
