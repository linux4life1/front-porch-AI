// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/services/services.dart';

void main() {
  test('HTTP 200 + success true / "true" / empty is accepted', () {
    expect(koboldAdminReloadSucceeded(200, '{"success":true}'), isTrue);
    expect(koboldAdminReloadSucceeded(200, '{"success":"true"}'), isTrue);
    expect(koboldAdminReloadSucceeded(200, ''), isTrue);
    expect(koboldAdminReloadSucceeded(200, '   '), isTrue);
    expect(koboldAdminReloadSucceeded(204, ''), isTrue);
    expect(koboldAdminReloadSucceeded(200, 'true'), isTrue);
    expect(koboldAdminReloadSucceeded(200, '"true"'), isTrue);
    expect(koboldAdminReloadSucceeded(200, '{"status":"ok"}'), isTrue);
  });

  test('HTTP 200 + success false is a real admin miss', () {
    expect(koboldAdminReloadSucceeded(200, '{"success":false}'), isFalse);
    expect(koboldAdminReloadSucceeded(200, '{"success":"false"}'), isFalse);
    expect(
      koboldAdminReloadSucceeded(200, '{"success":false}'),
      isFalse,
      reason: 'admin off returns 200 {"success":false} — not a process stop',
    );
  });

  test('non-2xx is never success', () {
    expect(koboldAdminReloadSucceeded(500, '{"success":true}'), isFalse);
    expect(koboldAdminReloadSucceeded(404, ''), isFalse);
  });

  test('load filename prefers GGUF, else a different .kcpps, else initial', () {
    expect(
      koboldAdminLoadFilename(
        requestedModel: '/tmp/worker.gguf',
        requestedKcpps: '/tmp/worker.kcpps',
      ),
      'worker.gguf',
    );
    expect(
      koboldAdminLoadFilename(
        requestedModel: '',
        requestedKcpps: '/tmp/worker.kcpps',
        launchedKcpps: '/tmp/mouth.kcpps',
      ),
      'worker.kcpps',
    );
    expect(
      koboldAdminLoadFilename(
        requestedModel: '',
        requestedKcpps: '/tmp/mouth.kcpps',
        launchedKcpps: '/tmp/mouth.kcpps',
      ),
      'initial_model',
    );
  });

  test('overrideconfig is the .kcpps basename only when a GGUF is named', () {
    expect(
      koboldAdminLoadOverride(
        requestedModel: '/tmp/w.gguf',
        requestedKcpps: '/cfg/w.kcpps',
      ),
      'w.kcpps',
    );
    expect(
      koboldAdminLoadOverride(
        requestedModel: '',
        requestedKcpps: '/cfg/w.kcpps',
      ),
      '',
    );
  });

  test('stage into admindir uses the basename when the dir is empty', () {
    expect(stageKoboldAdminFile('', '/models/w.gguf'), 'w.gguf');
  });

  test('connection refused is a retryable admin blip', () {
    expect(
      koboldAdminErrorIsTransient(Exception('Connection refused')),
      isTrue,
    );
    expect(
      koboldAdminErrorIsTransient(
        StateError('Kobold admin unload_model HTTP 200 body={"success":false}'),
      ),
      isFalse,
    );
  });

  test('retry wait doubles then caps; zero base stays instant', () {
    expect(
      koboldAdminRetryWait(1, const Duration(milliseconds: 250)),
      const Duration(milliseconds: 250),
    );
    expect(
      koboldAdminRetryWait(2, const Duration(milliseconds: 250)),
      const Duration(milliseconds: 500),
    );
    expect(
      koboldAdminRetryWait(4, const Duration(milliseconds: 250)),
      const Duration(milliseconds: 2000),
    );
    expect(koboldAdminRetryWait(1, Duration.zero), Duration.zero);
  });

  test('koboldAdminRetry skips delay after a non-transient miss', () async {
    var tries = 0;
    await expectLater(
      koboldAdminRetry(() async {
        tries++;
        throw StateError('{"success":false}');
      }, delay: const Duration(seconds: 5)),
      throwsStateError,
    );
    expect(tries, 1);
  });

  test('reload body includes overrideconfig when set', () {
    expect(koboldAdminReloadBody(filename: 'unload_model'), {
      'filename': 'unload_model',
    });
    expect(
      koboldAdminReloadBody(
        filename: 'worker.gguf',
        overrideConfig: 'worker.kcpps',
      ),
      {'filename': 'worker.gguf', 'overrideconfig': 'worker.kcpps'},
    );
  });
}
