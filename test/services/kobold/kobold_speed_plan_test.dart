// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

// The speed test's plan (the maintainer's ruling, 2026-10-06), as tables:
// the order of the settings, the ones skipped where they cannot differ or
// the app's rules forbid them, the greedy walk (each setting tried with the
// best so far, then fixed), what counts as quicker, and the words.

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/services/kobold/kobold.dart';

const _nvidia = KoboldBackendChoice(backend: KoboldGpuBackend.cuda, gpuId: 0);
const _rocm = KoboldBackendChoice(
  backend: KoboldGpuBackend.cuda,
  gpuId: 0,
  rocm: true,
);
const _vulkan = KoboldBackendChoice(backend: KoboldGpuBackend.vulkan);
const _apple = KoboldBackendChoice(
  backend: KoboldGpuBackend.none,
  unified: true,
);
const _cpu = KoboldBackendChoice(backend: KoboldGpuBackend.none);

List<KoboldKnob> _order(
  KoboldBackendChoice gpu, {
  List<int> batches = const [512, 1024, 2048],
  bool manual = false,
  bool moe = false,
  KvQuant cache = KvQuant.f16,
  bool flashRuns = true,
}) => [
  for (final (knob, _) in koboldSpeedSteps(
    koboldSpeedFactsFor(
      gpu: gpu,
      batches: batches,
      layersManual: manual,
      isMoe: moe,
      kvQuant: cache,
      flashAttentionRuns: flashRuns,
    ),
  ))
    knob,
];

const _start = KoboldKnobs(
  batch: 1024,
  mmq: true,
  mmap: true,
  mlock: false,
  flashAttention: true,
);

/// Runs [run] against an engine whose turn takes [seconds] for each try.
List<KoboldKnobs> _walk(
  KoboldSpeedRun run,
  double? Function(KoboldKnobs k) seconds,
) {
  final asked = <KoboldKnobs>[];
  for (var k = run.next(); k != null; k = run.next()) {
    asked.add(k);
    run.record(k, seconds(k));
    if (asked.length > 20) fail('the run never ends');
  }
  return asked;
}

