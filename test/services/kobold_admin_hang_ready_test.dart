// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/services/chat/chat.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:http/http.dart' as http;

void main() {
  test('admin reload_config hang times out and does not restart', () async {
    var starts = 0;
    var stops = 0;
    final admin = HttpGpuSwapHost(
      kind: LocalSwapKind.koboldProcess,
      apiUrl: 'http://127.0.0.1:5001',
      modelId: '/tmp/worker.gguf',
      adminHttpTimeout: const Duration(milliseconds: 30),
      send: (method, uri, headers, body) => Completer<http.Response>().future,
    );
    final host = KoboldProcessHost(
      baseUrl: 'http://127.0.0.1:5001',
      requestedModelPath: '/tmp/worker.gguf',
      requestedKcppsPath: '/tmp/worker.kcpps',
      adminRetryAttempts: 3,
      adminRetryDelay: Duration.zero,
      isProcessRunning: () => true,
      stopProcess: () async => stops++,
      startProcess: () async => starts++,
      waitUntilReady: () async => fail('gen-ready must not run during hang'),
      admin: admin,
    );
    await expectLater(
      host.restore(),
      throwsA(
        isA<TimeoutException>().having(
          (e) => e.toString(),
          'message',
          contains('reload_config'),
        ),
      ),
    );
    expect(starts, 0, reason: 'admin hang is not a process restart');
    expect(stops, 0);
    expect(
      friendlyGenerationError(
        TimeoutException('Kobold admin reload_config timed out').toString(),
      ),
      contains('Chat speech was put back'),
    );
  });

  test('admin unload hang times out and does not report success', () async {
    var starts = 0;
    var stops = 0;
    final admin = HttpGpuSwapHost(
      kind: LocalSwapKind.koboldProcess,
      apiUrl: 'http://127.0.0.1:5001',
      modelId: '/tmp/mouth.gguf',
      adminHttpTimeout: const Duration(milliseconds: 30),
      send: (method, uri, headers, body) => Completer<http.Response>().future,
    );
    final host = KoboldProcessHost(
      baseUrl: 'http://127.0.0.1:5001',
      requestedModelPath: '/tmp/mouth.gguf',
      requestedKcppsPath: '/tmp/mouth.kcpps',
      adminRetryAttempts: 3,
      adminRetryDelay: Duration.zero,
      isProcessRunning: () => true,
      stopProcess: () async => stops++,
      startProcess: () async => starts++,
      admin: admin,
    );
    await expectLater(
      host.unload(),
      throwsA(
        isA<TimeoutException>().having(
          (e) => e.toString(),
          'message',
          contains('reload_config'),
        ),
      ),
    );
    expect(starts, 0, reason: 'unload timeout is not a process restart');
    expect(stops, 0);
  });

  test('unload timeout does not prepare-worker as if mouth is gone', () async {
    var starts = 0;
    var stops = 0;
    final admin = HttpGpuSwapHost(
      kind: LocalSwapKind.koboldProcess,
      apiUrl: 'http://127.0.0.1:5001',
      modelId: '/tmp/mouth.gguf',
      adminHttpTimeout: const Duration(milliseconds: 30),
      send: (method, uri, headers, body) => Completer<http.Response>().future,
    );
    final mouth = KoboldProcessHost(
      baseUrl: 'http://127.0.0.1:5001',
      requestedModelPath: '/tmp/mouth.gguf',
      requestedKcppsPath: '/tmp/mouth.kcpps',
      adminRetryAttempts: 3,
      adminRetryDelay: Duration.zero,
      isProcessRunning: () => true,
      stopProcess: () async => stops++,
      startProcess: () async => starts++,
      admin: admin,
    );
    final occ = GpuSwapOccupancy(mouth: mouth, worker: _RecHost('worker'));
    await expectLater(occ.hold(() async {}), throwsA(isA<TimeoutException>()));
    expect(
      occ.steps.where((s) => s.startsWith('prepare-worker')),
      isEmpty,
      reason: 'unload timeout must not proceed as a successful mouth drop',
    );
    expect(occ.steps.first, startsWith('unload-mouth:'));
    expect(occ.steps, contains('restore-mouth:${mouth.label}'));
    expect(occ.mouthDown, isFalse);
    expect(occ.isHeld, isFalse);
    expect(starts, 0);
    expect(stops, 0);
    expect(
      friendlyGenerationError(
        TimeoutException('Kobold admin reload_config timed out').toString(),
      ),
      contains('Chat speech was put back'),
    );
  });

  test(
    'prepare-worker hang restores mouth and does not leave it down',
    () async {
      final occ = GpuSwapOccupancy(
        mouth: _RecHost('mouth'),
        worker: _HangRestoreHost(),
      );
      await expectLater(
        occ.hold(() async {}),
        throwsA(isA<TimeoutException>()),
      );
      expect(occ.steps.first, 'unload-mouth:mouth');
      expect(occ.steps, contains('prepare-worker:worker'));
      expect(occ.steps.last, 'restore-mouth:mouth');
      expect(occ.mouthDown, isFalse);
      expect(occ.isHeld, isFalse);
    },
  );

  test('inactive / error completion is not generation-ready', () {
    expect(
      koboldCompletionIsGenerationReady(
        200,
        '{"choices":[{"message":{"content":""},"finish_reason":"error"}]}',
      ),
      isFalse,
    );
    expect(
      koboldCompletionIsGenerationReady(
        200,
        '{"error":{"message":"model inactive"},"choices":[]}',
      ),
      isFalse,
    );
    expect(
      koboldCompletionIsGenerationReady(200, '{"choices":[{"text":""}]}'),
      isFalse,
    );
  });

  test(
    'ToolSupport auto-ping does not fire until worker lane is ready',
    () async {
      final probe = ToolTransportProbe();
      var pings = 0;
      var laneReady = false;
      final tester = ToolSupportTester(
        probe: probe,
        fireToolEval: (_, _) async {
          pings++;
          return const LlmToolResponse(
            calls: [
              LlmToolCall(name: 'report_ping', arguments: {'ok': true}),
            ],
            text: '',
          );
        },
        getBackendIdentity: () => 'worker|KoboldCPP|/tmp/q2.gguf',
        isBackendReady: () => true,
        isBusy: () => false,
        workerLaneReadyForPing: () => laneReady,
        onNotify: () {},
      );
      tester.onBackendMaybeChanged();
      await Future<void>.delayed(Duration.zero);
      expect(
        pings,
        0,
        reason: 'auto-ping must not open worker before gen-ready',
      );

      laneReady = true;
      tester.onBackendMaybeChanged();
      await Future<void>.delayed(Duration.zero);
      expect(pings, 1);
    },
  );
}

class _RecHost implements GpuSwapHost {
  _RecHost(this.label);

  @override
  final String label;

  @override
  Future<void> unload() async {}

  @override
  Future<void> restore() async {}
}

class _HangRestoreHost implements GpuSwapHost {
  @override
  String get label => 'worker';

  @override
  Future<void> unload() async {}

  @override
  Future<void> restore() async {
    await Future<void>.delayed(const Duration(milliseconds: 5));
    throw TimeoutException('Kobold admin reload_config');
  }
}
