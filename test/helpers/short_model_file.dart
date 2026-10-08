// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

// A real model file made for less chat than usual: Llama 3.2 3B's own header
// (test/fixtures/gguf_headers), grown to its real size, with only the length
// it was made for changed, as an older 4k or 8k role-play model would say.
// No fixture of a model made for under 16,384 tokens is kept, and the
// parser, the card and the phone read this one as they read any other.

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

const String _fixture = 'test/fixtures/gguf_headers/Llama-3.2-3B';

/// Writes the model into [dir] as [name], made for [contextLength] tokens,
/// and returns its path.
Future<String> writeShortModel(
  Directory dir, {
  required int contextLength,
  String name = 'Old-RP-8k-Q4_K_M.gguf',
}) async {
  final side = jsonDecode(File('$_fixture.json').readAsStringSync()) as Map;
  final header = Uint8List.fromList(File('$_fixture.gguf').readAsBytesSync());
  // The key, then its type (4: a 32-bit number), then the number.
  final key = utf8.encode('llama.context_length');
  final at = _indexOf(header, key);
  if (at < 0) throw StateError('no context length in $_fixture');
  final view = ByteData.sublistView(header);
  if (view.getUint32(at + key.length, Endian.little) != 4) {
    throw StateError('the context length is not a 32-bit number');
  }
  view.setUint32(at + key.length + 4, contextLength, Endian.little);
  final model = p.join(dir.path, name);
  final raf = await File(model).open(mode: FileMode.write);
  await raf.writeFrom(header);
  await raf.setPosition((side['fixture_file_bytes'] as int) - 1);
  await raf.writeByte(0);
  await raf.close();
  return model;
}

int _indexOf(List<int> bytes, List<int> part) {
  outer:
  for (var i = 0; i + part.length <= bytes.length; i++) {
    for (var j = 0; j < part.length; j++) {
      if (bytes[i + j] != part[j]) continue outer;
    }
    return i;
  }
  return -1;
}
