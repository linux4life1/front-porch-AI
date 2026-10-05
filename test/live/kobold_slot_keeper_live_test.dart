// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

// The slot keeper against a real KoboldCpp: ten chat turns with helper
// prompts (a judge, a needs check, a tool call) between them, then one
// regenerated reply, with the keeper off and on. What the engine says it
// read ("Processed:N" in its own log) is the measure: with the keeper off
// every reply after a helper reads the whole chat again, with it on a reply
// reads only what is new. Run with:
//   KOBOLD_LIVE_BIN=… KOBOLD_LIVE_MODEL=… flutter test --concurrency=1 \
//     --tags kobold_live test/live/kobold_slot_keeper_live_test.dart
// KOBOLD_LIVE_REPORT names a file the tables are also written to: tokens read,
// time to the first token, and how long the save after each reply held the
// line. The hybrid test needs KOBOLD_LIVE_HYBRID_MODEL, a small model with
// recurrent layers.

@Tags(['kobold_live'])
library;

import 'dart:io';
import 'dart:math';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/chat_db_teardown.dart';
import 'live_engine.dart';

const _slow = Timeout(Duration(minutes: 40));

const _words = [
  'porch',
  'lantern',
  'river',
  'quiet',
  'amber',
  'orchard',
  'whisper',
  'ledger',
  'kettle',
  'morning',
  'garden',
  'letter',
  'thread',
  'copper',
  'meadow',
  'harbor',
  'candle',
  'window',
  'ribbon',
  'stone',
  'market',
  'evening',
  'violin',
  'cedar',
  'pocket',
  'journal',
  'lantern',
  'bridge',
  'summer',
  'winter',
  'doorway',
  'clock',
  'feather',
  'mirror',
  'saddle',
  'travel',
  'sparrow',
  'blanket',
  'harvest',
  'story',
];

/// Text that is the same on every run, so what a turn adds can be told
/// apart from what a run does to it.
String _text(Random r, int words) => [
  for (var i = 0; i < words; i++) _words[r.nextInt(_words.length)],
].join(' ');

class _Rig {
  _Rig(
    this.root,
    this.storage,
    this.kobold,
    this.hardware,
    this.exe,
    this.port,
  );

  final Directory root;
  final StorageService storage;
  final KoboldService kobold;
  final HardwareService hardware;
  final String exe;
  final int port;
}

/// One request the script made, as the engine reported it.
class _Seen {
  _Seen(
    this.reply,
    this.promptTokens,
    this.processed,
    this.firstTokenMs,
    this.saveMs,
  );
  final String reply;
  final int promptTokens;
  final int processed;
  final int firstTokenMs;

  /// How long the line was held after the reply, for the keeper's save.
  final int saveMs;
}

class _Run {
  final List<_Seen> chats = [];
  final List<int> newTokens = [];
  final List<int> tailTokens = [];
  Map<String, dynamic> staged = {};
  String log = '';
}

final _processedLine = RegExp(r'Processed:(\d+) in ([\d.]+)s');

List<int> _processed(KoboldService kobold) => [
  for (final line in kobold.logs)
    if (_processedLine.firstMatch(line) case final m?) int.parse(m.group(1)!),
];