void main() {
  group('the order, and what is skipped', () {
    test('batch, then MMQ, then mmap, then flash attention on an NVIDIA '
        'card with automatic layers', () {
      expect(_order(_nvidia), [
        KoboldKnob.batch,
        KoboldKnob.mmq,
        KoboldKnob.mmap,
        KoboldKnob.flashAttention,
      ]);
    });

    test('MMQ on the ROCm build too, and nowhere else', () {
      expect(_order(_rocm), contains(KoboldKnob.mmq));
      expect(_order(_vulkan), isNot(contains(KoboldKnob.mmq)));
      expect(_order(_apple), isNot(contains(KoboldKnob.mmq)));
      expect(_order(_cpu), isNot(contains(KoboldKnob.mmq)));
    });

    test('memory lock only with layers set by hand, and not for a MoE '
        'model, before flash attention', () {
      expect(_order(_nvidia, manual: true), [
        KoboldKnob.batch,
        KoboldKnob.mmq,
        KoboldKnob.mmap,
        KoboldKnob.mlock,
        KoboldKnob.flashAttention,
      ]);
      expect(_order(_nvidia), isNot(contains(KoboldKnob.mlock)));
      expect(
        _order(_nvidia, manual: true, moe: true),
        isNot(contains(KoboldKnob.mlock)),
      );
    });

    test('flash attention only where it can run and the chat memory is '
        'full size', () {
      expect(
        _order(_vulkan, flashRuns: false),
        isNot(contains(KoboldKnob.flashAttention)),
        reason: 'Gemma 4 on Vulkan, or ROCm that died with it on',
      );
      expect(
        _order(_nvidia, cache: KvQuant.q8_0),
        isNot(contains(KoboldKnob.flashAttention)),
        reason: 'a compressed cache turns it on',
      );
      expect(
        _order(_nvidia, cache: KvQuant.bf16),
        contains(KoboldKnob.flashAttention),
      );
    });

    test('no batch step when only one batch fits', () {
      expect(
        _order(_nvidia, batches: [512]),
        isNot(contains(KoboldKnob.batch)),
      );
      expect(_order(_cpu, batches: [512]), [
        KoboldKnob.mmap,
        KoboldKnob.flashAttention,
      ]);
    });
  });

  group('the walk', () {
    final facts = koboldSpeedFactsFor(
      gpu: _nvidia,
      batches: const [512, 1024, 2048],
      layersManual: false,
      isMoe: false,
      kvQuant: KvQuant.f16,
      flashAttentionRuns: true,
    );

    test('what runs now first, then each other value with the best so far, '
        'each setting fixed before the next', () {
      final run = KoboldSpeedRun(_start, facts);
      double turn(KoboldKnobs k) {
        var s = switch (k.batch) {
          512 => 10.0,
          1024 => 9.0,
          _ => 8.5,
        };
        if (!k.mmq) s -= 0.1; // within the band: not kept
        if (!k.mmap) s -= 0.6; // clearly quicker: kept
        if (!k.flashAttention) s += 1.0;
        return s;
      }

      final asked = _walk(run, turn);
      expect(run.total, asked.length, reason: 'known before it began');
      expect(asked, [
        _start,
        _start.withValue(KoboldKnob.batch, 512),
        _start.withValue(KoboldKnob.batch, 2048),
        _start
            .withValue(KoboldKnob.batch, 2048)
            .withValue(KoboldKnob.mmq, false),
        _start
            .withValue(KoboldKnob.batch, 2048)
            .withValue(KoboldKnob.mmap, false),
        _start
            .withValue(KoboldKnob.batch, 2048)
            .withValue(KoboldKnob.mmap, false)
            .withValue(KoboldKnob.flashAttention, false),
      ]);
      expect(
        run.best,
        _start
            .withValue(KoboldKnob.batch, 2048)
            .withValue(KoboldKnob.mmap, false),
      );
      expect(run.gain, closeTo(1 - 7.9 / 9.0, 1e-9));
    });

    test('nothing quicker by more than the band keeps what runs now', () {
      final run = KoboldSpeedRun(_start, facts);
      _walk(run, (k) => k == _start ? 9.0 : 8.9);
      expect(run.best, _start);
      expect(run.gain, 0);
      expect(
        koboldSpeedResultWords(run.gain),
        'Your current settings were already the fastest.',
      );
    });

    test('a try that could not be timed is never kept', () {
      final run = KoboldSpeedRun(_start, facts);
      _walk(run, (k) => k == _start ? 9.0 : (k.batch == 2048 ? null : 9.5));
      expect(run.best, _start);
      expect(run.tried.where((t) => t.seconds == null), hasLength(1));
    });

    test('when what runs now cannot be timed there is nothing to compare '
        'with, and the run stops there', () {
      final run = KoboldSpeedRun(_start, facts);
      expect(_walk(run, (_) => null), [_start]);
      expect(run.gain, 0);
    });
  });

  group('the words', () {
    test('the one line at the end says the outcome, never a setting', () {
      expect(koboldSpeedResultWords(0.3), 'Replies now come about 30% sooner.');
      expect(
        koboldSpeedResultWords(0.004),
        'Your current settings were already the fastest.',
      );
    });

    test('how long, in words', () {
      expect(
        koboldAboutWords(const Duration(seconds: 30)),
        'less than a minute',
      );
      expect(koboldAboutWords(const Duration(seconds: 70)), 'about a minute');
      expect(
        koboldAboutWords(const Duration(minutes: 4, seconds: 10)),
        'about 4 minutes',
      );
      expect(
        koboldSpeedAskWords(const Duration(minutes: 4)),
        'This takes about 4 minutes. Replies may start sooner afterwards. '
        'Run it?',
      );
      expect(
        koboldSpeedChatWaitWords(const Duration(seconds: 70)),
        'Testing speed settings, about a minute left.',
      );
    });

    test('what is left: the timings still to make, and the last reload', () {
      expect(
        koboldSpeedLeft(
          left: 3,
          perStep: const Duration(seconds: 20),
          load: const Duration(seconds: 8),
        ),
        const Duration(seconds: 68),
      );
    });
  });
}
