// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

// Putting a preset in the editor, whichever way: from the list, from a file
// anywhere, or a new one from the app's own settings. One load reads
// everything first and puts it in the form in one step, so two loads in a
// row never leave a mixture (the path of one with the form of the other,
// which a save then wrote into the wrong file), and a new preset is sized on
// its own form. Llama 3.2 3B (its real header, grown to its real size as a
// sparse file) on a 6 GB GTX 1060 with 11 GB of system memory free.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/dialogs/kcpps_editor/kcpps_editor.dart';
import 'package:front_porch_ai/ui/dialogs/kcpps_editor/kcpps_editor_controller.dart';
import 'package:front_porch_ai/ui/dialogs/kcpps_editor/kcpps_fit_panel.dart';
import 'package:front_porch_ai/ui/dialogs/kcpps_editor/kcpps_preset_list.dart';
import 'package:front_porch_ai/utils/gguf_parser.dart';

import '../../golden/support/fakes_services.dart';
import '../../golden/support/fakes_storage.dart';

class _Storage extends FakeStorageService {
  _Storage(this._bin);
  final Directory _bin;

  @override
  Directory get binDir => _bin;
}

typedef _Read = ({GGUFModelInfo? info, int bytes});

final _gtx1060 = HardwareInfo(
  gpuName: 'NVIDIA GeForce GTX 1060 6GB',
  vramMb: 6144,
  ramMb: 16384,
  vendor: 'Nvidia',
  hasCuda: true,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory bin;
  late _Storage storage;
  late _Read read;
  late String model;

  setUp(() async {
    bin = await Directory.systemTemp.createTemp('fpai editor load');
    storage = _Storage(bin);
    const fx = 'test/fixtures/gguf_headers/Llama-3.2-3B';
    final side = jsonDecode(await File('$fx.json').readAsString()) as Map;
    model = p.join(bin.path, 'Llama-3.2-3B-Instruct-Q4_K_M.gguf');
    final raf = await File(model).open(mode: FileMode.write);
    await raf.writeFrom(await File('$fx.gguf').readAsBytes());
    await raf.setPosition((side['fixture_file_bytes'] as int) - 1);
    await raf.writeByte(0);
    await raf.close();
    read = (
      info: await GGUFParser.getModelArchitectureInfo(model),
      bytes: await File(model).length(),
    );
    await storage.backendSettings.setLastUsedModelPath(model);
    await storage.backendSettings.setContextSize(16384);
  });

  tearDown(() => bin.delete(recursive: true));

  KcppsEditorController controller({
    Future<_Read> Function(String path)? readModel,
  }) => KcppsEditorController(
    storage: storage,
    hardware: FakeHardwareService(hardwareInfo: _gtx1060),
    kobold: FakeKoboldService(),
    readFree: () async => (graphics: 5222, system: 11063),
    readModel: readModel ?? (_) async => read,
    unified: false,
    threads: () async => 4,
  );

  Future<String> preset(String name, Map<String, dynamic> map) async {
    final file = File(p.join(bin.path, '$name.kcpps'));
    await file.writeAsString(jsonEncode({'model_param': model, ...map}));
    return file.path;
  }

  group('a new preset', () {
    test('is sized on its own form, not on the one before', () async {
      final c = controller();
      addTearDown(c.dispose);
      await c.init();
      expect(c.draft.backend, KoboldGpuBackend.cuda);
      expect(c.draft.slots, 3, reason: 'the card is there, there is room');

      // A preset made for a chat length this machine has no room for.
      final big = await preset('Big', {'contextsize': 65536});
      await c.select(big);
      expect(c.suggestedSlots!.slots, 0);

      await c.newFromSettings();
      expect(c.draft.contextSize, 16384);
      expect(c.draft.slots, 3);
    });

    test('starts with no draft model of the one before', () async {
      final helper = p.join(bin.path, 'small.gguf');
      final c = controller();
      addTearDown(c.dispose);
      await c.select(await preset('Fast', {'draftmodel': helper}));
      expect(c.draftModelInfo, isNotNull);
      expect(c.draftModelBytes, isNotNull);

      await c.newFromSettings();
      expect(c.draft.draftModelPath, isEmpty);
      expect(c.draftModelInfo, isNull);
      expect(c.draftModelBytes, isNull);
    });
  });

  group('opening presets', () {
    test('a second one opened while the first is still reading leaves the '
        'second whole, not a mixture', () async {
      final slowModel = p.join(bin.path, 'A-slow.gguf');
      final a = await preset('A', {
        'model_param': slowModel,
        'contextsize': 16384,
      });
      final b = await preset('B', {'contextsize': 32768});
      final reading = Completer<void>();
      Completer<void>? hold;
      final c = controller(
        readModel: (path) async {
          final wait = hold;
          if (path == slowModel && wait != null) {
            reading.complete();
            await wait.future;
          }
          return read;
        },
      );
      addTearDown(c.dispose);
      await c.init();

      // A's model is slow to read; B's is not.
      final slow = hold = Completer<void>();
      final opening = c.select(a);
      await reading.future;
      await c.select(b);
      slow.complete();
      await opening;

      expect(c.path, b);
      expect(c.draft.name, 'B');
      expect(c.draft.modelPath, model);
      expect(c.draft.contextSize, 32768);
      expect(c.dirty, isFalse);
    });

    test('a file from anywhere is not the file being edited', () async {
      final c = controller();
      addTearDown(c.dispose);
      final file = await preset('Mine', {'contextsize': 32768});
      await c.select(file);
      expect(c.path, file);
      expect(c.dirty, isFalse);

      await c.openFile(file);
      expect(c.path, isNull);
      expect(c.dirty, isTrue, reason: 'not saved among the presets yet');
      expect(c.draft.contextSize, 32768);
    });

    test(
      'a preset that cannot be read changes nothing but the problem',
      () async {
        final c = controller();
        addTearDown(c.dispose);
        final good = await preset('Good', {'contextsize': 32768});
        await c.select(good);
        final broken = File(p.join(bin.path, 'Broken.kcpps'))
          ..writeAsStringSync('not json at all');
        await c.select(broken.path);
        expect(c.problem, isNotNull);
        expect(c.path, good);
        expect(c.draft.contextSize, 32768);
      },
    );
  });

  group('the model file', () {
    test('a model chosen is being read, then read or not', () async {
      final c = controller(
        readModel: (path) async {
          if (path.endsWith('gone.gguf')) {
            throw FileSystemException('No such file', path);
          }
          return read;
        },
      );
      addTearDown(c.dispose);
      await c.select(await preset('Mine', {}));
      expect(c.modelUnreadable, isFalse);

      final gone = p.join(bin.path, 'gone.gguf');
      final choosing = c.setModel(gone);
      expect(c.modelReading, isTrue);
      expect(c.modelUnreadable, isFalse, reason: 'still being read');
      await choosing;
      expect(c.modelReading, isFalse);
      expect(c.modelUnreadable, isTrue);
      expect(c.problem, isNull, reason: 'told in plain words where it shows');

      await c.setModel(model);
      expect(c.modelUnreadable, isFalse);
    });

    test(
      'a read that another load overtook does not change the form',
      () async {
        final slow = Completer<_Read>();
        final c = controller(
          readModel: (path) =>
              path.endsWith('slow.gguf') ? slow.future : Future.value(read),
        );
        addTearDown(c.dispose);
        final file = await preset('Mine', {});
        await c.select(file);

        final choosing = c.setModel(p.join(bin.path, 'slow.gguf'));
        await c.select(file);
        slow.complete((info: null, bytes: 1));
        await choosing;
        expect(c.draft.modelPath, model);
        expect(c.info, isNotNull);
        expect(c.modelUnreadable, isFalse);
      },
    );
  });

  group('in the dialog', () {
    Future<KcppsEditorController> open(WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(1280, 1600));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.runAsync(() async {
        await preset('Alpha', {'batchsize': 1024});
        await preset('Beta', {'batchsize': 1024});
      });
      final c = controller();
      await tester.runAsync(c.init);
      addTearDown(c.dispose);
      await tester.pumpWidget(
        ChangeNotifierProvider<StorageService>.value(
          value: storage,
          child: MaterialApp(
            home: Scaffold(body: KcppsEditorDialog(controller: c)),
          ),
        ),
      );
      await tester.pump();
      return c;
    }

    testWidgets('a wrong number typed in one preset is not carried to the '
        'next, even when the next holds the same number', (tester) async {
      final c = await open(tester);
      expect(c.draft.name, 'Alpha');
      final box = find.byKey(const ValueKey('kcpps-batch'));
      await tester.enterText(box, '5');
      await tester.pump();
      expect(find.text('A batch is 16 to 8,192 tokens.'), findsOneWidget);

      await tester.tap(
        find.descendant(
          of: find.byType(KcppsPresetList),
          matching: find.text('Beta'),
        ),
      );
      for (var i = 0; i < 20 && c.draft.name != 'Beta'; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        await tester.pump(const Duration(milliseconds: 10));
      }
      expect(c.draft.name, 'Beta');
      expect(tester.widget<TextField>(box).controller!.text, '1024');
      expect(find.text('A batch is 16 to 8,192 tokens.'), findsNothing);
    });

    testWidgets('the panel says whether the model file is being read, '
        'cannot be, or is fine', (tester) async {
      final gate = Completer<_Read>();
      final c = controller(
        readModel: (path) {
          if (path.endsWith('gone.gguf')) return gate.future;
          return Future.value(read);
        },
      );
      addTearDown(c.dispose);
      await tester.runAsync(() async {
        await c.select(
          await preset('Mine', {
            'usecuda': ['normal', '0'],
          }),
        );
      });
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: ListenableBuilder(
                listenable: c,
                builder: (_, _) => KcppsFitPanel(c: c),
              ),
            ),
          ),
        ),
      );
      expect(find.byKey(const ValueKey('kcpps-verdict')), findsOneWidget);

      unawaited(c.setModel(p.join(bin.path, 'gone.gguf')));
      await tester.pump();
      expect(find.text('Reading the model file…'), findsOneWidget);

      gate.completeError(FileSystemException('No such file', 'gone.gguf'));
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pump();
      expect(find.text('Reading the model file…'), findsNothing);
      expect(
        find.textContaining('The model file could not be read'),
        findsOneWidget,
      );
    });
  });
}
