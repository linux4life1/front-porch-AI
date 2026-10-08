// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

// The preset editor times MMQ by loading the preset into the running
// KoboldCpp. A preset that makes KoboldCpp run a program or open itself to
// the internet (`mcpfile`, `remotetunnel`, ...) rides through the editor in
// the settings it does not manage, so the timing would load it. It says no,
// in plain words where the timing says how it went, and loads nothing.

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

class _Running extends FakeKoboldService {
  @override
  bool get isRunning => true;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory bin;
  late FakeStorageService storage;

  setUp(() async {
    bin = await Directory.systemTemp.createTemp('fpai editor risky trial');
    storage = _Storage(bin);
  });

  tearDown(() => bin.delete(recursive: true));

  /// What the timing says for a preset with [extra] among ordinary
  /// settings, and the configs it loaded.
  Future<({String? status, List<Map<String, dynamic>> loaded})> timed(
    Map<String, dynamic> extra,
  ) async {
    final file = File(p.join(bin.path, 'Theirs.kcpps'));
    await file.writeAsString(
      jsonEncode({
        'contextsize': 16384,
        'usecuda': ['normal', '0'],
        'noflashattention': false,
        ...extra,
      }),
    );
    final loaded = <Map<String, dynamic>>[];
    final c = KcppsEditorController(
      storage: storage,
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
    addTearDown(c.dispose);
    await c.select(file.path);
    await c.timeMmq();
    return (status: c.mmqStatus, loaded: loaded);
  }

  test('a preset that would run a program is not loaded to be timed, and the '
      'timing says why in plain words', () async {
    final run = await timed({
      'mcpfile': 'https://example.com/servers.json',
      'remotetunnel': true,
    });

    expect(run.loaded, isEmpty, reason: 'KoboldCpp was never asked to load it');
    expect(run.status, contains('mcpfile'));
    expect(run.status, contains('remotetunnel'));
    expect(run.status, contains('pick another preset'));
    expect(run.status, isNot(contains('Timing stopped')));
  });

  test(
    'a preset with those settings switched off is timed as before',
    () async {
      final run = await timed({
        'mcpfile': '',
        'remotetunnel': false,
        'rpcmode': 'disabled',
      });

      // The timing is taken as not loaded, which ends it there: it got as far
      // as loading.
      expect(run.loaded, isNotEmpty);
      expect(run.status, isNot(contains('pick another preset')));
    },
  );
}
