// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

// What the Local model card says in auto mode (desktop and phone: both read
// KoboldStatusFacts) must be about the backend the launch really runs. The
// card used to take the backend from the detected card alone and ignore the
// switches in Settings, so an AMD user on ROCm was judged by Vulkan's rules
// and a user who chose "CPU only" was told the model fits on the card.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/services/storage/storage.dart';
import 'package:front_porch_ai/utils/gguf_reader.dart';
import 'package:front_porch_ai/utils/utils.dart';

import '../../golden/support/fakes_storage.dart';
import '../kobold_service_test.dart'
    show createStorageService, setupPathProviderMock;

const _dir = 'test/fixtures/gguf_headers';

({GGUFModelInfo info, int bytes}) _model(String name) {
  final side = (jsonDecode(File('$_dir/$name.json').readAsStringSync()) as Map)
      .cast<String, dynamic>();
  final header = GGUFFileReader.parseHeaderBytes(
    File('$_dir/$name.gguf').readAsBytesSync(),
  )!;
  final bytes = side['fixture_file_bytes'] as int;
  return (
    info: GGUFParser.modelInfoFromHeader(header, fileSize: bytes)!,
    bytes: bytes,
  );
}

HardwareInfo _hw(
  String vendor, {
  int vramMb = 12288,
  bool cuda = false,
  bool metal = false,
}) => HardwareInfo(
  gpuName: '$vendor card',
  vramMb: vramMb,
  ramMb: 32768,
  vendor: vendor,
  hasCuda: cuda,
  hasMetal: metal,
);

/// The switches as the Settings chips write them: every one set, the chosen
/// one on.
Future<void> _chip(
  BackendSettings b, {
  bool cublas = false,
  bool vulkan = false,
  bool rocm = false,
  bool metal = false,
}) async {
  await b.setUseCublas(cublas);
  await b.setUseVulkan(vulkan);
  await b.setUseRocm(rocm);
  await b.setUseMetal(metal);
}

/// What the card shows for each context size and the largest that works, as
/// text so that two are equal when they say the same.
typedef _Shown = String;

String _text(int? largest, Map<int, String> outcomes) =>
    'largest $largest, $outcomes';

_Shown _shown(KoboldStatusFacts f) => _text(f.largestGood, {
  for (final e in f.verdicts.entries) e.key: e.value.outcome.name,
});

