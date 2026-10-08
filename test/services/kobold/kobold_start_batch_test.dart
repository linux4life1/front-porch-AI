// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

// The physical batch auto mode runs before anything is measured (the
// maintainer's ruling, 2026-10-06): 1,024 on every NVIDIA card, 512 on
// ROCm, Vulkan, Apple Silicon and without a card. Memory is a ceiling only:
// a batch that puts less of the model on the card than 512 does is never
// used. A model with recurrent layers never goes below 1,024 on Vulkan
// (KoboldCpp issue 2402). What the speed test measured is used the same way,
// and the speed test tries 2,048 only where the fit leaves plenty spare.
// Real model headers on the machines they were measured on.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/services/kobold/kobold.dart';
import 'package:front_porch_ai/utils/gguf_parser.dart';
import 'package:front_porch_ai/utils/gguf_reader.dart';
import 'package:front_porch_ai/utils/kobold_memory_rules.dart';

const _dir = 'test/fixtures/gguf_headers';

KoboldFit _fit(
  String name,
  KoboldMemoryBackend backend, {
  int context = 16384,
}) {
  final side = (jsonDecode(File('$_dir/$name.json').readAsStringSync()) as Map)
      .cast<String, dynamic>();
  final header = GGUFFileReader.parseHeaderBytes(
    File('$_dir/$name.gguf').readAsBytesSync(),
  )!;
  final bytes = side['fixture_file_bytes'] as int;
  return KoboldFit(
    info: GGUFParser.modelInfoFromHeader(header, fileSize: bytes)!,
    fileSizeBytes: bytes,
    contextSize: context,
    batchSize: 512,
    backend: backend,
  );
}

KoboldMachine _card(KoboldMemoryBackend backend, int mb, {int? free}) =>
    KoboldMachine(
      backend: backend,
      totalGraphicsMb: mb,
      totalSystemMb: 32768,
      freeGraphicsMb: free ?? mb - 300,
      freeSystemMb: 28000,
    );

/// The original author's GTX 1060: 6 GB, about 5.1 GB free.
final _gtx1060 = _card(KoboldMemoryBackend.cuda, 6144, free: 5222);

const _noCard = KoboldMachine(
  backend: KoboldMemoryBackend.cuda,
  totalGraphicsMb: 0,
  totalSystemMb: 32768,
  freeGraphicsMb: 0,
  freeSystemMb: 28000,
);

int _batch(KoboldFit fit, KoboldMachine m, {int? measured, int? chosen}) =>
    koboldAutoTuning(fit, m, measured: measured, batchSize: chosen).batchSize;

