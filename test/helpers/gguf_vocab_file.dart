// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:convert';
import 'dart:typed_data';

/// A real GGUF header: a vocabulary and an embedded template, no tensors.
Uint8List ggufWithVocab({
  required List<String> tokens,
  required String template,
}) {
  final out = BytesBuilder();
  void u32(int v) => out.add(
    (ByteData(4)..setUint32(0, v, Endian.little)).buffer.asUint8List(),
  );
  void u64(int v) => out.add(
    (ByteData(8)..setUint64(0, v, Endian.little)).buffer.asUint8List(),
  );
  void str(String v) {
    final bytes = utf8.encode(v);
    u64(bytes.length);
    out.add(bytes);
  }

  out.add(utf8.encode('GGUF'));
  u32(3);
  u64(0);
  u64(2);
  str('tokenizer.ggml.tokens');
  u32(9);
  u32(8);
  u64(tokens.length);
  tokens.forEach(str);
  str('tokenizer.chat_template');
  u32(8);
  str(template);
  return out.toBytes();
}
