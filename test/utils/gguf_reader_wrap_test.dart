// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

// The reader that sizes the memory estimate steps over a list in the header
// by its count times the width of a value. That product wraps around for a
// count no real list has, and can read back as a small step backwards (see
// gguf_hostile_test.dart for the string lists).

import 'package:flutter_test/flutter_test.dart';

import 'gguf_hostile_support.dart';

void main() {
  test('a list whose length in bytes wraps around to minus stops the '
      'read', () async {
    // An entry takes 32 bytes up to its values with an 8-byte key. 2^61 - 4
    // values of 8 bytes come to 2^64 - 32 bytes, which the reader takes as
    // -32: back to the start of the entry, for as many entries as the
    // header claims.
    final read = await readHostile(
      'model',
      ggufHeader([
        ('general.architecture', 8, ggufStr('llama')),
        ('abcdefgh', 9, [...u32(10), ...u64((1 << 61) - 4)]),
      ], kvCount: 1 << 40),
    );
    expect(read, isNull);
  });
}
