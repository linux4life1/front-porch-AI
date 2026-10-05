// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

// The estimate against what a real KoboldCpp (1.122.1) set aside on Apple
// Silicon (Metal), for twenty models from fourteen families: dense, MoE,
// sliding-window, tied-output, hybrid recurrent, convolution, compressed
// attention (MLA) and per-layer-input models.
//
// Each model was loaded from its real header followed by zeros up to the
// real file size, so the engine allocated exactly what the real model needs
// (and generated nonsense). Every load in
// test/fixtures/kobold_loads/metal-1.122.1.json is one start: the context,
// batch, cache type, sliding window and flash attention it was started
// with, and the cache and working memory the engine printed, in MiB.
//
// The rule: the cache, which the file gives exactly, matches; the working
// memory is never below what the engine reserved, and not more than a fifth
// above it.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/utils/utils.dart';

const _dir = 'test/fixtures/gguf_headers';

final _infos = <String, ({GGUFModelInfo info, int bytes})>{};

({GGUFModelInfo info, int bytes}) _model(String name) =>
    _infos.putIfAbsent(name, () {
      final side =
          (jsonDecode(File('$_dir/$name.json').readAsStringSync()) as Map)
              .cast<String, dynamic>();
      final bytes = side['fixture_file_bytes'] as int;
      final header = GGUFFileReader.parseHeaderBytes(
        File('$_dir/$name.gguf').readAsBytesSync(),
      )!;
      return (
        info: GGUFParser.modelInfoFromHeader(header, fileSize: bytes)!,
        bytes: bytes,
      );
    });

void main() {
  final loads =
      (jsonDecode(
                File(
                  'test/fixtures/kobold_loads/metal-1.122.1.json',
                ).readAsStringSync(),
              )
              as Map)['loads']
          as List;

  for (final load in loads.cast<Map<String, dynamic>>()) {
    final model = load['model'] as String;
    final context = load['context'] as int;
    final batch = load['batch'] as int;
    final cache = load['cache'] as String;
    final swa = load['sliding_window'] as bool;
    final fa = load['flash_attention'] as bool;
    final kv = (load['kv_mib'] as num).toDouble();
    final compute = (load['compute_mib'] as num).toDouble();

    test('$model, ${context ~/ 1024}k, batch $batch, $cache'
        '${swa ? ', sliding window on' : ''}'
        '${fa ? '' : ', flash attention off'}', () {
      final m = _model(model);
      final e = VramEstimator.estimateFromArchitecture(
        modelInfo: m.info,
        fileSizeBytes: m.bytes,
        contextSize: context,
        batchSize: batch,
        kvQuant: cache,
        isSwa: swa,
        moeExpertsOnCpu: false,
        backend: KoboldMemoryBackend.metal,
        flashAttention: fa,
      );
      expect(e.kvCacheMb, kv.ceil(), reason: 'the cache');
      expect(
        e.computeBufMb,
        allOf(
          greaterThanOrEqualTo(compute.ceil()),
          lessThanOrEqualTo((compute * 1.20).ceil()),
        ),
        reason: 'the working memory',
      );
    });
  }
}
