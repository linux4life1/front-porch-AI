// The preset editor's speed test (MMQ on and off) loads its own preset into
// KoboldCpp for about a minute and puts chat's model back after. Meanwhile
// the app's own requests wait for chat's model: a chat reply, and the turn's
// other work (judges, tool calls). What the speed test sends, and what a load
// starts by itself (the system-role check), goes through. A real ChatService
// and the editor's real timing run against the engine stand-in; the test
// knows which model answers each request.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/dialogs/kcpps_editor/kcpps_editor.dart';

import '../../golden/support/fakes_services.dart';
import '../../golden/support/fakes_storage.dart';
import '../../helpers/fake_kobold_engine.dart';
import '../../helpers/kobold_chat_harness.dart';

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
  late KoboldChatHarness h;

  /// The model the engine runs: chat's, or the speed test's preset.
  late String model;

  /// Which model answered each request the engine served.
  late Map<FakeEngineRequest, String> servedBy;
  late int trialLoads;
  late DateTime? firstTrialLoad;

  setUp(() async {
    h = await KoboldChatHarness.start();
    model = 'chat';
    servedBy = {};
    trialLoads = 0;
    firstTrialLoad = null;
    h.engine.beforeReply = (r) async => servedBy[r] = model;
  });

  /// The editor, timing the preset it has open on the engine the chat uses.
  /// Loading the preset and putting chat back only switch the model here.
  Future<KcppsEditorController> editor() async {
    final bin = await Directory.systemTemp.createTemp('fpai speed test hold');
    addTearDown(() => bin.delete(recursive: true));
    final file = File(p.join(bin.path, 'Mine.kcpps'));
    await file.writeAsString(
      jsonEncode({
        'contextsize': 16384,
        'usecuda': ['normal', '0'],
      }),
    );
    final c = KcppsEditorController(
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
      holdForSpeedTest: h.kobold.holdForSpeedTest,
      loadTrial: (name, config) async {
        trialLoads++;
        firstTrialLoad ??= DateTime.now();
        model = 'trial';
        return true;
      },
      reloadChat: () async {
        model = 'chat';
        return null;
      },
      readFree: () async => (graphics: 23000, system: 60000),
      readModel: (_) async => (info: null, bytes: 0),
      unified: false,
      threads: () async => 4,
    );
    addTearDown(c.dispose);
    await c.select(file.path);
    return c;
  }

  /// Chat replies the engine was sent: the chat's rules come first.
  List<FakeEngineRequest> replies() => [
    for (final r in h.engine.arrived)
      if (r.kind == 'chat' && r.prompt.first == '<system>') r,
  ];

  test('a reply sent while the speed test has the engine is answered after '
      'it, by chat\'s model', () async {
    final speedTest = await editor();
    final reading = Completer<void>();
    addTearDown(() {
      if (!reading.isCompleted) reading.complete();
    });
    h.engine.beforeReply = (r) async {
      servedBy[r] = model;
      if (r.kind == 'generate') await reading.future;
    };
    final timing = speedTest.timeMmq();
    await _until(() => h.engine.arrived.any((r) => r.kind == 'generate'));

    final sending = h.chat.sendMessage('Did the rain stop?');
    await _aWhile();
    expect(replies(), isEmpty, reason: 'a reply went out during the test');

    reading.complete();
    await timing;
    await sending;
    await h.settle();
    expect(speedTest.mmqStatus, contains('faster here'));
    expect(replies(), hasLength(1));
    expect(
      servedBy[replies().single],
      'chat',
      reason: 'the speed test\'s preset answered the chat',
    );
  });

  test('the speed test waits for a reply that is running, and its save, '
      'before it loads its preset', () async {
    final speedTest = await editor();
    final writing = Completer<void>();
    addTearDown(() {
      if (!writing.isCompleted) writing.complete();
    });
    h.engine.beforeReply = (r) async {
      servedBy[r] = model;
      if (r.kind == 'chat') await writing.future;
    };
    final sending = h.chat.sendMessage('Good evening, Ada.');
    await _until(() => replies().isNotEmpty);

    final timing = speedTest.timeMmq();
    await _aWhile();
    expect(
      trialLoads,
      0,
      reason: 'the preset was loaded under a reply that was being written',
    );

    writing.complete();
    await sending;
    await timing;
    await h.settle();
    expect(trialLoads, 2);
    expect(servedBy[replies().single], 'chat');
    final saved = h.engine.of('save').first.endedAt!;
    expect(
      firstTrialLoad!.isAfter(saved),
      isTrue,
      reason: 'the preset was loaded before the reply had been saved',
    );
  });

  test('the turn\'s other work waits too: a judge and a tool call asked '
      'meanwhile are answered by chat\'s model', () async {
    final letChatGo = await h.kobold.holdForSpeedTest();
    model = 'trial';
    final judge = h.kobold
        .generateStream(
          const GenerationParams(prompt: 'a judge of the turn', maxLength: 8),
        )
        .toList();
    final tool = h.kobold.generateWithTools(
      const GenerationParams(prompt: 'a check of the turn', maxLength: 8),
      _tools,
    );
    await _aWhile();
    expect(
      h.engine.arrived,
      isEmpty,
      reason: 'the turn\'s work went to the speed test\'s preset',
    );

    model = 'chat';
    letChatGo();
    await judge;
    await tool;
    expect([for (final r in h.engine.arrived) servedBy[r]], ['chat', 'chat']);
  });

  test('what a load starts by itself, the system-role check, goes out while '
      'the app\'s requests wait', () async {
    final letChatGo = await h.kobold.holdForSpeedTest();
    model = 'trial';
    final judge = h.kobold
        .generateStream(
          const GenerationParams(prompt: 'a judge of the turn', maxLength: 8),
        )
        .toList();
    // The speed test's preset is up: the check of its model is made now.
    h.kobold.noteAdminLoadedPair(
      modelPath: '/models/Trial.gguf',
      kcppsPath: '',
    );
    await h.kobold.debugMarkModelReady().timeout(const Duration(seconds: 10));
    expect(h.engine.arrived, isNotEmpty, reason: 'the check was not made');
    expect({for (final r in h.engine.arrived) servedBy[r]}, {'trial'});

    model = 'chat';
    letChatGo();
    await judge;
    expect(servedBy[h.engine.arrived.last], 'chat');
  });

  test('Stop takes a reply held for the speed test out at once: nothing is '
      'sent, and the test\'s own prompt is not stopped', () async {
    // No clock check before the reply: the reply is what waits.
    await h.base.storage.realismSettings.setPassageOfTimeDefault(false);
    final letChatGo = await h.kobold.holdForSpeedTest();
    model = 'trial';
    final sending = h.chat.sendMessage('Did the rain stop?');
    await _until(() => h.kobold.debugRepliesWaiting == 1);
    expect(
      h.chat.activeLiveProgress?.heldBy,
      'the speed test',
      reason: 'the waiting reply\'s status does not say what it waits for',
    );

    h.chat.stopGeneration(); // the Stop button
    await sending.timeout(const Duration(seconds: 5));
    expect(h.chat.isGenerating, isFalse);
    expect(h.kobold.debugRepliesWaiting, 0);
    await _aWhile(); // time for an abort that was sent to arrive
    expect(h.engine.aborts, 0, reason: 'Stop told the engine to stop');

    model = 'chat';
    letChatGo();
    await _aWhile();
    expect(replies(), isEmpty, reason: 'the stopped reply was sent after');
    expect(h.chat.activeLiveProgress?.heldBy, isNull);
  });

  test('an abort while the speed test has the engine does not stop the '
      'test\'s prompt: nothing of the app\'s is on it', () async {
    final letChatGo = await h.kobold.holdForSpeedTest();
    h.kobold.abortGeneration(); // a check that timed out while it waited
    await _aWhile();
    expect(h.engine.aborts, 0);

    letChatGo();
    h.kobold.abortGeneration();
    await _until(() => h.engine.aborts == 1);
  });
}

const _tools = [
  {
    'type': 'function',
    'function': {
      'name': 'note',
      'description': 'Write a note.',
      'parameters': {'type': 'object', 'properties': <String, Object>{}},
    },
  },
];
