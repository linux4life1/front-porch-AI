// A chat that costs more to keep than to read again is not kept: its replies
// are not followed by a save that holds every other request back, nor
// preceded by a load. What decides is the speed the engine itself says it
// reads at, through the real service. Not a failure of the keeper: nothing is
// remembered, and the other chats are still kept. A save that never answers
// lets every chat go for the load, also without being remembered.

import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:front_porch_ai/services/services.dart';

import '../../helpers/kobold_engine_harness.dart';

GenerationParams _reply(String chat, String text) => GenerationParams(
  prompt: text,
  systemPrompt: 'RULES',
  maxLength: 16,
  kvChat: chat,
);

void main() {
  late KoboldEngineHarness h;

  setUp(() async {
    h = await KoboldEngineHarness.start();
    addTearDown(h.dispose);
    h.kobold.debugKeeperPlan = () async => const KoboldKeeperPlan.keep(3);
    // An auto-mode start of a model the app read, on an engine whose version
    // is known: a failure of the keeper would be remembered for this pair.
    final folder = await Directory.systemTemp.createTemp('fpai slow save');
    addTearDown(() => folder.delete(recursive: true));
    final exe = File(p.join(folder.path, 'koboldcpp'))
      ..writeAsBytesSync([1, 2, 3]);
    await KoboldBinaryVersion.write(folder.path, version: '1.117.1', size: 3);
    h.kobold
      ..debugEngineFile = exe.path
      ..noteAdminLoadedPair(modelPath: '/models/Qwen3-14B.gguf', kcppsPath: '');
  });

  /// Streams [params] to its end and waits for the save after it.
  Future<void> run(GenerationParams params) async {
    await h.kobold.generateStream(params).toList();
    await h.kobold.waitForIdle();
  }

  bool remembered() =>
      h.storage.backendSettings.keeperFailedFor('1.117.1', 'Qwen3-14B.gguf');

  test('the engine\'s own speed decides: the same slow saves let a short chat '
      'go and keep a long one, and nothing is remembered', () async {
    // What KoboldCpp prints after a request: 2,000 tokens read in 2 s.
    h.kobold.debugEngineSaid(
      'Processed:2000 in 2.00s (1000.00T/s), '
      'Generated:16/16 in 0.50s (32.00T/s)\n',
    );
    h.engine.beforeAdmin = (r) => r.kind == 'save'
        ? Future<void>.delayed(const Duration(milliseconds: 400))
        : Future<void>.value();
    final long = [for (var i = 0; i < 5000; i++) 'w$i'].join(' ');

    // The first saves only make the slots; the second ones decide.
    for (var turn = 0; turn < 2; turn++) {
      await run(_reply('short', 'a short chat, turn $turn'));
      await run(_reply('long', '$long turn $turn'));
      await run(const GenerationParams(prompt: 'a judge', maxLength: 8));
    }

    expect(h.kobold.debugKeeper.kept, 1);
    expect(
      h.kobold.logs.where((l) => l.contains('to read it again')),
      hasLength(1),
      reason: 'the log says why, once',
    );
    // The long chat loads back and is saved; the short one is neither.
    h.engine.forgetLog();
    await run(_reply('long', '$long turn 2'));
    await run(_reply('short', 'a short chat, turn 2'));
    expect(h.engine.kinds, ['load', 'chat', 'save', 'chat']);

    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(remembered(), isFalse);
    expect(
      h.kobold.logs.where((l) => l.contains('smart cache will look after')),
      isEmpty,
    );
  });

  test('a save that does not answer in time lets every chat go for the load, '
      'since what its slot holds is not known; it is not a failure', () async {
    final failures = <String>[];
    final logs = <String>[];
    final keeper = KoboldSlotKeeper(
      api: KoboldHttpSlotApi(
        () => h.engine.baseUrl,
        timeout: const Duration(milliseconds: 300),
      ),
      loadGeneration: () => 1,
      plan: () async => const KoboldKeeperPlan.keep(3),
      underSwapLock: <T>(work) => work(),
      log: logs.add,
      onFailure: failures.add,
    );
    final held = Completer<void>();
    addTearDown(() {
      if (!held.isCompleted) held.complete();
    });
    h.engine.beforeAdmin = (r) => r.kind == 'save' && !held.isCompleted
        ? held.future
        : Future<void>.value();
    h.engine.live = ['a', 'long', 'chat'];

    await keeper.chatStart('A');
    await keeper.chatEnd('A', ok: true);

    expect(failures, isEmpty, reason: 'remembered as a failure');
    expect(keeper.kept, 0);
    expect(keeper.chats, 0, reason: 'still keeping the other chats');
    expect(logs.last, contains('did not finish saving a chat in time'));

    // The engine finishes the save it was asked for in the end; nothing more
    // is asked of it for this load.
    held.complete();
    for (var i = 0; i < 200 && h.engine.of('save').first.endedAt == null; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    h.engine.forgetLog();
    await keeper.chatStart('B');
    h.engine.live = ['a', 'short', 'one'];
    await keeper.chatEnd('B', ok: true);
    expect(h.engine.arrived, isEmpty);
    expect(failures, isEmpty);
  });
}
