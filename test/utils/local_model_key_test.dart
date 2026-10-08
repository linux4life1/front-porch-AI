// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// What a local model is remembered by: its file name and size, never the
// folder it happens to sit in. The tool-calling verdicts the app keeps across
// restarts are filed under this.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/utils/local_model_key.dart';
import 'package:path/path.dart' as p;

void main() {
  const sizes = {
    '/models/gemma.gguf': 100,
    '/elsewhere/deeper/gemma.gguf': 100,
    '/models/renamed.gguf': 100,
    '/models/other.gguf': 250,
  };
  int? sizeOf(String path) => sizes[path];

  test('the same file moved to another folder is the same model', () {
    expect(
      localModelKey('/models/gemma.gguf', sizeOf: sizeOf),
      localModelKey('/elsewhere/deeper/gemma.gguf', sizeOf: sizeOf),
    );
  });

  test('a renamed file is another name, tested again once', () {
    expect(
      localModelKey('/models/renamed.gguf', sizeOf: sizeOf),
      isNot(localModelKey('/models/gemma.gguf', sizeOf: sizeOf)),
    );
  });

  test('a different model at the same path is another model', () {
    var size = 100;
    final before = localModelKey('/models/gemma.gguf', sizeOf: (_) => size);
    size = 250; // the file was replaced by another quant or another tune
    final after = localModelKey('/models/gemma.gguf', sizeOf: (_) => size);
    expect(after, isNot(before));
  });

  test('a file that cannot be read is still named, by its name', () {
    expect(localModelKey('/gone/x.gguf', sizeOf: (_) => null), 'x.gguf#?');
  });

  test('no path names no model', () {
    expect(localModelKey(null), '');
    expect(localModelKey('  '), '');
  });

  test('a real file moved to another folder keeps its name', () async {
    final dir = await Directory.systemTemp.createTemp('fpai model key');
    addTearDown(() => dir.delete(recursive: true));
    final first = File(p.join(dir.path, 'one', 'model.gguf'))
      ..createSync(recursive: true)
      ..writeAsBytesSync(List.filled(4096, 7));
    final key = localModelKey(first.path);
    expect(key, 'model.gguf#4096');

    final moved = first.renameSync(
      (Directory(p.join(dir.path, 'two'))..createSync()).path +
          p.separator +
          'model.gguf',
    );
    expect(localModelKey(moved.path), key);
  });
}
