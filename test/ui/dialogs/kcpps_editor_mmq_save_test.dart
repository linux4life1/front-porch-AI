// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

// MMQ in the preset editor against a preset made in KoboldCpp's own
// launcher, which says "no MMQ" as a word in the CUDA list
// (`"usecuda": ["normal", "0", "nommq"]`) and not as a setting of its own.
// KoboldCpp reads that word first: with it in the list MMQ is off whatever
// `nommq` says. So the editor's MMQ switch must change the word, not only
// the setting, or it does nothing.

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
  late KcppsEditorController c;

  setUp(() async {
    bin = await Directory.systemTemp.createTemp('fpai editor mmq');
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

  /// [map] written as `Launcher.kcpps`, opened, and saved after [edit].
  Future<Map<String, dynamic>> saved(
    Map<String, dynamic> map,
    KcppsDraft Function(KcppsDraft d) edit,
  ) async {
    final file = File(p.join(bin.path, 'Launcher.kcpps'));
    await file.writeAsString(jsonEncode(map));
    await c.select(file.path);
    c.edit(edit);
    expect(await c.save(), KcppsSaveResult.saved);
    return (jsonDecode(await file.readAsString()) as Map)
        .cast<String, dynamic>();
  }

  /// Whether KoboldCpp would run [file] with MMQ: it forces it off when
  /// the CUDA list has the word, and otherwise follows `nommq`.
  bool runsMmq(Map<String, dynamic> file) {
    final list = file['usecuda'] ?? file['usecublas'];
    if (list is List && list.contains('nommq')) return false;
    return file['nommq'] != true;
  }

  Map<String, dynamic> noMmqWord({bool? key}) => {
    'contextsize': 16384,
    'usecuda': ['normal', '0', 'nommq'],
    'nommq': ?key,
  };

  test('the preset opens with MMQ off, as KoboldCpp reads it', () async {
    await File(
      p.join(bin.path, 'Launcher.kcpps'),
    ).writeAsString(jsonEncode(noMmqWord()));
    await c.select(p.join(bin.path, 'Launcher.kcpps'));
    expect(c.draft.mmq, isFalse);
  });

  test('switching MMQ on takes the word out, so it runs with MMQ', () async {
    final file = await saved(noMmqWord(), (d) => d.copyWith(mmq: true));
    expect(runsMmq(file), isTrue, reason: '$file');
  });

  test(
    'switching MMQ on holds when the file also says nommq outright',
    () async {
      final file = await saved(
        noMmqWord(key: true),
        (d) => d.copyWith(mmq: true),
      );
      expect(runsMmq(file), isTrue, reason: '$file');
    },
  );

  test('changing the card keeps MMQ off for a file that says it with the '
      'word, and nothing is added to it', () async {
    final file = await saved(noMmqWord(), (d) => d.copyWith(gpuId: 1));
    expect(runsMmq(file), isFalse, reason: '$file');
    expect((file['usecuda'] as List)[1], '1');
  });
}
