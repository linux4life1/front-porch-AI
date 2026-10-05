// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

// Auto mode's own choices (batch, smart cache slots, context shift) and its
// plain verdict on each context size, for real model headers on the
// machines they were measured on: a 16 GB AMD card, the original author's
// 6 GB GTX 1060 (about 5.1 GB and 11 GB free), and Apple Silicon.
//
// Changed 2026-10-05: auto mode now offers context up to the length the
// model was made for, past 131,072 too (the maintainer's ruling; see
// kobold_context_ceiling_test.dart). Qwen3.6 35B is made for 262,144, so
// "the author's machine" is offered 262,144 as well, and on that 6 GB card
// it is too big, like 131,072. Its expected verdicts gain that one entry;
// the other five and the most that works well (65,536) are unchanged.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/services/kobold/kobold.dart';
import 'package:front_porch_ai/utils/gguf_parser.dart';
import 'package:front_porch_ai/utils/gguf_reader.dart';
import 'package:front_porch_ai/utils/kobold_memory_rules.dart';
import 'package:front_porch_ai/utils/smart_cache_estimate.dart';

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

const _amd16 = KoboldMachine(
  backend: KoboldMemoryBackend.vulkan,
  totalGraphicsMb: 16368,
  totalSystemMb: 32000,
  freeGraphicsMb: 16332,
  freeSystemMb: 28000,
);

const _author1060 = KoboldMachine(
  backend: KoboldMemoryBackend.cuda,
  totalGraphicsMb: 6144,
  totalSystemMb: 16384,
  freeGraphicsMb: 5222,
  freeSystemMb: 11063,
);

const _mac = KoboldMachine(
  backend: KoboldMemoryBackend.metal,
  totalGraphicsMb: 36864,
  totalSystemMb: 49152,
  freeGraphicsMb: 30000,
  freeSystemMb: 30000,
);

