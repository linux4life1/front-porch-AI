// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

// The editor's draft controls: the model's own draft heads are offered only
// for a model whose file has them (real headers), the tokens guessed each
// step are saved, and the box starts again for another preset.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

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
  late Directory bin;
  late KcppsEditorController c;

  const heads = 'test/fixtures/gguf_headers/Qwen3.6-35B-A3B-MTP.gguf';
  const none = 'test/fixtures/gguf_headers/Qwen3.6-35B-A3B.gguf';

  Future<void> setUpWith(WidgetTester tester, String header) async {
    await tester.runAsync(() async {
      bin = await Directory.systemTemp.createTemp('fpai editor draft');
      final info = await GGUFParser.getModelArchitectureInfo(header);
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
        readModel: (_) async => (info: info, bytes: 0),
        unified: false,
        threads: () async => 8,
      );
    });
    addTearDown(() async {
      c.dispose();
      await tester.runAsync(() => bin.delete(recursive: true));
    });
  }

  Future<String> preset(
    WidgetTester tester,
    String name,
    Map<String, dynamic> map,
  ) async {
    final file = File(p.join(bin.path, '$name.kcpps'));
    await tester.runAsync(() async {
      await file.writeAsString(jsonEncode(map));
      await c.select(file.path);
    });
    return file.path;
  }

  Future<void> show(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: ListenableBuilder(
              listenable: c,
              builder: (_, _) => KcppsExtrasSection(c: c),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  final mtpCheck = find.textContaining("Use the model's own draft heads");
  Finder box() => find.byKey(const ValueKey('kcpps-draft-amount'));

  testWidgets('a model with draft heads: they are offered, and what is set '
      'is saved', (tester) async {
    await setUpWith(tester, heads);
    final file = await preset(tester, 'Heads', {
      'model_param': '/m/Qwen3.6-35B-A3B-MTP.gguf',
      'contextsize': 16384,
    });
    await show(tester);
    expect(mtpCheck, findsOneWidget);
    expect(box(), findsNothing);

    await tester.tap(mtpCheck);
    await tester.pump();
    expect(c.draft.useMtp, isTrue);
    await tester.enterText(box(), '6');
    await tester.pump();
    expect(c.draft.draftAmount, 6);

    await tester.runAsync(() => c.save());
    final saved =
        jsonDecode(await tester.runAsync(() => File(file).readAsString()) ?? '')
            as Map;
    expect(saved['usemtp'], isTrue);
    expect(saved['draftamount'], 6);
  });

  testWidgets('a model without them: not offered', (tester) async {
    await setUpWith(tester, none);
    await preset(tester, 'Plain', {
      'model_param': '/m/Qwen3.6-35B-A3B.gguf',
      'contextsize': 16384,
    });
    await show(tester);
    expect(mtpCheck, findsNothing);
  });

  testWidgets('the box starts again for another preset', (tester) async {
    await setUpWith(tester, none);
    await preset(tester, 'Three', {
      'model_param': '/m/Qwen3.6-35B-A3B.gguf',
      'draftmodel': '/m/small.gguf',
      'draftamount': 3,
    });
    await show(tester);
    expect(tester.widget<TextField>(box()).controller!.text, '3');

    await preset(tester, 'Default', {
      'model_param': '/m/Qwen3.6-35B-A3B.gguf',
      'draftmodel': '/m/small.gguf',
    });
    await tester.pump();
    expect(tester.widget<TextField>(box()).controller!.text, '');
    expect(find.text('Empty: KoboldCpp guesses 4.'), findsOneWidget);
  });
}
