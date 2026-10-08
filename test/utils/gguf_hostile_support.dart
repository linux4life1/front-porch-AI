// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

// Support for the tests that feed the model-file readers a header no real
// model has. A reader that loops on a number from the file can spin for
// good, so each read runs in an isolate of its own that is killed when it
// has not answered: a hang fails the test instead of stalling the run (and
// is not left spinning behind it).

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:front_porch_ai/utils/gguf_parser.dart';
import 'package:front_porch_ai/utils/gguf_vision.dart';

List<int> u32(int v) =>
    (ByteData(4)..setUint32(0, v, Endian.little)).buffer.asUint8List();

List<int> i32(int v) =>
    (ByteData(4)..setInt32(0, v, Endian.little)).buffer.asUint8List();

List<int> u64(int v) =>
    (ByteData(8)..setUint64(0, v, Endian.little)).buffer.asUint8List();

/// A GGUF string: its length, then its bytes.
List<int> ggufStr(String s) => [
  ...u64(utf8.encode(s).length),
  ...utf8.encode(s),
];

/// A GGUF v3 header with [kv] written as given, each entry its key, value
/// type and value bytes. [kvCount] says how many entries the header claims
/// (as many as [kv] holds unless given).
Uint8List ggufHeader(List<(String, int, List<int>)> kv, {int? kvCount}) {
  final b = BytesBuilder()
    ..add(utf8.encode('GGUF'))
    ..add(u32(3))
    ..add(u64(0))
    ..add(u64(kvCount ?? kv.length));
  for (final (key, type, value) in kv) {
    b
      ..add(ggufStr(key))
      ..add(u32(type))
      ..add(value);
  }
  return b.takeBytes();
}

/// What a read of a hostile file gave, as plain values (they cross the
/// isolate): null when the reader refused the file.
typedef HostileRead = List<Object?>?;

/// Reads [bytes] as a model file with the reader named by [kind] and gives
/// the answer:
///
///  - `vision`: `[architecture, isMultimodal]` of [GgufVisionParser];
///  - `model`: `[nLayers, kvLayers.length, draftHeads]` of [GGUFParser].
///
/// A reader that has not answered after ten seconds is hung, which is the
/// failure being looked for; this is a hang guard, not a speed check.
Future<HostileRead> readHostile(String kind, Uint8List bytes) async {
  final dir = await Directory.systemTemp.createTemp('fpai hostile gguf');
  addTearDown(() => dir.delete(recursive: true));
  final file = File(p.join(dir.path, 'hostile.gguf'))..writeAsBytesSync(bytes);
  final port = ReceivePort();
  final isolate = await Isolate.spawn(_entry, [port.sendPort, kind, file.path]);
  try {
    final answer = await port.first.timeout(
      const Duration(seconds: 10),
      onTimeout: () => throw TimeoutException(
        'the $kind reader did not finish: it is stuck on this header',
      ),
    );
    return answer as HostileRead;
  } finally {
    isolate.kill(priority: Isolate.immediate);
    port.close();
  }
}

Future<void> _entry(List<Object> args) async {
  final send = args[0] as SendPort;
  final kind = args[1] as String;
  final path = args[2] as String;
  switch (kind) {
    case 'vision':
      final info = await GgufVisionParser.getVisionInfo(path);
      send.send(info == null ? null : [info.architecture, info.isMultimodal]);
    case 'model':
      final info = await GGUFParser.getModelArchitectureInfo(path);
      send.send(
        info == null
            ? null
            : [info.nLayers, info.kvLayers?.length, info.draftHeads],
      );
    default:
      throw ArgumentError('unknown reader: $kind');
  }
}
