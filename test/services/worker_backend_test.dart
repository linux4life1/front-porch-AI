// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/services/chat/chat.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/services/storage/settings/remote_api_key_vault.dart';

void main() {
  test('unready copy is keyed by worker type', () {
    expect(workerLaneUnreadyMessage('kobold'), contains('KoboldCPP'));
    expect(workerLaneUnreadyMessage('omlx'), contains('omlx serve'));
    expect(workerLaneUnreadyMessage('openRouter'), contains('URL and key'));
    expect(workerLaneUnreadyMessage(''), isNull);
  });

  test('empty worker is off', () {
    expect(workerBackendIsOff(''), isTrue);
    expect(workerBackendIsOff('  '), isTrue);
    expect(workerBackendIsOff('openRouter'), isFalse);
  });

  test('Kobold and oMLX are local; LM Studio URL is local; Nano is API', () {
    expect(backendLaneIsLocal('kobold', ''), isTrue);
    expect(backendLaneIsLocal('omlx', ''), isTrue);
    expect(backendLaneIsLocal('openRouter', kLmStudioApiV1), isTrue);
    expect(backendLaneIsLocal('openRouter', kNanoGptApiV1), isFalse);
    expect(backendLaneIsLocal('openRouter', kOpenRouterApiV1), isFalse);
  });

  test('API+API is allowed — same host or different hosts', () {
    expect(
      workerPairAllowed(
        mouthType: 'openRouter',
        mouthUrl: kNanoGptApiV1,
        workerType: 'openRouter',
        workerUrl: kNanoGptApiV1,
      ),
      isTrue,
      reason: 'Nano Kimi mouth + Nano GLM worker',
    );
    expect(
      workerPairAllowed(
        mouthType: 'openRouter',
        mouthUrl: kOpenRouterApiV1,
        workerType: 'openRouter',
        workerUrl: kNanoGptApiV1,
      ),
      isTrue,
      reason: 'OpenRouter Grok mouth + Nano GLM worker',
    );
  });

  test('API+local and local+API are allowed', () {
    expect(
      workerPairAllowed(
        mouthType: 'openRouter',
        mouthUrl: kNanoGptApiV1,
        workerType: 'omlx',
        workerUrl: kOmlxApiV1,
      ),
      isTrue,
    );
    expect(
      workerPairAllowed(
        mouthType: 'kobold',
        mouthUrl: '',
        workerType: 'openRouter',
        workerUrl: kOpenRouterApiV1,
      ),
      isTrue,
    );
  });

  test('Kobold starts for mouth or an allowed Kobold worker', () {
    expect(
      shouldEnsureKoboldProcess(
        mouthType: 'openRouter',
        workerType: 'kobold',
        pairAllowed: true,
      ),
      isTrue,
    );
    expect(
      shouldEnsureKoboldProcess(
        mouthType: 'kobold',
        workerType: '',
        pairAllowed: true,
      ),
      isTrue,
    );
    expect(
      shouldEnsureKoboldProcess(
        mouthType: 'openRouter',
        workerType: 'openRouter',
        pairAllowed: true,
      ),
      isFalse,
    );
    expect(
      shouldEnsureKoboldProcess(
        mouthType: 'omlx',
        workerType: 'kobold',
        pairAllowed: false,
      ),
      isFalse,
    );
  });

  test('oMLX poller runs for mouth or an allowed oMLX worker', () {
    expect(
      shouldRunOmlxPoller(
        mouthType: 'openRouter',
        workerType: 'omlx',
        pairAllowed: true,
      ),
      isTrue,
    );
    expect(
      shouldRunOmlxPoller(mouthType: 'omlx', workerType: '', pairAllowed: true),
      isTrue,
    );
    expect(
      shouldRunOmlxPoller(
        mouthType: 'openRouter',
        workerType: '',
        pairAllowed: true,
      ),
      isFalse,
    );
  });

  test('local+local is refused; empty worker is allowed', () {
    expect(
      workerPairAllowed(
        mouthType: 'kobold',
        mouthUrl: '',
        workerType: 'omlx',
        workerUrl: kOmlxApiV1,
      ),
      isFalse,
    );
    expect(
      workerPairAllowed(
        mouthType: 'omlx',
        mouthUrl: kOmlxApiV1,
        workerType: 'openRouter',
        workerUrl: kLmStudioApiV1,
      ),
      isFalse,
    );
    expect(
      workerPairAllowed(
        mouthType: 'kobold',
        mouthUrl: '',
        workerType: '',
        workerUrl: '',
      ),
      isTrue,
    );
  });

  test('worker identity is prefixed and distinct from mouth', () {
    final mouth = evalBackendIdentityFor(
      backendName: 'Remote API',
      remoteApiUrl: kNanoGptApiV1,
      remoteModelName: 'moonshotai/kimi-k2.6:thinking',
      modelPath: null,
    );
    final worker = workerEvalIdentityFor(
      backendName: 'Remote API',
      remoteApiUrl: kNanoGptApiV1,
      remoteModelName: 'z-ai/glm-5.3',
      modelPath: null,
    );
    expect(worker, startsWith('worker|'));
    expect(worker, isNot(mouth));
    expect(mouth, isNot(contains('worker|')));
  });
}