/// The same verdicts worked out with the backend named outright, which is
/// what the card must come to when that is the backend that runs.
_Shown _judged(
  ({GGUFModelInfo info, int bytes}) m, {
  required KoboldMemoryBackend backend,
  required bool flashAttention,
  required int vramMb,
  required int contextSize,
  int? batchSize,
}) {
  final fit = KoboldFit(
    info: m.info,
    fileSizeBytes: m.bytes,
    contextSize: contextSize,
    batchSize: 512,
    backend: backend,
    flashAttention: flashAttention,
  );
  final machine = KoboldMachine(
    backend: backend,
    totalGraphicsMb: vramMb,
    totalSystemMb: 32768,
    freeGraphicsMb: vramMb - 600,
    freeSystemMb: 16384,
  );
  final v = koboldContextVerdicts(
    fit: fit,
    machine: machine,
    choices: koboldContextChoices(
      current: contextSize,
      modelMax: m.info.contextLength,
    ),
    batchSize: batchSize,
  );
  return _text(v.largestGood, {
    for (final x in v.verdicts) x.contextSize: x.outcome.name,
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setupPathProviderMock();

  KoboldStatusFacts facts(
    StorageService storage,
    HardwareInfo hw,
    ({GGUFModelInfo info, int bytes}) m,
  ) => KoboldStatusFacts.of(
    storage: storage,
    hardware: hw,
    free: (graphics: hw.vramMb - 600, system: 16384),
    info: m.info,
    bytes: m.bytes,
  )!;

  test(
    'a user who chose "CPU only" is not told the model fits on the card',
    () async {
      final storage = FakeStorageService();
      final qwen = _model('Qwen3-14B');
      final nvidia = _hw('Nvidia', cuda: true, vramMb: 16384);
      expect(
        facts(storage, nvidia, qwen).lines.first,
        contains('fits on your graphics card'),
      );
      // The chips write all four switches off for "CPU only".
      await _chip(storage.backendSettings);
      final cpu = facts(storage, nvidia, qwen);
      expect(cpu.lines.first, contains('no graphics card it can use'));
      expect(cpu.lines.first, isNot(contains('fits on your graphics card')));
    },
  );

  test('an AMD card with ROCm chosen is judged by ROCm, and without it by '
      'Vulkan', () async {
    // An RX 7900 XT.
    const vram = 20480;
    final gemma = _model('gemma-4-12b-it');
    final amd = _hw('AMD', vramMb: vram);
    final storage = FakeStorageService();
    await storage.backendSettings.setContextSize(16384);

    // Gemma 4 on Vulkan runs with flash attention off; ROCm has it on.
    final onRocm = _judged(
      gemma,
      backend: KoboldMemoryBackend.rocm,
      flashAttention: true,
      vramMb: vram,
      contextSize: 16384,
    );
    final onVulkan = _judged(
      gemma,
      backend: KoboldMemoryBackend.vulkan,
      flashAttention: false,
      vramMb: vram,
      contextSize: 16384,
    );
    expect(
      onRocm,
      isNot(onVulkan),
      reason: 'this machine and model must tell the two backends apart',
    );

    expect(_shown(facts(storage, amd, gemma)), onVulkan, reason: 'automatic');
    await _chip(storage.backendSettings, rocm: true);
    expect(_shown(facts(storage, amd, gemma)), onRocm, reason: 'ROCm chosen');
  });

  test('a batch chosen in Settings is the one the verdicts are worked out '
      'at', () async {
    const vram = 12000;
    final qwen = _model('Qwen3-14B');
    final nvidia = _hw('Nvidia', cuda: true, vramMb: vram);
    final storage = FakeStorageService();
    await storage.backendSettings.setContextSize(16384);

    _Shown atBatch(int? batch) => _judged(
      qwen,
      backend: KoboldMemoryBackend.cuda,
      flashAttention: true,
      vramMb: vram,
      contextSize: 16384,
      batchSize: batch,
    );
    expect(
      atBatch(4096),
      isNot(atBatch(null)),
      reason: 'this machine and model must tell the two apart',
    );

    expect(_shown(facts(storage, nvidia, qwen)), atBatch(null));
    await storage.backendSettings.setBatchAutomatic(false);
    await storage.backendSettings.setBlasBatchSize(4096);
    expect(_shown(facts(storage, nvidia, qwen)), atBatch(4096));
  });

  group('the card and the launch agree', () {
    // Every kind of machine against every way the switches can stand: the
    // staged launch config says whether a card is used, and the card must
    // say the same.
    final machines = <String, HardwareInfo>{
      'an NVIDIA card': _hw('Nvidia', cuda: true),
      'an AMD card': _hw('AMD'),
      'an Intel card': _hw('Intel'),
      'a card KoboldCpp cannot use': _hw('Unknown'),
      'a Mac': _hw('Apple', metal: true),
    };
    final switches = <String, Future<void> Function(BackendSettings)>{
      'automatic': (b) async {},
      'CPU only': (b) => _chip(b),
      'Vulkan': (b) => _chip(b, vulkan: true),
      'CUDA': (b) => _chip(b, cublas: true),
      'ROCm': (b) => _chip(b, rocm: true),
      'one switch off, the rest never chosen': (b) => b.setUseCublas(false),
    };

    late StorageService storage;
    late Directory binDir;

    setUp(() async {
      storage = await createStorageService();
      binDir = Directory.systemTemp.createTempSync('fpai_facts_agree_');
    });

    tearDown(() => binDir.deleteSync(recursive: true));

    final qwen = _model('Qwen3-14B');

    for (final machine in machines.entries) {
      for (final choice in switches.entries) {
        test('${machine.key}, ${choice.key}', () async {
          final hw = machine.value;
          final b = storage.backendSettings;
          await choice.value(b);
          // As the launch sites call it: switches never chosen read as off.
          final args = await buildKoboldLaunchArgs(
            storage: storage,
            executablePath: '${binDir.path}/koboldcpp',
            modelPath: '/models/a.gguf',
            kcppsPath: null,
            mmprojPath: null,
            port: 5001,
            gpuLayers: 0,
            contextSize: b.contextSize,
            useVulkan: b.useVulkan ?? false,
            useCublas: b.useCublas ?? false,
            useMetal: b.useMetal ?? false,
            useRocm: b.useRocm ?? false,
            hardware: hw,
          );
          final staged =
              (jsonDecode(
                        File(
                          args[args.indexOf('--config') + 1],
                        ).readAsStringSync(),
                      )
                      as Map)
                  .cast<String, dynamic>();
          final launchUsesCard =
              staged.containsKey('usecuda') ||
              staged.containsKey('usevulkan') ||
              hw.hasMetal;
          final cardSaysNoCard = facts(
            storage,
            hw,
            qwen,
          ).lines.first.contains('no graphics card');
          expect(cardSaysNoCard, !launchUsesCard, reason: '$staged');
        });
      }
    }
  });
}
