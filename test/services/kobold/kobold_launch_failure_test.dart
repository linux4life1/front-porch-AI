// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

// Why KoboldCpp stopped, told from what it printed. The log lines are
// real, from KoboldCpp on an RX 6900 XT (2026-10-04): the ROCm build
// running out of memory on the first prompt after a load that worked, and
// the Vulkan build dying silently on Gemma 4's first prompt.

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/services/kobold/kobold.dart';

const _loaded = [
  'Load Text Model OK: True',
  'Please connect to custom endpoint at http://localhost:5599',
  'Starting model warm up, please wait a moment...',
  '[09:59:09] CtxLimit:55/16384, Init:0.00s, Processed:54 in 0.07s',
];

void main() {
  test('the ROCm build running out of memory on the first prompt', () {
    final f = classifyKoboldExit(
      log: [
        ..._loaded,
        'Processing Prompt [BATCH] (1024 / 2180 tokens)ROCm pool[0]: alloc of '
            '33.60 MiB failed, flushing 23.68 MiB of cached buffers and '
            'retrying',
        'ROCm pool[0]: alloc of 4.20 MiB failed, flushing 50.40 MiB of cached '
            'buffers and retrying',
        'ROCm error: out of memory',
        '  current device: 0, in function alloc at '
            'ggml/src/ggml-cuda/ggml-cuda.cu:511',
      ],
      exitCode: -6,
      wasReady: true,
    );
    expect(f.kind, KoboldFailureKind.outOfMemory);
    expect(f.message, contains('while answering'));
    expect(f.message, contains('smaller context size'));
  });

  test('running out of memory while loading', () {
    final f = classifyKoboldExit(
      log: const ['CUDA error: out of memory'],
      exitCode: 1,
      wasReady: false,
    );
    expect(f.kind, KoboldFailureKind.outOfMemory);
    expect(f.message, contains('while loading'));
  });

  test('dying in the middle of a prompt without a word', () {
    final f = classifyKoboldExit(
      log: [
        ..._loaded,
        'Processing Prompt [BATCH] (0 / 2156 tokens)Processing Prompt [BATCH] '
            '(512 / 2156 tokens)Processing Prompt [BATCH] (1024 / 2156 '
            'tokens)',
      ],
      exitCode: -11,
      wasReady: true,
    );
    expect(f.kind, KoboldFailureKind.diedWhileAnswering);
  });

  test('a model file it cannot read', () {
    final f = classifyKoboldExit(log: const [], exitCode: 2, wasReady: false);
    expect(f.kind, KoboldFailureKind.unreadableModel);
  });

  test('stopping after a reply was finished is not "while answering"', () {
    final f = classifyKoboldExit(
      log: [
        ..._loaded,
        'Processing Prompt [BATCH] (275 / 275 tokens)',
        'Generating (50 / 64 tokens)',
        '[09:59:50] CtxLimit:290/16384, Init:0.15s, Processed:240 in 34.03s',
      ],
      exitCode: 1,
      wasReady: true,
    );
    expect(f.kind, KoboldFailureKind.other);
    expect(f.message, contains('exit code 1'));
  });

  group('the ROCm flash attention fallback', () {
    const died = KoboldFailure(KoboldFailureKind.diedWhileAnswering, '');
    const oom = KoboldFailure(KoboldFailureKind.outOfMemory, '');

    test('starts again without it when the ROCm build died mid-answer', () {
      expect(
        koboldRetryWithoutFlashAttention(
          failure: died,
          rocmWithFlashAttention: true,
          alreadyMarked: false,
        ),
        isTrue,
      );
    });

    test('not for running out of memory, which flash attention eases', () {
      expect(
        koboldRetryWithoutFlashAttention(
          failure: oom,
          rocmWithFlashAttention: true,
          alreadyMarked: false,
        ),
        isFalse,
      );
    });

    test('only once, and only for the ROCm build with it on', () {
      expect(
        koboldRetryWithoutFlashAttention(
          failure: died,
          rocmWithFlashAttention: true,
          alreadyMarked: true,
        ),
        isFalse,
      );
      expect(
        koboldRetryWithoutFlashAttention(
          failure: died,
          rocmWithFlashAttention: false,
          alreadyMarked: false,
        ),
        isFalse,
      );
    });
  });
}
