// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

// The vision check reads the start of a model file on the app's own thread
// (picking a model, attaching a photo, the projector field), and has a
// header walk of its own beside the one in gguf_reader.dart. gguf_hostile_
// test.dart pins the other walk; these cases hold this one to the same
// rule: a header that makes the walk stand still or go backwards ends the
// read at once, and what was read before it still counts.

import 'package:flutter_test/flutter_test.dart';

import 'gguf_hostile_support.dart';

void main() {
  test('a string length that reads back as negative stops the walk', () async {
    final read = await readHostile(
      'vision',
      ggufHeader([
        ('general.architecture', 8, ggufStr('llama')),
        // A list of 2^40 strings whose first length is 2^64 - 8: the offset
        // never moves, so the walk would read the same length forever.
        (
          'tokenizer.ggml.tokens',
          9,
          [...u32(8), ...u64(1 << 40), ...u64(0xFFFFFFFFFFFFFFF8)],
        ),
      ]),
    );
    expect(read, ['llama', false]);
  });

  test('a list of numbers whose length reads back as negative stops the '
      'walk instead of going back to where it began', () async {
    const key = 'clip.hostile';
    // After the key, the value type, the list type and its length, a length
    // of minus that many bytes puts the walk at the start of this entry,
    // for as many entries as the header claims.
    final back = -(8 + key.length + 4 + 4 + 8);
    final read = await readHostile(
      'vision',
      ggufHeader([
        ('general.architecture', 8, ggufStr('llama')),
        (key, 9, [...u32(0), ...u64(back)]),
      ], kvCount: 1 << 40),
    );
    expect(read, ['llama', false]);
  });

  test(
    'a list whose length in bytes wraps around to minus stops the walk',
    () async {
      // An entry takes 32 bytes up to its values with an 8-byte key. 2^61 - 4
      // values of 8 bytes come to 2^64 - 32 bytes, which the walk reads as
      // -32: back to the start of the entry.
      const key = 'clip.abc';
      final read = await readHostile(
        'vision',
        ggufHeader([
          ('general.architecture', 8, ggufStr('llama')),
          (key, 9, [...u32(10), ...u64((1 << 61) - 4)]),
        ], kvCount: 1 << 40),
      );
      expect(read, ['llama', false]);
    },
  );
}
