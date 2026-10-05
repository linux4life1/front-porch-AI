// The MMQ timing in the preset editor sends fresh 2,000-token prompts, which
// change what KoboldCpp keeps in its cache. They go out through the same line
// as every other request that does, so a timing prompt never overlaps the
// save or the load of a chat, and a reply never overlaps a timing prompt. The
// editor times for real here, against the engine stand-in with a real
// service.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/dialogs/kcpps_editor/kcpps_editor.dart';

import '../../golden/support/fakes_services.dart';
import '../../golden/support/fakes_storage.dart';
import '../../helpers/kobold_engine_harness.dart';

class _Storage extends FakeStorageService {
  _Storage(this._bin);
  final Directory _bin;

  @override
  Directory get binDir => _bin;
}

Future<void> _until(bool Function() done) async {
  final end = DateTime.now().add(const Duration(seconds: 10));
  while (!done()) {
    if (DateTime.now().isAfter(end)) fail('waited 10 s for something');
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}

/// Long enough for a request sent too early to reach the socket.
Future<void> _aWhile() =>
    Future<void>.delayed(const Duration(milliseconds: 250));

void main() {
  late KoboldEngineHarness h;
  late KcppsEditorController editor;

  setUp(() async {
    h = await KoboldEngineHarness.start();
    addTearDown(h.dispose);
    h.kobold.debugKeeperPlan = () async => const KoboldKeeperPlan.keep(3);
    final bin = await Directory.systemTemp.createTemp('fpai editor mmq line');
    addTearDown(() => bin.delete(recursive: true));
    final file = File(p.join(bin.path, 'Mine.kcpps'));
    await file.writeAsString(
      jsonEncode({
        'contextsize': 16384,
        'usecuda': ['normal', '0'],
      }),
    );
    editor = KcppsEditorController(
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
      kobold: h.kobold,
      // The preset is taken as loaded: the engine the stand-in plays is
      // already running.
      loadTrial: (name, config) async => true,
      readFree: () async => (graphics: 23000, system: 60000),
      readModel: (_) async => (info: null, bytes: 0),
      unified: false,
      threads: () async => 4,
    );
    addTearDown(editor.dispose);
    await editor.select(file.path);
  });

  GenerationParams reply() => const GenerationParams(
    prompt: 'the chat so far',
    systemPrompt: 'RULES',
    maxLength: 16,
    kvChat: 'A',
  );

  Iterable<Object> timingPromptsSent() =>
      h.engine.arrived.where((r) => r.kind == 'generate');

  test(
    'a timing prompt waits for the save of a chat that is running',
    () async {
      final save = Completer<void>();
      h.engine.beforeAdmin = (r) =>
          r.kind == 'save' ? save.future : Future<void>.value();
      addTearDown(() {
        if (!save.isCompleted) save.complete();
      });
      await h.kobold.generateStream(reply()).toList();
      await _until(() => h.engine.arrived.any((r) => r.kind == 'save'));

      final timing = editor.timeMmq();
      await _aWhile();
      expect(
        timingPromptsSent(),
        isEmpty,
        reason: 'a timing prompt went out while the chat was being saved',
      );

      save.complete();
      await timing;
      expect(editor.mmqStatus, contains('faster here'));
      expect(
        h.engine.kinds,
        containsAllInOrder(['chat', 'save', 'generate', 'generate']),
      );
    },
  );

  test('a reply waits for the timing prompt that is running', () async {
    // The keeper has looked at the engine and holds the chat, so the reply
    // has nothing to ask the engine before it goes out.
    await h.kobold.generateStream(reply()).toList();
    await h.kobold.waitForIdle();
    h.engine.forgetLog();
    final reading = Completer<void>();
    h.engine.beforeReply = (r) =>
        r.kind == 'generate' ? reading.future : Future<void>.value();
    addTearDown(() {
      if (!reading.isCompleted) reading.complete();
    });
    final timing = editor.timeMmq();
    await _until(() => timingPromptsSent().isNotEmpty);

    final asked = h.kobold.generateStream(reply()).toList();
    await _aWhile();
    expect(
      h.engine.arrived.where((r) => r.kind == 'chat'),
      isEmpty,
      reason: 'a reply went out while a timing prompt was running',
    );

    reading.complete();
    await asked;
    await timing;
  });
}
