// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

// The preset editor's context slider goes up to the length the model was
// made for, the same ceiling the Local model card uses (koboldContextMost),
// and never below the size in use. Before, it was clamped to 16,384 at the
// bottom and 262,144 at the top: an 8k model's slider ran to 16,384 and a
// model made for 1,024,000 tokens stopped at 262,144. An 8k model also gets
// the card's plain warning. Real model headers: Llama 3.2's saying 8,192,
// and Mistral Nemo, made for 1,024,000.

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
import '../../helpers/short_model_file.dart';

class _Storage extends FakeStorageService {
  _Storage(this._bin);
  final Directory _bin;

  @override
  Directory get binDir => _bin;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory bin;
  late _Storage storage;
  late String short;
  late String nemo;
  late Map<String, GGUFModelInfo?> infos;
  KcppsEditorController? c;

  setUp(() async {
    bin = await Directory.systemTemp.createTemp('fpai editor ceiling');
    storage = _Storage(bin);
    short = await writeShortModel(bin, contextLength: 8192);
    nemo = p.join(bin.path, 'Mistral-Nemo-Instruct-2407-Q4_K_M.gguf');
    infos = {
      short: await GGUFParser.getModelArchitectureInfo(short),
      nemo: await GGUFParser.getModelArchitectureInfo(
        'test/fixtures/gguf_headers/Mistral-Nemo-12B.gguf',
      ),
    };
  });

  tearDown(() async {
    c?.dispose();
    c = null;
    await bin.delete(recursive: true);
  });

  /// The editor on a preset for [model] at [context] tokens.
  Future<void> open(WidgetTester tester, String model, int context) async {
    await tester.binding.setSurfaceSize(const Size(1280, 1800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final editor = KcppsEditorController(
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
      kobold: FakeKoboldService(),
      readFree: () async => (graphics: 23000, system: 60000),
      readModel: (path) async => (info: infos[path], bytes: 0),
      unified: false,
      threads: () async => 8,
    );
    c = editor;
    await tester.runAsync(() async {
      await File(p.join(bin.path, 'Mine.kcpps')).writeAsString(
        jsonEncode({'model_param': model, 'contextsize': context}),
      );
      await editor.init();
    });
    await tester.pumpWidget(
      ChangeNotifierProvider<StorageService>.value(
        value: storage,
        child: MaterialApp(
          home: Scaffold(body: KcppsEditorDialog(controller: editor)),
        ),
      ),
    );
    await tester.pump();
  }

  double sliderTop(WidgetTester tester) =>
      tester.widget<Slider>(find.byKey(const ValueKey('kcpps-context'))).max;

  Finder warning() => find.byKey(const ValueKey('kcpps-short-model'));

  testWidgets('an 8k model: the slider stops at 8,192, with the warning', (
    tester,
  ) async {
    await open(tester, short, 8192);

    expect(sliderTop(tester), 8192);
    expect(warning(), findsOneWidget);
    expect(
      tester.widget<Text>(warning()).data,
      startsWith('This model was made for 8,192 tokens of chat.'),
    );
  });

  testWidgets('an 8k model at 32,768: the size in use stays reachable', (
    tester,
  ) async {
    await open(tester, short, 32768);

    expect(sliderTop(tester), 32768);
    expect(warning(), findsOneWidget);
  });

  testWidgets('a model made for 1,024,000 tokens can be given all of it, '
      'with no warning', (tester) async {
    await open(tester, nemo, 16384);

    expect(sliderTop(tester), 1024000);
    expect(warning(), findsNothing);
  });
}