void main() {
  late List<Directory> roots;

  setUpAll(() {
    HttpOverrides.global = null;
    roots = [];
  });

  tearDownAll(() async {
    for (final root in roots) {
      await stopLiveEnginesUnder(root);
      if (root.existsSync()) await root.delete(recursive: true);
    }
  });

  /// What KoboldCpp printed about the graphics it took, so a table says
  /// which card and path its numbers are from.
  String engineSaid(KoboldService kobold) {
    final lines = [
      for (final l in kobold.logs)
        if (RegExp(
          r'ggml_vulkan: \d =|ggml_cuda_init|Device \d+:|Initializing dynamic '
          r'library|Using Metal|offloaded \d+/\d+ layers',
        ).hasMatch(l))
          l.trim(),
    ];
    return lines.take(6).map((l) => '  engine: $l\n').join();
  }

  Future<_Rig> startRig(String model) async {
    final temp = await Directory.systemTemp.createTemp('fpai keeper live');
    final root = Directory(temp.resolveSymbolicLinksSync());
    roots.add(root);
    TestWidgetsFlutterBinding.ensureInitialized();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async => call.method == 'getApplicationDocumentsDirectory'
              ? root.path
              : null,
        );
    SharedPreferences.setMockInitialValues({});
    final storage = StorageService();
    await storage.initialized;
    final b = storage.backendSettings;
    await b.setBackendType('kobold');
    await b.setContextSize(16384);
    await b.setLastUsedModelPath(model);
    // Detection waits for the app's first frame, which a test never has.
    final hardware = HardwareService();
    await hardware.detectHardware();
    final kobold = KoboldService(storage)
      ..hardwareInfo = (() => hardware.hardwareInfo)
      ..readFreeMemory = (() => hardware.readFreeMemory());
    final exe = await copyEngineInto(storage.binDir);
    final port = await freePort();
    kobold.setBaseUrl('http://127.0.0.1:$port');
    expect((await kobold.launch(exe, port: port)).started, isTrue);
    await waitForLiveModel(port);
    for (var i = 0; i < 240 && !kobold.modelReady; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 500));
    }
    expect(kobold.modelReady, isTrue);
    // The system-role check sends its three requests as soon as the model
    // is up; let them finish, so none is taken for the script's.
    var seen = -1;
    while (seen != _processed(kobold).length) {
      seen = _processed(kobold).length;
      await Future<void>.delayed(const Duration(seconds: 2));
    }
    return _Rig(root, storage, kobold, hardware, exe, port);
  }

  Future<void> stopRig(_Rig rig) async {
    await rig.kobold.stopKobold();
    rig.hardware.dispose();
  }

  Map<String, dynamic> stagedChat(_Rig rig) =>
      (readKcpps(
                File(
                  p.join(koboldAdminDirFor(rig.storage), kStagedChatConfig),
                ).readAsStringSync(),
              )
              as KcppsOk)
          .raw;

  /// Runs [start], waits for the save that follows a chat reply, and reads
  /// the engine's own account of the request from its log.
  Future<({String reply, int processed, int firstTokenMs, int saveMs})> ask(
    _Rig rig,
    Stream<String> Function() start,
  ) async {
    final kobold = rig.kobold;
    final before = _processed(kobold).length;
    final sw = Stopwatch()..start();
    int? first;
    final reply = StringBuffer();
    await for (final chunk in start()) {
      first ??= sw.elapsedMilliseconds;
      reply.write(chunk);
    }
    final firstTokenMs = first ?? sw.elapsedMilliseconds;
    // The line is held until the keeper's save is done: that wait is the save.
    final saving = Stopwatch()..start();
    await kobold.waitForIdle();
    final saveMs = saving.elapsedMilliseconds;
    for (var i = 0; i < 100 && _processed(kobold).length <= before; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    final now = _processed(kobold);
    expect(now.length, before + 1, reason: 'one request, one line in the log');
    return (
      reply: reply.toString().trim(),
      processed: now.last,
      firstTokenMs: firstTokenMs,
      saveMs: saveMs,
    );
  }

  /// Ten chat turns with three helpers after each, then a regenerated reply.
  Future<_Run> script(_Rig rig, {required int turns}) async {
    final kobold = rig.kobold;
    final r = Random(7);
    final rules = _text(r, 1100);
    final run = _Run()
      ..staged = stagedChat(rig)
      ..log = '';
    var history = '';
    String? lastPrompt;

    GenerationParams chat(String userContent) => GenerationParams(
      prompt: userContent,
      systemPrompt: rules,
      maxLength: 60,
      temperature: 0.2,
      kvChat: 'A',
    );

    for (var t = 1; t <= turns; t++) {
      final line = 'You: ${_text(r, 100)}\n';
      final tail = '[This turn: ${_text(r, 220)}]';
      final prompt = '$history$line\n$tail';
      lastPrompt = prompt;
      final promptTokens = await kobold.countTokens('$rules $prompt');
      final added = await kobold.countTokens(
        t == 1 ? line : 'Char: ${run.chats.last.reply}\n$line',
      );
      final seen = await ask(rig, () => kobold.generateStream(chat(prompt)));
      run.chats.add(
        _Seen(
          seen.reply,
          promptTokens,
          seen.processed,
          seen.firstTokenMs,
          seen.saveMs,
        ),
      );
      run.newTokens.add(added);
      run.tailTokens.add(await kobold.countTokens(tail));
      history = '$history${line}Char: ${seen.reply}\n';

      // Three helpers with prompts of their own, none starting like the chat.
      for (final (i, size) in [(0, 600), (1, 900), (2, 1200)]) {
        final words = '$history ${_text(r, size)}'.split(' ');
        final excerpt = words
            .sublist(max(0, words.length - size * 3 ~/ 4))
            .join(' ');
        if (i < 2) {
          await ask(
            rig,
            () => kobold.generateStream(
              GenerationParams(
                prompt: 'Helper $i of turn $t. Answer in one word.\n$excerpt',
                maxLength: 12,
                temperature: 0.0,
              ),
            ),
          );
        } else {
          final before = _processed(kobold).length;
          await kobold.generateWithTools(
            GenerationParams(
              prompt: 'Helper $i of turn $t. Note one fact.\n$excerpt',
              maxLength: 24,
              temperature: 0.0,
            ),
            [
              {
                'type': 'function',
                'function': {
                  'name': 'note',
                  'description': 'Write one fact down.',
                  'parameters': {
                    'type': 'object',
                    'properties': {
                      'fact': {'type': 'string'},
                    },
                  },
                },
              },
            ],
          );
          await kobold.waitForIdle();
          for (var w = 0; w < 100 && _processed(kobold).length <= before; w++) {
            await Future<void>.delayed(const Duration(milliseconds: 100));
          }
        }
      }
    }

    // The regenerated reply: the same prompt as the last turn, after helpers.
    final promptTokens = await kobold.countTokens('$rules $lastPrompt');
    final seen = await ask(rig, () => kobold.generateStream(chat(lastPrompt!)));
    run.chats.add(
      _Seen(
        'regen',
        promptTokens,
        seen.processed,
        seen.firstTokenMs,
        seen.saveMs,
      ),
    );
    run.log = kobold.logs.join('\n');
    return run;
  }

  String table(Map<String, _Run> runs) {
    final names = runs.keys.toList();
    final b = StringBuffer()
      ..writeln(
        'turn   prompt  '
        '${names.map((n) => '${n.padLeft(10)} read   first token   save').join('   ')}',
      );
    final rows = runs.values.first.chats.length;
    for (var i = 0; i < rows; i++) {
      final label = i == rows - 1 ? 'regen' : '${i + 1}';
      final prompt = runs.values.first.chats[i].promptTokens;
      final cells = [
        for (final run in runs.values)
          '${run.chats[i].processed.toString().padLeft(10)}   '
              '${'${run.chats[i].firstTokenMs} ms'.padLeft(11)}   '
              '${'${run.chats[i].saveMs} ms'.padLeft(7)}',
      ];
      b.writeln(
        '${label.padRight(6)} ${'$prompt'.padLeft(6)}  ${cells.join('   ')}',
      );
    }
    return b.toString();
  }

  void report(String text) {
    // ignore: avoid_print
    print(text);
    final file = Platform.environment['KOBOLD_LIVE_REPORT'];
    if (file != null && file.isNotEmpty) {
      File(file).writeAsStringSync(text, mode: FileMode.append);
    }
  }

  test(
    'ten chat turns with helpers between: the keeper leaves only what is new '
    'to be read, and a regenerated reply reads nothing',
    () async {
      final runs = <String, _Run>{};

      final off = await startRig(liveEngineModel);
      off.kobold.debugKeeperPlan = () async =>
          const KoboldKeeperPlan.off('Switched off for this run.');
      runs['keeper off'] = await script(off, turns: 10);
      await stopRig(off);

      final on = await startRig(liveEngineModel);
      runs['keeper on'] = await script(on, turns: 10);
      final keptChats = on.kobold.debugKeeper.chats;
      final said = engineSaid(on.kobold);
      await stopRig(on);

      final engine = p.basename(liveEngineBin);
      report(
        '\n$engine with ${p.basename(liveEngineModel)}\n$said${table(runs)}',
      );

      final a = runs['keeper off']!;
      final b = runs['keeper on']!;
      expect(a.staged.containsKey('smartcache'), isFalse);
      expect(b.staged.containsKey('smartcache'), isFalse);
      expect(keptChats, greaterThanOrEqualTo(1));
      expect(
        a.log,
        isNot(contains('KV Load SaveState')),
        reason: 'with the keeper off nothing is loaded back',
      );
      expect(b.log, contains('KV Save State 0'));
      expect(b.log, contains('KV Load SaveState 0'));
      for (var t = 1; t < 10; t++) {
        final off = a.chats[t];
        final on = b.chats[t];
        // The turn's own new text, its changing tail, and some slack for how
        // the join of old and new text tokenizes.
        expect(
          on.processed,
          lessThanOrEqualTo(b.newTokens[t] + b.tailTokens[t] + 64),
          reason: 'turn ${t + 1} with the keeper on read ${on.processed}',
        );
        expect(
          off.processed,
          greaterThan(off.promptTokens * 8 ~/ 10),
          reason: 'turn ${t + 1} with the keeper off read ${off.processed}',
        );
      }
      expect(b.chats.last.processed, lessThanOrEqualTo(16));
      expect(
        a.chats.last.processed,
        greaterThan(a.chats.last.promptTokens * 8 ~/ 10),
      );
    },
    timeout: _slow,
    skip: liveEngineSkip,
  );

  test(
    'a chat that grows toward the context is still kept: its save stays '
    'under the time the keeper allows',
    () async {
      final rig = await startRig(liveEngineModel);
      final kobold = rig.kobold;
      final api = KoboldHttpSlotApi(() => kobold.baseUrl);
      final r = Random(11);
      final rules = _text(r, 800);
      final rows = <String>[];

      /// One reply of [chat], which the keeper saves into [slot]; its tokens.
      /// The save is timed as the line it holds after the reply. The load is
      /// asked of the engine directly, for that slot while the line is idle,
      /// and brings the same cache back.
      Future<int> step(
        String chat,
        String prompt,
        int slot, {
        String note = '',
      }) async {
        final reply = Stopwatch()..start();
        await kobold
            .generateStream(
              GenerationParams(
                prompt: prompt,
                systemPrompt: rules,
                maxLength: 8,
                temperature: 0.2,
                kvChat: chat,
              ),
            )
            .drain<void>();
        final replyMs = reply.elapsedMilliseconds;
        final saving = Stopwatch()..start();
        await kobold.waitForIdle();
        final saveMs = saving.elapsedMilliseconds;
        final tokens = await kobold.countTokens('$rules $prompt');
        final states = await livePost(rig.port, '/api/admin/check_state', {
          'slot': 0,
        });
        final size = ((states as Map)['old_states'] as List)[slot]['size'];
        final loading = Stopwatch()..start();
        final loaded = await api.load(slot);
        final loadMs = loading.elapsedMilliseconds;
        expect(loaded.ok, isTrue, reason: 'the slot the keeper saved into');
        rows.add(
          '${tokens.toString().padLeft(7)}  '
          '${'${(size as num) ~/ 1000000} MB'.padLeft(8)}  '
          '${'$replyMs ms'.padLeft(9)}  '
          '${'$saveMs ms'.padLeft(8)}  '
          '${'$loadMs ms'.padLeft(8)}  '
          '${loaded.tokens} restored$note',
        );
        return tokens;
      }

      var history = '';
      for (var tokens = 0; tokens < 13000 && rows.length < 10;) {
        history = '$history\n${_text(r, 1300)}';
        tokens = await step('long', history, 0);
      }
      // A second chat that is already long when it starts: its first save
      // goes into a slot nothing has been written to.
      await step(
        'fresh',
        _text(r, 6500),
        1,
        note: '  (a new chat, a slot not used before)',
      );
      final kept = kobold.debugKeeper.kept;
      final tooSlow = [
        for (final l in kobold.logs)
          if (l.contains('too long to do after every reply')) l.trim(),
      ];
      final said = engineSaid(kobold);
      await stopRig(rig);
      report(
        '\nlong chat, ${p.basename(liveEngineModel)} on '
        '${p.basename(liveEngineBin)}\n$said'
        ' tokens  cache  reply (read and written)  save  load\n'
        '${rows.join('\n')}\n',
      );
      expect(rows.length, greaterThanOrEqualTo(3));
      expect(
        tooSlow,
        isEmpty,
        reason:
            'a real long chat took longer to save than the '
            '${kKoboldSlowSave.inSeconds} s the keeper allows',
      );
      expect(kept, 2, reason: 'both chats are kept');
    },
    timeout: _slow,
    skip: liveEngineSkip,
  );

  final hybrid = Platform.environment['KOBOLD_LIVE_HYBRID_MODEL'] ?? '';
  test(
    'a model with recurrent layers keeps KoboldCpp\'s own smart cache and the '
    'keeper stays out',
    () async {
      final rig = await startRig(hybrid);
      final run = await script(rig, turns: 3);
      final kobold = rig.kobold;
      final out = table({'hybrid': run});
      await stopRig(rig);

      report(
        '\nhybrid ${p.basename(hybrid)} on ${p.basename(liveEngineBin)}\n$out',
      );
      expect(run.staged.containsKey('smartcache'), isTrue);
      expect(run.staged['noshift'], isFalse);
      expect(kobold.debugKeeper.chats, 0);
      expect(kobold.debugKeeper.kept, 0);
      expect(
        kobold.logs.where((l) => l.contains('cannot go back to an earlier')),
        hasLength(1),
        reason: 'the keeper says once, for the load, why it stays out',
      );
    },
    timeout: _slow,
    skip:
        liveEngineSkip ??
        (File(hybrid).existsSync()
            ? null
            : 'set KOBOLD_LIVE_HYBRID_MODEL to a small model with recurrent layers'),
  );

  test(
    'a real chat with Realism on: each reply after the first loads the chat '
    'back and reads less than the cache it restored',
    () async {
      final rig = await startRig(liveEngineModel);
      final db = AppDatabase.forTesting();
      final chat =
          ChatService(
              rig.kobold,
              UserPersonaService(db),
              rig.storage,
              WorldRepository(rig.storage, db),
            )
            ..setDatabase(db)
            ..setCharacterRepository(CharacterRepository(db, rig.storage));
      addTearDown(() => disposeChatThenCloseDb(chat, db));
      final ada = CharacterCard(
        name: 'Ada',
        description: 'Keeps the porch. ' * 60,
        firstMessage: 'Evening.',
        imagePath: '/tmp/ada-keeper-live.png',
        frontPorchExtensions: FrontPorchExtensions(
          realismEnabled: true,
          needsSimEnabled: true,
        ),
      );
      await CharacterRepository(db, rig.storage).addCharacter(ada);
      await chat.setActiveCharacter(ada);

      for (final line in [
        'Good evening, Ada.',
        'Did the rain stop?',
        'Shall we sit on the porch a while?',
        'Tell me about the orchard.',
      ]) {
        await chat.sendMessage(line);
        for (
          var i = 0;
          i < 3000 && (chat.isGenerating || chat.isSettlingTurn);
          i++
        ) {
          await Future<void>.delayed(const Duration(milliseconds: 20));
        }
        await rig.kobold.waitForIdle();
      }

      // What each load restored, and what the reply after it read.
      final loaded = RegExp(
        r'KV Load SaveState \d+: Restored KV with (\d+) tokens',
      );
      final restored = <int>[];
      final read = <int>[];
      var waiting = false;
      for (final line in rig.kobold.logs) {
        final load = loaded.firstMatch(line);
        if (load != null) {
          restored.add(int.parse(load.group(1)!));
          waiting = true;
        } else if (waiting) {
          final m = _processedLine.firstMatch(line);
          if (m != null) {
            read.add(int.parse(m.group(1)!));
            waiting = false;
          }
        }
      }
      final said = [
        for (var i = 0; i < restored.length; i++)
          '${restored[i]} restored, ${read[i]} read',
      ];
      report(
        '\nreal chat with Realism on, ${p.basename(liveEngineBin)}\n${said.join('\n')}\n',
      );
      expect(
        restored.length,
        greaterThanOrEqualTo(3),
        reason: 'a load for each reply after the first',
      );
      expect(read.length, restored.length);
      for (var i = 0; i < restored.length; i++) {
        expect(
          read[i],
          lessThan(restored[i]),
          reason: 'reply ${i + 2} read ${read[i]} of ${restored[i]}',
        );
      }
      expect(
        chat.messages.where((m) => !m.isUser).length,
        greaterThanOrEqualTo(4),
      );
    },
    timeout: _slow,
    skip: liveEngineSkip,
  );
}
