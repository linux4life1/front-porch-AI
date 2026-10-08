// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

// Saving in the preset editor writes only what was edited, over the file as
// written. A save used to rebuild the whole file from the form, which cannot
// hold a second graphics card, a smart cache over 20, the sliding-window
// padding or an expert count beside automatic placement: opening a
// hand-written preset and pressing Save lost them.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/dialogs/kcpps_editor/kcpps_editor.dart';

import '../../golden/support/fakes_services.dart';
import '../../golden/support/fakes_storage.dart';

class _Storage extends FakeStorageService {
  _Storage(this._bin);
  final Directory _bin;

  @override
  Directory get binDir => _bin;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory bin;
  late String model;
  late KcppsEditorController c;

  setUp(() async {
    bin = await Directory.systemTemp.createTemp('fpai editor save');
    model = p.join(bin.path, 'Big-24B-Q4_K_M.gguf');
    c = KcppsEditorController(
      storage: _Storage(bin),
      hardware: FakeHardwareService(
        hardwareInfo: HardwareInfo(
          gpuName: 'NVIDIA GeForce GTX 1060 6GB',
          vramMb: 6144,
          ramMb: 16384,
          vendor: 'Nvidia',
          hasCuda: true,
        ),
      ),
      kobold: FakeKoboldService(),
      readFree: () async => (graphics: 5222, system: 11063),
      readModel: (_) async => (info: null, bytes: 0),
      unified: false,
      threads: () async => 4,
    );
  });

  tearDown(() async {
    c.dispose();
    await bin.delete(recursive: true);
  });

  /// [text] written by hand as `<name>.kcpps`, then opened in the editor.
  Future<File> open(String name, String text) async {
    final file = File(p.join(bin.path, '$name.kcpps'));
    await file.writeAsString(text);
    await c.select(file.path);
    expect(c.path, file.path);
    return file;
  }

  Future<File> openMap(String name, Map<String, dynamic> map) =>
      open(name, const JsonEncoder.withIndent('  ').convert(map));

  Future<Object?> save(File file) async {
    expect(await c.save(), KcppsSaveResult.saved);
    return jsonDecode(await file.readAsString());
  }

  test('changing the context keeps the second card and nothing else '
      'changes', () async {
    final file = await openMap('Two cards', {
      'model_param': model,
      'gpulayers': 99,
      'usevulkan': [0, 1],
      'tensor_split': [1, 1],
      'contextsize': 16384,
    });
    c.edit((d) => d.copyWith(contextSize: 32768));
    expect(await save(file), {
      'model_param': model,
      'gpulayers': 99,
      'usevulkan': [0, 1],
      'tensor_split': [1, 1],
      'contextsize': 32768,
    });
  });

  test('saved with no edits, a preset is the same JSON', () async {
    final map = {
      'model_param': model,
      'contextsize': 32768,
      'smartcache': 40,
      'swapadding': 512,
      'noswa': false,
      'nofastforward': true,
      'noshift': true,
      'gpulayers': 30,
      'usecuda': ['normal', '0'],
    };
    final file = await openMap('Padded', map);
    expect(await save(file), map);
  });

  test(
    'KoboldCpp\'s own export, saved with no edits, is the same JSON',
    () async {
      final text = await File(
        'test/fixtures/kcpps/koboldcpp_1_117_1_export.kcpps',
      ).readAsString();
      final file = await open('Exported', text);
      expect(await save(file), jsonDecode(text));
    },
  );

  test(
    'a batch change keeps the expert count and adds no forced fit',
    () async {
      final file = await openMap('Experts', {
        'gpulayers': -1,
        'moecpu': 20,
        'usecuda': ['normal'],
      });
      c.edit((d) => d.copyWith(batchSize: 1024));
      final saved = await save(file) as Map;
      expect(saved['moecpu'], 20);
      expect(saved['gpulayers'], -1);
      expect(saved.containsKey('autofit'), isFalse);
      expect(saved['batchsize'], 1024);
    },
  );

  test('switching CUDA to Vulkan leaves no CUDA keys behind', () async {
    // The ROCm build's key: read as the card, never written by the form.
    final file = await openMap('Switch', {
      'model_param': model,
      'usehipblas': ['normal', '0'],
      'contextsize': 16384,
    });
    c.edit((d) => d.copyWith(backend: KoboldGpuBackend.vulkan, gpuId: 0));
    final saved = await save(file) as Map;
    expect(saved.keys, isNot(contains('usecuda')));
    expect(saved.keys, isNot(contains('usecublas')));
    expect(saved.keys, isNot(contains('usehipblas')));
    expect(saved['usevulkan'], [0]);
  });
}
