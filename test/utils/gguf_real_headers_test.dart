// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

// The header reader against real model headers (see
// test/fixtures/gguf_headers/README.md): the exact size of the weights, by
// where KoboldCpp can put them, must match what was measured from the real
// files.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/utils/utils.dart';

const _dir = 'test/fixtures/gguf_headers';

void main() {
  final names =
      Directory(_dir)
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.gguf'))
          .map((f) => f.uri.pathSegments.last.replaceAll('.gguf', ''))
          .toList()
        ..sort();

  test('there are real headers to check', () {
    expect(names.length, greaterThanOrEqualTo(9));
  });

  for (final name in names) {
    test('$name: every tensor is read, and the weights add up to what the '
        'real file holds', () {
      final side =
          (jsonDecode(File('$_dir/$name.json').readAsStringSync()) as Map)
              .cast<String, dynamic>();
      final truth = (side['truth'] as Map).cast<String, dynamic>();
      final bytes = (truth['bytes'] as Map).cast<String, dynamic>();

      final header = GGUFFileReader.parseHeaderBytes(
        File('$_dir/$name.gguf').readAsBytesSync(),
      )!;
      expect(header.tensors.length, truth['n_tensors']);

      final weights = GGUFWeights.fromTensorSizes(
        header.tensorSizes(side['fixture_file_bytes'] as int),
      );
      expect(weights.total, bytes['total']);
      expect(
        weights.perBlock.fold<int>(0, (sum, b) => sum + b),
        bytes['blocks'],
      );
      expect(weights.experts, bytes['expert']);
      expect(weights.tokenEmbedding, bytes['token_embd']);
      expect(weights.output, bytes['output']);
      expect(weights.other, bytes['other']);
      expect(weights.perBlock.length, truth['n_layer']);
    });
  }

  test('a header cut off inside the tensor table gives no tensors rather '
      'than some of them', () {
    final whole = File('$_dir/Qwen3-14B.gguf').readAsBytesSync();
    final cut = whole.sublist(0, whole.length ~/ 2);
    final header = GGUFFileReader.parseHeaderBytes(cut)!;
    expect(header.tensors, isEmpty);
    expect(header.meta['general.architecture'], 'qwen3');
  });
}
