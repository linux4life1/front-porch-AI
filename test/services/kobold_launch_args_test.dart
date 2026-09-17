// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Guards for the KoboldCpp argv builder.
//
// Every rule in buildKoboldLaunchArgs is a decision with a bug behind it — the
// iGPU-defaulting --usecublas that ran a discrete RTX's work on the integrated
// GPU at ~0.5 t/s, the flash-attention prerequisite that --quantkv needs, the
// launcher's argparse cap that rejects a batch size the engine itself accepts.
// None of it was reachable by a test while it lived inside startKobold, which
// spawns a process; as a pure function it is, so here it is.
//
// This file was written when the block was extracted (2026-08-08). It asserts
// the arguments as they were ALREADY being built — it is a characterisation of
// the shipped behaviour, not a new specification.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/services/kobold_launch_args.dart';
import 'package:front_porch_ai/services/storage_service.dart';

// The path_provider mock + in-memory StorageService factory.
import 'kobold_service_test.dart'
    show createStorageService, setupPathProviderMock;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setupPathProviderMock();

  late StorageService storage;
  late Directory binDir;

  setUp(() async {
    storage = await createStorageService();
    binDir = Directory.systemTemp.createTempSync('fpai_kobold_bin_');
  });

  tearDown(() {
    if (binDir.existsSync()) binDir.deleteSync(recursive: true);
  });

  Future<List<String>> build({
    String modelPath = '/models/mini-magnum-12b.gguf',
    String? kcppsPath,
    String? mmprojPath,
    int port = 5001,
    int gpuLayers = 33,
    int contextSize = 8192,
    bool useVulkan = false,
    bool useCublas = false,
    bool useMetal = false,
    bool useRocm = false,
  }) => buildKoboldLaunchArgs(
    storage: storage,
    executablePath: '${binDir.path}/koboldcpp',
    modelPath: modelPath,
    kcppsPath: kcppsPath,
    mmprojPath: mmprojPath,
    port: port,
    gpuLayers: gpuLayers,
    contextSize: contextSize,
    useVulkan: useVulkan,
    useCublas: useCublas,
    useMetal: useMetal,
    useRocm: useRocm,
  );

  /// The value that follows [flag], or null when the flag is absent.
  String? valueAfter(List<String> args, String flag) {
    final i = args.indexOf(flag);
    return i < 0 || i + 1 >= args.length ? null : args[i + 1];
  }

  test('standard mode carries the model, port, context and layers', () async {
    final args = await build();
    expect(valueAfter(args, '--model'), '/models/mini-magnum-12b.gguf');
    expect(valueAfter(args, '--port'), '5001');
    expect(valueAfter(args, '--contextsize'), '8192');
    expect(valueAfter(args, '--gpulayers'), '33');
  });

  test('--jinja is on BOTH launch paths', () async {
    // The whole reason reasoning models can think locally — and, less happily,
    // the reason a template with no system branch gets to throw the character
    // card away (system_role_probe.dart). It must never be conditional.
    expect(await build(), contains('--jinja'));
    expect(await build(kcppsPath: '/presets/mine.kcpps'), contains('--jinja'));
  });

  test('preset mode defers to the .kcpps and only forces the port', () async {
    final args = await build(kcppsPath: '/presets/mine.kcpps', modelPath: '');
    expect(valueAfter(args, '--config'), '/presets/mine.kcpps');
    expect(valueAfter(args, '--port'), '5001');
    expect(
      args,
      isNot(contains('--model')),
      reason: 'an empty modelPath means the preset owns the model',
    );
    expect(
      args,
      isNot(contains('--contextsize')),
      reason: 'the preset owns everything except the port',
    );
  });

  test('a preset with no model of its own still gets one on the CLI', () async {
    // Without this KoboldCpp opens its own native file picker.
    final args = await build(
      kcppsPath: '/presets/mine.kcpps',
      modelPath: '/models/picked.gguf',
    );
    expect(valueAfter(args, '--model'), '/models/picked.gguf');
  });

  test('CUDA always names an explicit GPU id', () async {
    // A bare --usecublas defaults to GPU 0, which on an iGPU + discrete-RTX
    // machine is the iGPU: everything ran at ~0.5 t/s and nothing said why.
    await storage.setGpuId(1);
    final args = await build(useCublas: true);
    expect(valueAfter(args, '--usecublas'), '1');
  });

  test(
    'ROCm names its device too and always disables flash attention',
    () async {
      // The flash-attention kernel crashes on many AMD cards, so it is off even
      // when the user asked for it in Advanced settings.
      await storage.setGpuId(2);
      await storage.setFlashAttentionEnabled(true);
      final args = await build(useRocm: true);
      expect(valueAfter(args, '--usehipblas'), '2');
      expect(args, contains('--noflashattention'));
      expect(args, isNot(contains('--flashattention')));
    },
  );

  test('flash attention no longer requires KV quantisation to be on', () async {
    // It used to be added only alongside --quantkv, so CUDA and Metal users
    // without KV quant silently never got the ~30% speed-up.
    await storage.setFlashAttentionEnabled(true);
    expect(await build(useCublas: true), contains('--flashattention'));
    expect(await build(useMetal: true), contains('--flashattention'));
    expect(
      await build(),
      isNot(contains('--flashattention')),
      reason: 'no GPU backend that supports it',
    );
  });

  test(
    '--quantkv forces flash attention on, even if the user turned it off',
    () async {
      // V-cache quantisation does not work without it.
      await storage.setFlashAttentionEnabled(false);
      await storage.setKvQuantizationLevel(2);
      final args = await build(useCublas: true);
      expect(valueAfter(args, '--quantkv'), '2');
      expect(args, contains('--flashattention'));
      expect(
        args.where((a) => a == '--flashattention').length,
        1,
        reason: 'added twice would be a duplicate flag on the command line',
      );
    },
  );

  test('--quantkv does NOT force flash attention on ROCm', () async {
    await storage.setFlashAttentionEnabled(true);
    await storage.setKvQuantizationLevel(2);
    final args = await build(useRocm: true);
    expect(args, contains('--quantkv'));
    expect(
      args,
      isNot(contains('--flashattention')),
      reason: 'the kernel crashes on AMD — quantkv must not smuggle it back',
    );
  });

  test('the default BLAS batch size is left off the command line', () async {
    await storage.setBlasBatchSize(512);
    expect(
      await build(),
      isNot(contains('--blasbatchsize')),
      reason: "KoboldCpp's own default should apply when untouched",
    );
  });

  test('an oversized BLAS batch rides a config file, not the flag', () async {
    // KoboldCpp's CLI rejects anything above 4096 (an argparse `choices`
    // list), but its config loader applies values with setattr AFTER parsing,
    // so the engine accepts what the launcher refuses.
    await storage.setBlasBatchSize(8192);
    final args = await build();
    expect(args, isNot(contains('--blasbatchsize')));
    final config = valueAfter(args, '--config');
    expect(config, isNotNull);
    expect(config, endsWith('fpai_batch_override.kcpps'));
    expect(
      jsonDecode(File(config!).readAsStringSync()),
      {'batchsize': 8192},
      reason:
          'the override must carry ONLY the batch size — every other '
          'flag stays authoritative on the CLI',
    );
  });

  test('an in-range BLAS batch uses the plain flag', () async {
    await storage.setBlasBatchSize(2048);
    final args = await build();
    expect(valueAfter(args, '--blasbatchsize'), '2048');
    expect(args, isNot(contains('--config')));
  });

  test('mlock is passed only when enabled', () async {
    await storage.setMlockEnabled(true);
    expect(await build(), contains('--usemlock'));
    await storage.setMlockEnabled(false);
    expect(await build(), isNot(contains('--usemlock')));
  });

  test('a missing mmproj is dropped rather than aborting the launch', () async {
    // A stale path in settings must not stop the backend from starting.
    expect(
      await build(mmprojPath: '${binDir.path}/not-here.gguf'),
      isNot(contains('--mmproj')),
    );
    expect(await build(mmprojPath: ''), isNot(contains('--mmproj')));

    final real = File('${binDir.path}/mmproj.gguf')..writeAsStringSync('x');
    final args = await build(mmprojPath: real.path);
    expect(valueAfter(args, '--mmproj'), real.path);
  });

  test('an mmproj reaches preset launches too', () async {
    // Multimodal presets were the case that used to be silently sightless.
    final real = File('${binDir.path}/mmproj.gguf')..writeAsStringSync('x');
    final args = await build(
      kcppsPath: '/presets/mine.kcpps',
      modelPath: '',
      mmprojPath: real.path,
    );
    expect(valueAfter(args, '--mmproj'), real.path);
  });

  test('vulkan is passed through', () async {
    expect(await build(useVulkan: true), contains('--usevulkan'));
    expect(await build(), isNot(contains('--usevulkan')));
  });

  test('managed launches enable admin reload_config', () async {
    final args = await build();
    expect(args, contains('--admin'));
    expect(valueAfter(args, '--admindir'), isNotEmpty);
    expect(await build(kcppsPath: '/presets/mine.kcpps'), contains('--admin'));
  });
}
