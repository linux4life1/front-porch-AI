// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

// A preset an older KoboldCpp saved, with old setting names and not the
// current ones, is refused wherever it would reach the engine (see
// kcpps_old_names_test), and the refusal says the fix: open it in the preset
// editor and press Save. This is that fix. The editor reads the old names
// (the form shows what the file says) and a Save writes the current ones,
// whether or not anything was edited, so the file the app will then launch
// from runs exactly as it did.

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
  late List<String?> reloadAnswers;

  setUp(() async {
    bin = await Directory.systemTemp.createTemp('fpai editor old names');
    model = p.join(bin.path, 'Big-24B-Q4_K_M.gguf');
    reloadAnswers = [];
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
      // What the running engine's reload asks first: the same check every
      // reload is built behind, over the file as it is on disk.
      reloadChat: () async {
        final problem = await koboldPresetProblem(c.path);
        reloadAnswers.add(problem);
        return problem == null ? null : KoboldLaunchResult.refused(problem);
      },
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

  /// An old-style file as KoboldCpp's launcher once wrote it, opened.
  Future<File> openOld([Map<String, dynamic> extra = const {}]) async {
    final file = File(p.join(bin.path, 'Old.kcpps'));
    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert({
        'model_param': model,
        'contextsize': 8192,
        'usecublas': ['normal', '1'],
        'blasbatchsize': 2048,
        'flashattention': false,
        'useswa': false,
        ...extra,
      }),
    );
    await c.select(file.path);
    expect(c.path, file.path);
    return file;
  }

  Future<Map<String, dynamic>> read(File file) async =>
      jsonDecode(await file.readAsString()) as Map<String, dynamic>;

  test('the form shows what the old names say', () async {
    final file = await openOld();

    expect(c.draft.backend, KoboldGpuBackend.cuda);
    expect(c.draft.gpuId, 1);
    expect(c.draft.batchSize, 2048);
    expect(c.draft.flashAttention, isFalse);
    expect(c.draft.slidingWindow, isFalse);
    expect(
      await koboldPresetProblem(file.path),
      contains('saved by an older KoboldCpp'),
      reason: 'as it was written, the app will not launch from it',
    );
  });

  test('Save with nothing edited writes the current names, and the app '
      'then launches from it', () async {
    final file = await openOld();
    expect(c.dirty, isFalse);

    expect(await c.save(), KcppsSaveResult.saved);

    final saved = await read(file);
    expect(saved['usecuda'], ['normal', '1']);
    expect(saved['batchsize'], 2048);
    expect(saved['noflashattention'], isTrue);
    expect(saved['noswa'], isTrue);
    expect(saved.containsKey('flashattention'), isFalse);
    expect(saved.containsKey('useswa'), isFalse);
    expect(saved['contextsize'], 8192, reason: 'nothing else moved');
    expect(await koboldPresetProblem(file.path), isNull);
  });

  test('Save of an edit over an old-style file writes the current names '
      'too', () async {
    final file = await openOld({'smartcache': 7});
    c.edit((d) => d.copyWith(contextSize: 32768));

    expect(await c.save(), KcppsSaveResult.saved);

    final saved = await read(file);
    expect(saved['contextsize'], 32768);
    expect(saved['smartcache'], 7, reason: 'a setting the form cannot hold');
    expect(saved['batchsize'], 2048);
    expect(await koboldPresetProblem(file.path), isNull);
  });

  test('Save and use now on an old-style preset: the reload the editor asks '
      'for finds a file that is no longer refused', () async {
    final file = await openOld();

    expect(await c.saveAndUse(), KcppsSaveResult.saved);

    expect(reloadAnswers, [null]);
    expect(c.problem, isNull);
    expect(await koboldPresetProblem(file.path), isNull);
  });

  group('timing MMQ', () {
    /// What the timing says for the old file with [extra], and the configs
    /// it loaded into the running KoboldCpp.
    Future<({String? status, List<Map<String, dynamic>> loaded})> timed(
      Map<String, dynamic> extra,
    ) async {
      final loaded = <Map<String, dynamic>>[];
      final timer = KcppsEditorController(
        storage: _Storage(bin),
        hardware: FakeHardwareService(
          hardwareInfo: HardwareInfo(
            gpuName: 'NVIDIA GeForce RTX 4090',
            vramMb: 24564,
            ramMb: 65536,
            vendor: 'Nvidia',
            hasCuda: true,
          ),
        ),
        kobold: _Running(),
        loadTrial: (name, config) async {
          loaded.add(config);
          return false;
        },
        readFree: () async => (graphics: 23000, system: 60000),
        readModel: (_) async => (info: null, bytes: 0),
        unified: false,
        threads: () async => 4,
      );
      addTearDown(timer.dispose);
      final file = await openOld(extra);
      await timer.select(file.path);
      await timer.timeMmq();
      return (status: timer.mmqStatus, loaded: loaded);
    }

    test('an old setting the form does not hold rides along, so the preset '
        'is not loaded to be timed, and the timing says why', () async {
      final run = await timed({'sdclipl': 'clip_l.safetensors'});

      expect(run.loaded, isEmpty, reason: 'KoboldCpp was never asked');
      expect(run.status, contains('saved by an older KoboldCpp'));
      expect(run.status, contains('sdclipl'));
      expect(run.status, contains('press Save'));
    });

    test('the old names the form holds are timed under their current '
        'names', () async {
      final run = await timed(const {});

      expect(run.loaded, isNotEmpty, reason: 'it got as far as loading');
      for (final config in run.loaded) {
        expect(config['noflashattention'], isTrue);
        expect(config['noswa'], isTrue);
        expect(config['batchsize'], 2048);
        expect(config.containsKey('flashattention'), isFalse);
        expect(config.containsKey('useswa'), isFalse);
      }
    });
  });
}

class _Running extends FakeKoboldService {
  @override
  bool get isRunning => true;
}