void main() {
  group('where auto mode starts', () {
    test('1,024 on an NVIDIA card, even where 2,048 would fit', () {
      final fit = _fit('Qwen3-14B', KoboldMemoryBackend.cuda);
      final card = _card(KoboldMemoryBackend.cuda, 24576);
      expect(_batch(fit, card), 1024);
      expect(koboldBatchCandidates(fit, card), contains(2048));
    });

    test('1,024 on an 8 GB NVIDIA card too, where the model fits at it', () {
      final fit = _fit('Llama-3.2-3B', KoboldMemoryBackend.cuda);
      final load = fit.copyWith(batchSize: 1024).mostThatFits(7600 - 1024);
      expect(load.allOnCard, isTrue);
      expect(
        _batch(fit, _card(KoboldMemoryBackend.cuda, 8192, free: 7600)),
        1024,
      );
    });

    test('and 512 on the 6 GB card, where 1,024 would put fewer layers on '
        'it', () {
      // At 16,384 tokens the model does not fit there whole even at 512 (25
      // of 29 layers); 1,024's larger working memory would leave 22.
      final fit = _fit('Llama-3.2-3B', KoboldMemoryBackend.cuda);
      final budget = _gtx1060.graphicsMb - kKoboldFitPaddingMb;
      final at512 = fit.copyWith(batchSize: 512).mostThatFits(budget);
      final at1024 = fit.copyWith(batchSize: 1024).mostThatFits(budget);
      expect(at1024.gpuLayers, lessThan(at512.gpuLayers));
      expect(_batch(fit, _gtx1060), 512);
    });

    test('512 on ROCm, Vulkan and Apple Silicon', () {
      for (final backend in [
        KoboldMemoryBackend.rocm,
        KoboldMemoryBackend.vulkan,
        KoboldMemoryBackend.metal,
      ]) {
        expect(
          _batch(_fit('Qwen3-14B', backend), _card(backend, 24576)),
          512,
          reason: backend.name,
        );
      }
    });

    test('512 without a card', () {
      expect(_batch(_fit('Qwen3-14B', KoboldMemoryBackend.cuda), _noCard), 512);
      expect(
        koboldBatchCandidates(
          _fit('Qwen3-14B', KoboldMemoryBackend.cuda),
          _noCard,
        ),
        [512],
      );
    });
  });

  group('memory is a ceiling', () {
    test('an NVIDIA card falls back to 512 where 1,024 would push experts '
        'off the card', () {
      final fit = _fit('Qwen3.6-35B-A3B-Q4_K_XL', KoboldMemoryBackend.cuda);
      expect(_batch(fit, _gtx1060), 512);
      expect(koboldBatchCandidates(fit, _gtx1060), [512]);
    });

    test('a measured 2,048 is used while it costs nothing on the card, and '
        'given up where it would', () {
      final card = _card(KoboldMemoryBackend.vulkan, 16368, free: 16332);
      expect(
        _batch(
          _fit('Qwen3-14B', KoboldMemoryBackend.vulkan),
          card,
          measured: 2048,
        ),
        2048,
      );
      final long = _fit(
        'Qwen3-14B',
        KoboldMemoryBackend.vulkan,
        context: 65536,
      );
      expect(_batch(long, card, measured: 2048), 512);
    });

    test('the speed test tries 2,048 only with plenty spare beside the '
        'model', () {
      final fit = _fit('Qwen3-14B', KoboldMemoryBackend.cuda);
      final roomy = _card(KoboldMemoryBackend.cuda, 24576);
      final load = fit
          .copyWith(batchSize: 2048)
          .mostThatFits(24576 - 300 - 1024);
      expect(load.allOnCard, isTrue);
      // Just enough to hold the model at 2,048 with KoboldCpp's 1 GB spare,
      // and less than the plenty the test asks for beside it.
      final tight = _card(
        KoboldMemoryBackend.cuda,
        24576,
        free: load.cardMb + kKoboldFitPaddingMb + 100,
      );
      expect(koboldBatchCandidates(fit, roomy), [512, 1024, 2048]);
      expect(koboldBatchCandidates(fit, tight), isNot(contains(2048)));
    });
  });

  group('a model with recurrent layers on Vulkan', () {
    final hybrid = _fit('Qwen3.6-35B-A3B-Q4_K_XL', KoboldMemoryBackend.vulkan);

    test('never runs below 1,024, even where memory is short', () {
      expect(hybrid.recurrent, isTrue);
      final small = _card(KoboldMemoryBackend.vulkan, 8192);
      expect(_batch(hybrid, small), 1024);
      expect(koboldBatchCandidates(hybrid, small).first, 1024);
      expect(koboldBatchCandidates(hybrid, small), isNot(contains(512)));
    });

    test('a batch chosen in Settings is held to that floor', () {
      final card = _card(KoboldMemoryBackend.vulkan, 24576);
      expect(_batch(hybrid, card, chosen: 512), 1024);
      expect(_batch(hybrid, card, chosen: 2048), 2048);
    });

    test('the same model on CUDA keeps 512 when memory asks for it', () {
      final cuda = _fit('Qwen3.6-35B-A3B-Q4_K_XL', KoboldMemoryBackend.cuda);
      expect(_batch(cuda, _gtx1060), 512);
    });
  });
}
