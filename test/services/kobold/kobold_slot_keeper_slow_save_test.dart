// A chat whose save takes too long is no longer kept: its replies are not
// followed by a save that holds every other request back, nor preceded by a
// load. The engine did what it was asked, so it is not a failure of the
// keeper: nothing is remembered, and the other chats are still kept.

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

  test('a chat whose save takes too long is let go: its next reply loads '
      'nothing and is not saved, another chat is still kept, and nothing is '
      'remembered', () async {
    var slow = true;
    h.engine.beforeAdmin = (r) => r.kind == 'save' && slow
        ? Future<void>.delayed(
            kKoboldSlowSave + const Duration(milliseconds: 500),
          )
        : Future<void>.value();

    await run(_reply('A', 'a long chat so far'));
    slow = false;

    expect(h.kobold.debugKeeper.kept, 0, reason: 'the slow chat is kept');
    expect(
      h.kobold.logs.where((l) => l.contains('too long to do after every')),
      hasLength(1),
      reason: 'the log says why, once',
    );

    // A helper, then the same chat again: no load before, no save after.
    await run(const GenerationParams(prompt: 'a judge', maxLength: 8));
    h.engine.forgetLog();
    await run(_reply('A', 'a long chat so far and one line more'));
    expect(h.engine.kinds, ['chat']);

    await run(_reply('B', 'a short chat'));
    expect(h.kobold.debugKeeper.kept, 1, reason: 'a chat quick to save');

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
