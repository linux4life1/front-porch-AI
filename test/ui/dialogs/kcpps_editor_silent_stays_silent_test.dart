// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

// A preset that says nothing about sliding window stays silent on every save
// until the user answers the sliding-window switch. The editor kept a silent
// file's own word only while the model in the form had a sliding window: on
// one without (or after the form's model was changed to one), a smart cache
// edit, which rewrites that whole group of settings, wrote "noswa": true and
// "nofastforward": false into a file that had said neither.
//
// Used as a person would: the whole dialog, a typed slot count, a model
// picked in the form, Save, and the file read back. Real model headers:
// Llama 3.2 has no sliding window, Gemma 3 has one.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/dialogs/kcpps_editor/kcpps_editor.dart';
import 'package:front_porch_ai/utils/utils.dart';

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

  const headers = 'test/fixtures/gguf_headers';
  const swaKeys = ['noswa', 'useswa', 'nofastforward', 'swapadding'];
  late Directory bin;
  late String gemma;
  late String llama;
  late KcppsEditorController c;
  late File file;

  setUp(() async {
    bin = await Directory.systemTemp.createTemp('fpai editor stays silent');
    gemma = p.join(bin.path, 'gemma-3-12b-it-Q4_K_M.gguf');
    llama = p.join(bin.path, 'Llama-3.2-3B-Instruct-Q4_K_M.gguf');
    final infos = {
      gemma: await GGUFParser.getModelArchitectureInfo(
        '$headers/gemma-3-12b-it.gguf',
      ),
      llama: await GGUFParser.getModelArchitectureInfo(
        '$headers/Llama-3.2-3B.gguf',
      ),
    };
    c = KcppsEditorController(
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
      kobold: FakeKoboldService(),
      readFree: () async => (graphics: 23000, system: 60000),
      readModel: (path) async => (info: infos[path], bytes: 0),
      unified: false,
      threads: () async => 8,
    );
    file = File(p.join(bin.path, 'Silent.kcpps'));
  });

  tearDown(() async {
    c.dispose();
    await bin.delete(recursive: true);
  });

  /// The silent preset on [model], opened in the whole dialog.
  Future<void> mount(WidgetTester tester, String model) async {
    await tester.binding.setSurfaceSize(const Size(1280, 1800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.runAsync(() async {
      await file.writeAsString(
        jsonEncode({'model_param': model, 'contextsize': 16384}),
      );
      await c.init();
    });
    await tester.pumpWidget(
      ChangeNotifierProvider<StorageService>.value(
        value: c.storage,
        child: MaterialApp(
          home: Scaffold(body: KcppsEditorDialog(controller: c)),
        ),
      ),
    );
    await tester.pump();
  }

  /// Types a slot count (the smart cache is saved with sliding window and
  /// fast forward), saves, and reads the file back.
  Future<Map<String, dynamic>> saveSlots(WidgetTester tester) async {
    await tester.enterText(find.byKey(const ValueKey('kcpps-slots')), '4');
    await tester.pump();
    expect(c.dirty, isTrue, reason: 'something was edited');
    await tester.tap(find.widgetWithText(KeButton, 'Save'));
    for (var i = 0; i < 100 && c.dirty; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
    }
    await tester.pump();
    expect(c.dirty, isFalse, reason: 'it was saved');
    return (jsonDecode(await tester.runAsync(file.readAsString) as String)
            as Map)
        .cast<String, dynamic>();
  }

  testWidgets('on a model without a sliding window the file stays silent', (
    tester,
  ) async {
    await mount(tester, llama);

    final saved = await saveSlots(tester);

    expect(saved['smartcache'], isNotNull, reason: 'the slots were saved');
    for (final key in swaKeys) {
      expect(saved.containsKey(key), isFalse, reason: key);
    }
  });

  testWidgets('after the form\'s model is changed to one without, it still '
      'stays silent', (tester) async {
    await mount(tester, gemma);
    await tester.runAsync(() => c.setModel(llama));
    await tester.pump();

    final saved = await saveSlots(tester);

    expect(saved['model_param'], llama);
    for (final key in swaKeys) {
      expect(saved.containsKey(key), isFalse, reason: key);
    }
  });
}
