// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// A local model's key is read from its file once per model and per load of
// the engine, not on a timer and not on every paint: the sidebar's pill asks
// for it while it builds, and a multi-GB file is not stat-ed per frame.

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/utils/local_model_key.dart';

void main() {
  test('the file is read once for a model, however often it is asked', () {
    var reads = 0;
    int? sizeOf(String path) {
      reads++;
      return 100;
    }

    final keys = LocalModelKeys();
    for (var i = 0; i < 50; i++) {
      expect(
        keys.of('/m/gemma.gguf', stamp: 1, sizeOf: sizeOf),
        'gemma.gguf#100',
      );
    }
    expect(reads, 1);
  });

  test('it is read again when the model changes or the engine loads', () {
    var size = 100;
    var reads = 0;
    int? sizeOf(String path) {
      reads++;
      return size;
    }

    final keys = LocalModelKeys();
    expect(
      keys.of('/m/gemma.gguf', stamp: 1, sizeOf: sizeOf),
      'gemma.gguf#100',
    );

    // The file was replaced on disk: nothing runs it yet, so nothing changes.
    size = 250;
    expect(
      keys.of('/m/gemma.gguf', stamp: 1, sizeOf: sizeOf),
      'gemma.gguf#100',
    );

    // The engine loads (a start, a swap, a reload): now it is the new file.
    expect(
      keys.of('/m/gemma.gguf', stamp: 2, sizeOf: sizeOf),
      'gemma.gguf#250',
    );

    // Another model is picked.
    expect(keys.of('/m/qwen.gguf', stamp: 2, sizeOf: sizeOf), 'qwen.gguf#250');
    expect(reads, 3);
  });

  test('no model, no key, no read', () {
    var reads = 0;
    final keys = LocalModelKeys();
    expect(
      keys.of(
        null,
        stamp: 1,
        sizeOf: (_) {
          reads++;
          return 1;
        },
      ),
      '',
    );
    expect(reads, 0);
  });
}
