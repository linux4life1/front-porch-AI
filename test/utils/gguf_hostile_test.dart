// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

// A model file is read on the app's own thread (picking a model, the preset
// editor, the Local model card, every launch without a preset), so a broken
// or hostile header must be refused at once: a block count no model has
// used to hang or run the app out of memory, and so did a string length
// that reads back as negative and never moves the reader on.

import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:front_porch_ai/utils/gguf_parser.dart';

List<int> _u32(int v) =>
    (ByteData(4)..setUint32(0, v, Endian.little)).buffer.asUint8List();

List<int> _u64(int v) =>
    (ByteData(8)..setUint64(0, v, Endian.little)).buffer.asUint8List();

List<int> _str(String s) => [..._u64(utf8.encode(s).length), ...utf8.encode(s)];

/// A GGUF v3 header with [kv] written as given, each value its type and
/// bytes, so a test can write what no real file holds.
Uint8List _gguf(List<(String, int, List<int>)> kv) {
  final b = BytesBuilder()
    ..add(utf8.encode('GGUF'))
    ..add(_u32(3))
    ..add(_u64(0))
    ..add(_u64(kv.length));
  for (final (key, type, value) in kv) {
    b
      ..add(_str(key))
      ..add(_u32(type))
      ..add(value);
  }
  return b.takeBytes();
}

/// A Llama header claiming [blocks] blocks, with a per-layer list of 4.
Uint8List _blocks(int blocks) => _gguf([
  ('general.architecture', 8, _str('llama')),
  ('llama.block_count', 10, _u64(blocks)),
  ('llama.attention.head_count', 4, _u32(32)),
  ('llama.embedding_length', 4, _u32(4096)),
  (
    'llama.attention.head_count_kv',
    9,
    [..._u32(4), ..._u64(4), for (var i = 0; i < 4; i++) ..._u32(8)],
  ),
]);

/// Reads [bytes] as a model file the way the app does, in an isolate so a
/// read that never ends cannot stall the run: whether it gave model info,
/// and how long the read took.
Future<({bool info, int ms})> _read(Uint8List bytes) async {
  final dir = await Directory.systemTemp.createTemp('fpai hostile gguf');
  addTearDown(() => dir.delete(recursive: true));
  final path = (File(
    p.join(dir.path, 'hostile.gguf'),
  )..writeAsBytesSync(bytes)).path;
  return Isolate.run(() async {
    final watch = Stopwatch()..start();
    final info = await GGUFParser.getModelArchitectureInfo(path);
    return (info: info != null, ms: watch.elapsedMilliseconds);
  }).timeout(const Duration(seconds: 5));
}

void main() {
  test('a block count of 2^40 is refused at once', () async {
    final read = await _read(_blocks(1 << 40));
    expect(read.info, isFalse);
    expect(read.ms, lessThan(100));
  });

  test('five million blocks are refused at once', () async {
    final read = await _read(_blocks(5000000));
    expect(read.info, isFalse);
    expect(read.ms, lessThan(100));
  });

  test('a string length that reads back as negative stops the read', () async {
    final read = await _read(
      _gguf([
        ('general.architecture', 8, _str('llama')),
        // A list of 2^40 strings whose first length is 2^64 - 8.
        (
          'tokenizer.ggml.tokens',
          9,
          [..._u32(8), ..._u64(1 << 40), ..._u64(0xFFFFFFFFFFFFFFF8)],
        ),
        ('llama.block_count', 10, _u64(32)),
      ]),
    );
    expect(read.info, isFalse);
    expect(read.ms, lessThan(100));
  });

  test('a real-sized header still reads', () async {
    final read = await _read(_blocks(32));
    expect(read.info, isTrue);
  });
}