void main() {
  group('the batch auto mode picks', () {
    test('the largest when the model fits with room to spare', () {
      final t = koboldAutoTuning(
        _fit('Qwen3-14B', KoboldMemoryBackend.vulkan),
        _amd16,
      );
      expect(t.batchSize, 2048);
      expect(t.load.allOnCard, isTrue);
    });

    test('KoboldCpp\'s own 512 when a larger one would push layers or '
        'experts off the card', () {
      final dense = koboldAutoTuning(
        _fit('Qwen3-14B', KoboldMemoryBackend.vulkan, context: 65536),
        _amd16,
      );
      expect(dense.batchSize, 512);
      expect(dense.load.gpuLayers, 30, reason: 'what KoboldCpp chose');

      final moe = koboldAutoTuning(
        _fit('Qwen3.6-35B-A3B-Q4_K_XL', KoboldMemoryBackend.cuda),
        _author1060,
      );
      expect(moe.batchSize, 512);
    });

    test('one chosen in Settings is kept', () {
      final t = koboldAutoTuning(
        _fit('Qwen3-14B', KoboldMemoryBackend.vulkan),
        _amd16,
        batchSize: 768,
      );
      expect(t.batchSize, 768);
    });
  });

  group('smart cache slots', () {
    test('one per kind of prompt when memory allows', () {
      final t = koboldAutoTuning(
        _fit('Qwen3-14B', KoboldMemoryBackend.vulkan),
        _amd16,
      );
      expect(t.slots.slots, 3);
      expect(t.smartCache, (asked: 3, contextShift: true));
    });

    test('none on the author\'s machine, where the model already needs '
        'more than is free; context shift off so KoboldCpp adds none', () {
      final t = koboldAutoTuning(
        _fit('Qwen3.6-35B-A3B-Q4_K_XL', KoboldMemoryBackend.cuda),
        _author1060,
      );
      expect(t.slots.limit, SmartCacheLimit.noRoom);
      expect(t.smartCache, (asked: 0, contextShift: false));
    });

    test('what is written always makes no more slots than fit', () {
      for (final recurrent in [false, true]) {
        for (var slots = 0; slots <= 9; slots++) {
          final w = koboldSmartCacheSetting(slots: slots, recurrent: recurrent);
          final made = koboldSmartCacheSlots(
            asked: w.asked,
            recurrent: recurrent,
            fastForward: true,
            contextShift: w.contextShift,
          );
          expect(made, lessThanOrEqualTo(slots), reason: '$slots $recurrent');
        }
      }
      // A recurrent model keeps context shift, and KoboldCpp's own slots,
      // from three up.
      expect(koboldSmartCacheSetting(slots: 2, recurrent: true), (
        asked: 2,
        contextShift: false,
      ));
      expect(koboldSmartCacheSetting(slots: 3, recurrent: true), (
        asked: 2,
        contextShift: true,
      ));
      expect(koboldSmartCacheSetting(slots: 7, recurrent: true), (
        asked: 5,
        contextShift: true,
      ));
    });
  });

  group('the verdict on each context size', () {
    Map<int, KoboldContextOutcome> outcomes(
      KoboldFit fit,
      KoboldMachine machine, {
      void Function(int? largestGood)? largest,
    }) {
      final v = koboldContextVerdicts(
        fit: fit,
        machine: machine,
        choices: koboldContextChoices(
          current: fit.contextSize,
          modelMax: fit.info.contextLength,
        ),
      );
      largest?.call(v.largestGood);
      return {for (final e in v.verdicts) e.contextSize: e.outcome};
    }

    test('the author\'s machine: below 16,384 is not supported, 128k is too '
        'big, and 65,536 is named as the most that works well', () {
      int? most;
      final o = outcomes(
        _fit('Qwen3.6-35B-A3B-Q4_K_XL', KoboldMemoryBackend.cuda),
        _author1060,
        largest: (l) => most = l,
      );
      expect(o, {
        8192: KoboldContextOutcome.tooSmall,
        16384: KoboldContextOutcome.likeNow,
        32768: KoboldContextOutcome.likeNow,
        65536: KoboldContextOutcome.slower,
        131072: KoboldContextOutcome.tooBig,
        262144: KoboldContextOutcome.tooBig,
      });
      expect(most, 65536);
    });

    test('only sizes the model was made for are offered', () {
      final o = outcomes(_fit('Qwen3-14B', KoboldMemoryBackend.vulkan), _amd16);
      expect(o.keys, [8192, 16384, 32768]);
      expect(o[32768], KoboldContextOutcome.littleSlower);
    });

    test('on a Mac nothing moves to system memory, so too big means out of '
        'memory', () {
      int? most;
      final o = outcomes(
        _fit('gemma-4-12b-it', KoboldMemoryBackend.metal),
        _mac,
        largest: (l) => most = l,
      );
      expect(o[131072], KoboldContextOutcome.tooBig);
      expect(most, 65536);
    });

    test('a small model whose long context still fits in a Mac\'s memory is '
        'slower there, not too big', () {
      final o = outcomes(_fit('Llama-3.2-3B', KoboldMemoryBackend.metal), _mac);
      expect(o[131072], KoboldContextOutcome.slower);
    });

    test('the words say what happens, never how', () {
      final big = koboldContextWords(
        const KoboldContextVerdict(
          contextSize: 131072,
          outcome: KoboldContextOutcome.tooBig,
          verySlow: true,
          outOfMemory: true,
        ),
        largestGood: 65536,
      );
      expect(big.title, 'Too big for this computer.');
      expect(
        big.text,
        'Replies would be very slow, and the computer may run out of '
        'memory. The most that works well here is 65,536.',
      );
      final small = koboldContextWords(
        const KoboldContextVerdict(
          contextSize: 8192,
          outcome: KoboldContextOutcome.tooSmall,
        ),
        largestGood: null,
      );
      expect(small.text, contains('16,384 tokens'));
      for (final word in ['batch', 'layer', 'expert', '8-bit', 'cache']) {
        expect(
          '${big.text} ${small.text}'.toLowerCase(),
          isNot(contains(word)),
        );
      }
    });
  });
}
