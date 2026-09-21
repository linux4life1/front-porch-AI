// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter_test/flutter_test.dart';

import 'package:front_porch_ai/services/web/util/step_up.dart';

void main() {
  test('worker GGUF / kcpps path change needs a password', () {
    expect(
      workerPathWriteNeedsStepUp(
        {'workerKoboldModelPath': '/models/other.gguf'},
        currentWorkerModelPath: '/models/mouth.gguf',
        currentWorkerKcppsPath: '',
      ),
      isTrue,
    );
    expect(
      workerPathWriteNeedsStepUp(
        {'workerKoboldModelPath': '/models/mouth.gguf'},
        currentWorkerModelPath: '/models/mouth.gguf',
        currentWorkerKcppsPath: '',
      ),
      isFalse,
    );
  });

  test('a new Tavily key needs a password', () {
    expect(
      searchApiKeyWriteNeedsStepUp({
        'realism': {'searchApiKey': 'tvly-secret'},
      }),
      isTrue,
    );
    expect(
      searchApiKeyWriteNeedsStepUp({
        'realism': {'searchApiKey': ''},
      }),
      isFalse,
    );
  });
}
