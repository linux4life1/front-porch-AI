// The slot keeper inside a real KoboldService, against the engine stand-in
// on a loopback socket: what the engine is asked, in what order, and how much
// of each prompt it has to read again. A word is a token.

import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:front_porch_ai/services/services.dart';

import '../../helpers/fake_kobold_engine.dart';
import '../../helpers/kobold_engine_harness.dart';

String _words(String tag, int n) =>
    [for (var i = 0; i < n; i++) '$tag$i'].join(' ');

/// A reply of [chat]: the system rules, the history so far and a tail that
/// changes every turn, as the app builds one.
GenerationParams _reply(
  String history,
  String tail, {
  String chat = 'A',
  String rules = 'RULES',
}) => GenerationParams(
  prompt: '$history $tail',
  systemPrompt: rules,
  maxLength: 16,
  kvChat: chat,
);

/// Any other prompt: a judge, a journal pass.
GenerationParams _helper(String text) =>
    GenerationParams(prompt: text, maxLength: 16);

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

void main() {
  late KoboldEngineHarness h;
  late FakeKoboldEngine engine;
  late KoboldService kobold;

  setUp(() async {
    h = await KoboldEngineHarness.start();
    engine = h.engine;
    kobold = h.kobold;
    kobold.debugKeeperPlan = () async => const KoboldKeeperPlan.keep(3);
  });

  tearDown(() => h.dispose());

  /// Streams [params] to its end and waits for everything after it (the
  /// save) to be done.
  Future<void> run(GenerationParams params) async {
    await kobold.generateStream(params).toList();
    await kobold.waitForIdle();
  }

  List<int> readsOfChats() => [for (final r in engine.of('chat')) r.processed];

  test(
    'a helper between two replies no longer costs the chat its cache',
    () async {
      final history = _words('h', 300);

      await run(_reply(history, _words('tailA', 40)));
      await run(_helper(_words('judge', 200)));
      await run(_reply('$history ${_words('new', 30)}', _words('tailB', 40)));

      expect(engine.kinds, [
        'check',
        'chat',
        'save',
        'chat',
        'load',
        'chat',
        'save',
      ]);
      expect(
        readsOfChats().last,
        70,
        reason: 'only the 30 new words and the 40 of the new tail',
      );
    },
  );

  test('without the keeper the same turn reads the whole chat again', () async {
    kobold.debugKeeperPlan = () async =>
        const KoboldKeeperPlan.off('Not for this test.');
    final history = _words('h', 300);

    await run(_reply(history, _words('tailA', 40)));
    await run(_helper(_words('judge', 200)));
    await run(_reply('$history ${_words('new', 30)}', _words('tailB', 40)));

    expect(engine.kinds, ['chat', 'chat', 'chat']);
    expect(readsOfChats().last, greaterThan(300));
  });

  test('a regenerated reply after the judges reads nothing again', () async {
    final history = _words('h', 300);
    final tail = _words('tail', 40);

    await run(_reply(history, tail));
    await run(_helper(_words('judge', 200)));
    await run(_reply(history, tail));

    expect(readsOfChats().last, 0);
  });

  test(
    'going back to another chat loads that chat, not the last one',
    () async {
      final a = _words('a', 300);
      final b = _words('b', 300);

      await run(_reply(a, 'tail1', chat: 'A'));
      await run(_reply(b, 'tail2', chat: 'B'));
      await run(_reply('$a more', 'tail3', chat: 'A'));

      expect(engine.kinds, [
        'check',
        'chat',
        'save',
        'chat',
        'save',
        'load',
        'chat',
        'save',
      ]);
      expect(engine.of('load').single.slot, 0, reason: "A's own slot");
      expect(readsOfChats().last, lessThan(10));
    },
  );

  test(
    'a helper asked while a reply streams goes out after the save',
    () async {
      final hold = Completer<void>();
      engine.beforeReply = (r) =>
          r.promptText.contains('h0') ? hold.future : Future<void>.value();

      final reply = kobold
          .generateStream(_reply(_words('h', 50), 'tail'))
          .toList();
      while (engine.arrived.where((r) => r.kind == 'chat').isEmpty) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      // A swap holds the lock the save runs in, so the save is slow to
      // reach the engine: a helper that was let through early would be
      // first.
      unawaited(
        kobold.adminSwapLock.enqueue(
          () => Future<void>.delayed(const Duration(milliseconds: 400)),
        ),
      );
      final helper = kobold
          .generateStream(_helper('judge words here'))
          .toList();
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(engine.arrived.where((r) => r.kind == 'chat'), hasLength(1));

      hold.complete();
      await Future.wait([reply, helper]);
      await kobold.waitForIdle();

      expect(engine.kinds, ['check', 'chat', 'save', 'chat']);
      expect(engine.maxInFlight, 1);
    },
  );

  test('a reply the reader leaves part way is still saved', () async {
    engine.tokenDelay = const Duration(milliseconds: 40);
    final gotOne = Completer<void>();
    final sub = kobold.generateStream(_reply(_words('h', 100), 'tail')).listen((
      _,
    ) {
      if (!gotOne.isCompleted) gotOne.complete();
    }, onError: (_) {});
    await gotOne.future;

    final left = sub.cancel().then((_) {}, onError: (_) {});
    kobold.abortGeneration();
    await left;
    await kobold.waitForIdle();

    expect(engine.kinds, ['check', 'chat', 'save']);
    expect(
      engine.slots[0].tokens.length,
      greaterThan(100),
      reason: 'the prompt and the part of the reply there was',
    );
  });

  test(
    'a reply whose call is closed under it by Stop is still saved',
    () async {
      engine.tokenDelay = const Duration(milliseconds: 40);
      final gotOne = Completer<void>();
      final ended = Completer<void>();
      kobold
          .generateStream(_reply(_words('h', 100), 'tail'))
          .listen(
            (_) {
              if (!gotOne.isCompleted) gotOne.complete();
            },
            onError: (_) {},
            onDone: ended.complete,
          );
      await gotOne.future;

      kobold.abortGeneration();
      await ended.future;
      await kobold.waitForIdle();

      expect(engine.kinds, ['check', 'chat', 'save']);
    },
  );

  test('a reply given up on while it waits is never sent', () async {
    final hold = Completer<void>();
    engine.beforeReply = (r) =>
        r.promptText.contains('judge') ? hold.future : Future<void>.value();
    final helper = kobold.generateStream(_helper('judge words')).toList();
    while (engine.arrived.isEmpty) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }

    final sub = kobold
        .generateStream(_reply(_words('h', 50), 'tail'))
        .listen((_) {}, onError: (_) {});
    await Future<void>.delayed(const Duration(milliseconds: 50));
    final left = sub.cancel().then((_) {}, onError: (_) {});
    hold.complete();
    await helper;
    await left;
    await kobold.waitForIdle();

    expect(
      engine.of('chat').where((r) => r.promptText.contains('h0')),
      isEmpty,
      reason: 'the reader had left, so the reply was never sent',
    );
  });

  test(
    'a reply that fails is not saved, and the next one loads the earlier save',
    () async {
      engine.chatStatusFor = (prompt) => prompt.contains('BROKEN') ? 500 : null;
      final history = _words('h', 100);

      await run(_reply(history, 'tail1'));
      await expectLater(
        run(_reply('$history BROKEN', 'tail2')),
        throwsException,
      );
      await kobold.waitForIdle();
      await run(_reply(history, 'tail3'));

      expect(engine.kinds, ['check', 'chat', 'save', 'load', 'chat', 'save']);
    },
  );

  test(
    'a new load of the engine drops the chats, with no load for them',
    () async {
      final history = _words('h', 100);
      await run(_reply(history, 'tail1'));

      // What a swap does: a new model process, with empty slots and cache.
      for (final slot in engine.slots) {
        slot.tokens = [];
      }
      engine.live = [];
      kobold.noteAdminLoadedPair(modelPath: '/models/other.gguf');
      engine.forgetLog();

      await run(_reply(history, 'tail2'));

      expect(engine.kinds, ['check', 'chat', 'save']);
    },
  );

  test('a tool call that names a chat is still only a helper', () async {
    final history = _words('h', 100);
    await run(_reply(history, 'tail1'));
    engine.forgetLog();

    await kobold.generateWithTools(
      GenerationParams(prompt: 'note this', kvChat: 'A'),
      _tools,
    );
    await kobold.waitForIdle();

    expect(engine.kinds, ['chat'], reason: 'no save, load or check for it');
    engine.forgetLog();
    await run(_reply(history, 'tail2'));
    expect(engine.kinds, [
      'load',
      'chat',
      'save',
    ], reason: 'the tool call changed the cache, so the chat is loaded back');
  });

  test('a coding session on the engine makes the keeper wait', () async {
    final history = _words('h', 100);
    await run(_reply(history, 'tail1'));
    engine.forgetLog();

    await kobold.keepLoadedFor(() => run(_reply(history, 'tail2')));
    expect(engine.kinds, ['chat'], reason: 'nothing saved or loaded meanwhile');
    engine.forgetLog();

    await run(_reply(history, 'tail3'));
    expect(engine.kinds, ['load', 'chat', 'save']);
  });

  test(
    'an engine that will not keep chats leaves everything as it was',
    () async {
      engine.adminOn = false;
      final history = _words('h', 100);

      await run(_reply(history, 'tail1'));
      await run(_helper('judge words'));
      await run(_reply(history, 'tail2'));

      expect(engine.kinds, ['check', 'chat', 'chat', 'chat']);
    },
  );

  test('a plan that keeps nothing never asks the engine for a slot', () async {
    kobold.debugKeeperPlan = () async =>
        const KoboldKeeperPlan.off('Not for this model.');

    await run(_reply(_words('h', 100), 'tail1'));
    await run(_reply(_words('h', 100), 'tail2'));

    expect(engine.kinds, ['chat', 'chat']);
    expect(
      kobold.logs.where((l) => l.contains('Not for this model.')),
      hasLength(1),
      reason: 'said once for the load, not at every reply',
    );
  });

  group('when the keeper fails', () {
    late Directory folder;

    setUp(() async {
      folder = Directory.systemTemp.createTempSync('fpai keeper failure');
      addTearDown(() => folder.delete(recursive: true));
      // The engine as a start leaves it: a program with a version record.
      final exe = File(p.join(folder.path, 'koboldcpp'))
        ..writeAsBytesSync([1, 2, 3]);
      await KoboldBinaryVersion.write(folder.path, version: '1.117.1', size: 3);
      kobold.debugEngineFile = exe.path;
    });

    Future<void> failASave() async {
      engine.failSaves = true;
      await run(_reply(_words('h', 50), 'tail'));
      // The remembering runs on its own after the step aside.
      for (var i = 0; i < 50 && !_remembered(h); i++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
    }

    test('in auto mode the next start of this model on this engine is told to '
        'use the smart cache, and the log says so once', () async {
      kobold.noteAdminLoadedPair(
        modelPath: '/models/Qwen3-14B.gguf',
        kcppsPath: '',
      );

      await failASave();

      expect(
        h.storage.backendSettings.keeperFailedFor('1.117.1', 'Qwen3-14B.gguf'),
        isTrue,
      );
      expect(
        kobold.logs.where((l) => l.contains('smart cache will look after')),
        hasLength(1),
      );
    });

    test('a preset is left as its owner wrote it', () async {
      kobold.noteAdminLoadedPair(
        modelPath: '/models/Qwen3-14B.gguf',
        kcppsPath: '/presets/mine.kcpps',
      );

      await failASave();
      await Future<void>.delayed(const Duration(milliseconds: 100));

      expect(
        h.storage.backendSettings.keeperFailedFor('1.117.1', 'Qwen3-14B.gguf'),
        isFalse,
      );
    });

    test('an engine that only refused to be asked is not remembered as a '
        'failure of the keeper', () async {
      kobold.noteAdminLoadedPair(
        modelPath: '/models/Qwen3-14B.gguf',
        kcppsPath: '',
      );
      // Chats somebody else already holds are left alone: not a failure.
      engine.slots[2].tokens = ['x'];

      await run(_reply(_words('h', 50), 'tail'));
      await Future<void>.delayed(const Duration(milliseconds: 100));

      expect(
        h.storage.backendSettings.keeperFailedFor('1.117.1', 'Qwen3-14B.gguf'),
        isFalse,
      );
    });

    test('a first look that finds admin off is not remembered either: it may '
        'be a blip, and the next load looks again', () async {
      kobold.noteAdminLoadedPair(
        modelPath: '/models/Qwen3-14B.gguf',
        kcppsPath: '',
      );
      engine.adminOn = false;

      await run(_reply(_words('h', 50), 'tail'));
      await Future<void>.delayed(const Duration(milliseconds: 100));

      expect(
        h.storage.backendSettings.keeperFailedFor('1.117.1', 'Qwen3-14B.gguf'),
        isFalse,
      );
      expect(
        kobold.logs.where((l) => l.contains('smart cache will look after')),
        isEmpty,
        reason: 'no word about the next start: nothing was decided',
      );
    });
  });
}

bool _remembered(KoboldEngineHarness h) =>
    h.storage.backendSettings.keeperFailedFor('1.117.1', 'Qwen3-14B.gguf');
