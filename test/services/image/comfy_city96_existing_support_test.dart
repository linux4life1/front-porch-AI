// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/services/image/image.dart';

void main() {
  const url = 'http://127.0.0.1:8188';
  const other = 'http://127.0.0.1:8189';
  const graph = <String, dynamic>{
    'encoder': {
      'class_type': 'CLIPLoaderGGUF',
      'inputs': {'clip_name': 'qwen3vl_8b-Q4_K_M.gguf'},
    },
  };
  late Directory dir;
  late File loader;
  late City96Gate gate;
  var reads = 0;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('city96-existing-');
    loader = await File(
      '${dir.path}/loader.py',
    ).writeAsString('# custom loader');
    reads = 0;
    gate = City96Gate(
      locate: (_) async {
        reads++;
        return loader;
      },
      ask: (_) async =>
          throw StateError('Confirmation must not patch a loader'),
      write: (_, _) async => throw StateError('Confirmation must not write'),
    );
  });
  tearDown(() async => dir.delete(recursive: true));

  test(
    'explicit support allows checks and submission without loader writes',
    () async {
      expect(
        (await gate.check(comfyUrl: url, graph: graph)).state,
        City96State.needsUpdate,
      );
      gate.setExistingSupport(url, confirmed: true);
      expect(
        (await gate.check(comfyUrl: url, graph: graph)).state,
        City96State.ready,
      );
      await withoutCity96Ask(
        () => gate.ensureOrThrow(comfyUrl: url, graph: graph),
      );
      expect(reads, 1);
      expect(await loader.readAsString(), '# custom loader');
    },
  );

  test('confirmation is scoped to the complete server URL', () async {
    gate.setExistingSupport(url, confirmed: true);
    for (final address in [
      other,
      '$url/another-server',
      'https://127.0.0.1:8188',
    ]) {
      expect(
        (await gate.check(comfyUrl: address, graph: graph)).state,
        City96State.needsUpdate,
      );
    }
    expect(gate.hasExistingSupport(url), isTrue);
  });

  test('recheck restores inspection and blocks submission again', () async {
    gate.setExistingSupport(url, confirmed: true);
    gate.setExistingSupport(url, confirmed: false);
    expect(gate.hasExistingSupport(url), isFalse);
    expect(
      () => gate.ensureOrThrow(comfyUrl: url, graph: graph),
      throwsA(isA<ComfyLoaderUpdateNeeded>()),
    );
  });

  test('a new app gate has no confirmation', () {
    gate.setExistingSupport(url, confirmed: true);
    expect(City96Gate().hasExistingSupport(url), isFalse);
  });

  test('unrelated models keep the not-needed result', () async {
    gate.setExistingSupport(url, confirmed: true);
    expect(
      (await gate.check(comfyUrl: url, graph: const {})).state,
      City96State.notNeeded,
    );
    expect(reads, 0);
  });
}
