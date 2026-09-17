// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/services/services.dart';

void main() {
  test('empty worker GGUF inherits the Models-tab file', () {
    expect(
      resolvedKoboldWorkerModelPath(
        workerPath: null,
        mouthPath: '/models/mouth.gguf',
      ),
      '/models/mouth.gguf',
    );
    expect(
      resolvedKoboldWorkerModelPath(workerPath: '  ', mouthPath: '/m.gguf'),
      '/m.gguf',
    );
    expect(
      resolvedKoboldWorkerModelPath(
        workerPath: '/models/worker.gguf',
        mouthPath: '/models/mouth.gguf',
      ),
      '/models/worker.gguf',
    );
  });
}
