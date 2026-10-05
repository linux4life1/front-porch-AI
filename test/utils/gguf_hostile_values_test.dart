// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

// The reader that sizes the memory estimate loops over the model's layers
// (gguf_hostile_test.dart holds the block count and the string length). A
// count of draft blocks outside the model's own blocks must not decide how
// many layers there are.

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'gguf_hostile_support.dart';

/// A Llama header with [blocks] blocks and [extra] entries after them.
Uint8List _llama(
  int blocks, [
  List<(String, int, List<int>)> extra = const [],
]) => ggufHeader([
  ('general.architecture', 8, ggufStr('llama')),
  ('llama.block_count', 4, u32(blocks)),
  ('llama.attention.head_count', 4, u32(32)),
  ('llama.embedding_length', 4, u32(4096)),
  ...extra,
]);

void main() {
  test('a negative count of draft blocks does not make more layers than the '
      'model has', () async {
    final read = await readHostile(
      'model',
      _llama(32, [('llama.nextn_predict_layers', 5, i32(-1000000))]),
    );
    // Blocks, layers that keep a cache, draft blocks.
    expect(read, [32, 32, 0]);
  });

  test(
    'more draft blocks than the model has leave it none of its own',
    () async {
      final read = await readHostile(
        'model',
        _llama(32, [('llama.nextn_predict_layers', 4, u32(100))]),
      );
      expect(read, [32, 0, 32]);
    },
  );

  test(
    'a real draft block count still takes its blocks off the cache',
    () async {
      final read = await readHostile(
        'model',
        _llama(32, [('llama.nextn_predict_layers', 4, u32(2))]),
      );
      expect(read, [32, 30, 2]);
    },
  );
}
