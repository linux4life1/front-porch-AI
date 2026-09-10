// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Belt A: loop truth. Proven red against the OpenCode-class audit
// (verify VIP club, failed-mutate wrap-up, Stop drain, check-in chop,
// OR reviewed, pattern-blind glob stub, generic Done, todowrite desync,
// forceTool cleared on first read, Flutter-first cues).

import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/services/waifu/waifu.dart';
import 'package:path/path.dart' as p;

import 'waifu_analyze_bash.dart';

WaifuToolResult _writeOk(String path) => WaifuToolResult(
  ok: true,
  output: 'wrote $path',
  write: WaifuWriteRecord(relativePath: path, before: 'old', after: 'new'),
);

WaifuTurnContract _afterWrites(Iterable<String> paths) {
  final turn = WaifuTurnContract.start('fix the files', null);
  for (final path in paths) {
    turn.noteResult(
      kWaifuToolWrite,
      _writeOk(path),
      _writeOk(path).write,
      args: {'path': path, 'contents': 'new'},
    );
  }
  return turn;
}

void _read(WaifuTurnContract turn, String path) {
  turn.noteResult(
    kWaifuToolRead,
    const WaifuToolResult(ok: true, output: 'new'),
    null,
    args: {'path': path},
  );
}

void _bash(WaifuTurnContract turn, String command, {bool ok = true}) {
  turn.noteResult(
    kWaifuToolBash,
    WaifuToolResult(ok: ok, output: ok ? 'passed' : 'failed'),
    null,
    args: {'command': command},
  );
}

void main() {
  test('A1: polyglot test class receipts; echo/ls/help/build do not', () {
    expect(waifuLooksVerifyCommand('cargo test'), isTrue);
    expect(waifuLooksVerifyCommand('npm test'), isTrue);
    expect(waifuLooksVerifyCommand('pytest'), isTrue);
    expect(waifuLooksVerifyCommand('python -m pytest'), isTrue);
    expect(waifuLooksVerifyCommand('flutter test'), isTrue);
    expect(waifuLooksVerifyCommand('dart analyze'), isTrue);
    expect(waifuLooksVerifyCommand('mvn test'), isTrue);
    expect(waifuLooksVerifyCommand('gradle test'), isTrue);
    expect(waifuLooksVerifyCommand('dotnet test'), isTrue);
    expect(waifuLooksVerifyCommand('bun test'), isTrue);
    expect(waifuLooksVerifyCommand('mix test'), isTrue);
    expect(waifuLooksVerifyCommand('zig test'), isTrue);
    expect(waifuLooksVerifyCommand('echo cargo test'), isFalse);
    expect(waifuLooksVerifyCommand('ls -la'), isFalse);
    expect(waifuLooksVerifyCommand('cargo test --help'), isFalse);
    expect(waifuLooksVerifyCommand('cargo test --dry-run'), isFalse);
    expect(waifuLooksVerifyCommand('cargo build'), isFalse);
    expect(waifuLooksVerifyCommand('npm run build'), isFalse);
    expect(waifuLooksVerifyCommand('swift build'), isFalse);
    expect(waifuLooksVerifyCommand('test -f parser.dart'), isFalse);
  });

  test('A1: step.verify / named / marker beat the deny-list-only gate', () {
    const ctx = WaifuVerifyContext(
      stepVerify: ['make ci'],
      named: ['tox -e py'],
      markers: ['ctest --output-on-failure'],
    );
    expect(waifuLooksVerifyCommand('make ci', context: ctx), isTrue);
    expect(waifuLooksVerifyCommand('tox -e py', context: ctx), isTrue);
    expect(
      waifuLooksVerifyCommand('ctest --output-on-failure', context: ctx),
      isTrue,
    );
    expect(waifuLooksVerifyCommand('make ci --help', context: ctx), isFalse);
    expect(waifuLooksVerifyCommand('make build', context: ctx), isFalse);
    expect(waifuLooksVerifyCommand('echo make ci', context: ctx), isFalse);
  });

  test(
    'A1: cargo/npm/pytest clear tested; echo does not; Build does not ask',
    () {
      final cargo = _afterWrites(['lib.rs']);
      _bash(cargo, 'cargo test');
      expect(cargo.tested, isTrue);

      final npm = _afterWrites(['index.js']);
      _bash(npm, 'npm test');
      expect(npm.tested, isTrue);

      final py = _afterWrites(['mod.py']);
      _bash(py, 'pytest');
      expect(py.tested, isTrue);

      final echo = _afterWrites(['lib.rs']);
      _bash(echo, 'echo cargo test');
      expect(echo.tested, isFalse);

      final p = WaifuPermissions(mode: WaifuMode.build);
      expect(
        p.needsAsk(name: 'bash', args: {'command': 'cargo test'}),
        isFalse,
      );
      expect(p.needsAsk(name: 'bash', args: {'command': 'npm test'}), isFalse);
      expect(p.needsAsk(name: 'bash', args: {'command': 'pytest'}), isFalse);
      expect(
        p.needsAsk(name: 'bash', args: {'command': 'flutter test'}),
        isFalse,
      );
      expect(
        p.needsAsk(name: 'bash', args: {'command': 'rm -rf build'}),
        isTrue,
      );
      expect(
        p.needsAsk(name: 'bash', args: {'command': 'npm test && rm foo'}),
        isTrue,
      );
    },
  );

  test('A2: denied or failed mutate does not unlock wrap-up', () {
    final denied = WaifuTurn.start('fix parser.rs', null);
    expect(denied.mutationSucceeded, isFalse);
    expect(
      denied.onEmptyCalls('Hmph. Parser is fixed. Obviously.'),
      WaifuTurnStep.retry,
    );
    expect(denied.phase, WaifuPhase.tools);

    final failed = WaifuTurn.start('fix parser.rs', null);
    failed.noteResult(
      kWaifuToolWrite,
      const WaifuToolResult(ok: false, output: 'denied by user'),
      null,
      args: {'path': 'parser.rs', 'contents': 'new'},
    );
    expect(failed.mutationSucceeded, isFalse);
    expect(
      failed.onEmptyCalls('Hmph. Parser is fixed. Obviously.'),
      WaifuTurnStep.retry,
    );
    expect(failed.phase, WaifuPhase.tools);
  });

  test(
    'A3: abort clears queued follow-ups and does not drain to send',
    () async {
      final root = await Directory.systemTemp.createTemp('waifu_a3_');
      addTearDown(() async {
        if (await root.exists()) await root.delete(recursive: true);
      });
      final gate = Completer<void>();
      final llm = ScriptedWaifuLlm(
        [
          const LlmToolResponse(calls: [], text: 'first done'),
          const LlmToolResponse(calls: [], text: 'second done'),
        ],
        beforeGenerate: (i) async {
          if (i == 0) await gate.future;
        },
      );
      final session = WaifuSession(
        folderRoot: root.path,
        coworker: CharacterCard(name: 'Iris'),
      );
      final harness = WaifuHarness(session: session, llm: llm);
      final first = harness.send('first');
      for (var i = 0; i < 40 && !session.running; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      expect(session.running, isTrue);
      await harness.send('second');
      expect(session.queued, ['second']);
      harness.abort();
      expect(session.queued, isEmpty);
      gate.complete();
      await first;
      expect(session.queued, isEmpty);
      expect(session.transcript.where((m) => m.isUser).map((m) => m.text), [
        'first',
      ]);
      expect(
        session.transcript
            .where((m) => m.kind == WaifuMsgKind.assistant)
            .map((m) => m.text)
            .join('\n'),
        isNot(contains('second done')),
      );
    },
  );

  test('A4: check-in does not reset until verify+speak', () {
    final turn = _afterWrites([
      for (var i = 1; i <= kWaifuCheckInEvery; i++) 'f$i.txt',
    ]);
    expect(turn.mutationsSinceCheckIn, kWaifuCheckInEvery);
    turn.requestCheckInSpeech();
    expect(turn.mutationsSinceCheckIn, kWaifuCheckInEvery);
    turn.requestSpeech();
    expect(turn.mutationsSinceCheckIn, 0);
  });

  test('A4: sibling tool_calls in one model response all run', () async {
    final root = await Directory.systemTemp.createTemp('waifu_a4_');
    addTearDown(() async {
      if (await root.exists()) await root.delete(recursive: true);
    });
    for (var i = 1; i <= kWaifuCheckInEvery + 1; i++) {
      await File(p.join(root.path, 'f$i.txt')).writeAsString('old $i');
    }
    final writes = [
      for (var i = 1; i <= kWaifuCheckInEvery + 1; i++)
        LlmToolCall(
          name: 'write',
          arguments: {'path': 'f$i.txt', 'contents': 'body $i'},
        ),
    ];
    final reads = [
      for (var i = 1; i <= kWaifuCheckInEvery + 1; i++)
        LlmToolCall(name: 'read', arguments: {'path': 'f$i.txt'}),
    ];
    final llm = ScriptedWaifuLlm([
      LlmToolResponse(calls: writes, text: ''),
      LlmToolResponse(calls: reads, text: ''),
      const LlmToolResponse(calls: [kWaifuAnalyzeCall], text: ''),
      const LlmToolResponse(
        calls: [],
        text: 'Hmph. Scaffold is up. Parser is next unless you want the UI.',
      ),
    ]);
    final session = WaifuSession(
      folderRoot: root.path,
      coworker: CharacterCard(name: 'Iris'),
    );
    await WaifuHarness(
      session: session,
      llm: llm,
      bash: WaifuAnalyzeBash(root.path),
    ).send('build the app');
    expect(
      await File(
        p.join(root.path, 'f${kWaifuCheckInEvery + 1}.txt'),
      ).readAsString(),
      'body ${kWaifuCheckInEvery + 1}',
    );
    final spoken = session.transcript
        .where((m) => m.kind == WaifuMsgKind.assistant)
        .toList();
    expect(spoken, hasLength(1));
    expect(spoken.single.text, contains('Scaffold is up'));
  });

  test('A5: multi-file reviewed is AND of touched mutate paths', () {
    final turn = _afterWrites(['a.rs', 'b.rs']);
    _read(turn, 'a.rs');
    expect(turn.reviewed, isFalse);
    expect(turn.verified, isFalse);
    _read(turn, 'b.rs');
    expect(turn.reviewed, isTrue);
    _bash(turn, 'cargo test');
    expect(turn.verified, isTrue);
  });

  test('A5: run-plan-step cue wants re-read AND verify, not OR', () {
    final prompt =
        waifuBuiltinRunPlanStepWorkflow().steps.last.agents.single.prompt;
    expect(prompt, contains('Re-read every touched path'));
    expect(prompt, contains('AND'));
    expect(prompt.toLowerCase(), isNot(contains(' or run the step')));
    expect(prompt, contains('step verify'));
    expect(prompt, isNot(contains('flutter test')));
    expect(prompt, isNot(contains('dart analyze')));
  });

  test('A6: glob stub keys on pattern and path', () {
    const first = WaifuMessage.tool(
      name: kWaifuToolGlob,
      output: 'a.rs',
      ok: true,
      args: {'pattern': '*.rs', 'path': 'src'},
    );
    expect(
      waifuDuplicateGlobStub(
        transcript: const [first],
        pattern: '*.rs',
        path: 'src',
      ),
      kWaifuDuplicateInHistory,
    );
    expect(
      waifuDuplicateGlobStub(
        transcript: const [first],
        pattern: '*.toml',
        path: 'src',
      ),
      isNull,
    );
    expect(
      waifuDuplicateGlobStub(
        transcript: const [first],
        pattern: '*.rs',
        path: 'tests',
      ),
      isNull,
    );
  });

  test('A7: live wrap-up rejects generic Done; no second authority', () {
    final turn = WaifuTurn.start('track the work', null);
    turn.noteResult(
      kWaifuToolGlob,
      const WaifuToolResult(ok: true, output: 'ok'),
      null,
      args: {'pattern': '*'},
    );
    expect(turn.onEmptyCalls('Done.'), WaifuTurnStep.retry);
    expect(turn.pendingSpeech, isNot('Done.'));
  });

  test('A8: todowrite schema rejects malformed items', () {
    expect(waifuTodoWriteError(null), isNotNull);
    expect(waifuTodoWriteError('nope'), isNotNull);
    expect(
      waifuTodoWriteError([
        {'content': 'x', 'status': 'pending'},
      ]),
      isNotNull,
    );
    expect(
      waifuTodoWriteError([
        {'id': '1', 'status': 'pending'},
      ]),
      isNotNull,
    );
    expect(
      waifuTodoWriteError([
        {'id': '1', 'content': 'x', 'status': 'maybe'},
      ]),
      isNotNull,
    );
    expect(
      waifuTodoWriteError([
        {'id': '1', 'content': 'x', 'status': 'completed'},
      ]),
      isNull,
    );
    final schema = kWaifuFileTools.firstWhere(
      (t) => (t['function'] as Map)['name'] == kWaifuToolTodoWrite,
    );
    final items =
        (((schema['function'] as Map)['parameters'] as Map)['properties']
                as Map)['todos']
            as Map;
    expect(items['items'], isA<Map>());
    expect(
      (items['items'] as Map)['required'],
      containsAll(['id', 'content', 'status']),
    );
    expect(
      (((items['items'] as Map)['properties'] as Map)['status'] as Map)['enum'],
      ['pending', 'in_progress', 'completed'],
    );
  });

  test(
    'A8: blockedDone syncs before saveLast so disk is not completed',
    () async {
      final root = await Directory.systemTemp.createTemp('waifu_a8_');
      final storeDir = await Directory.systemTemp.createTemp('waifu_a8_store_');
      addTearDown(() async {
        if (await root.exists()) await root.delete(recursive: true);
        if (await storeDir.exists()) await storeDir.delete(recursive: true);
      });
      final rel = '.waifu/plans/empty-email.md';
      await Directory(
        p.join(root.path, '.waifu', 'plans'),
      ).create(recursive: true);
      await File(p.join(root.path, rel)).writeAsString('''
---
id: empty-email
slug: empty-email
title: Empty email fix
status: accepted
steps:
- id: s1
  title: Fix the parser
  status: pending
---
''');
      final session = WaifuSession(
        folderRoot: root.path,
        coworker: CharacterCard(name: 'Iris'),
        mode: WaifuMode.build,
        activePlanPath: rel,
      );
      await WaifuHarness(
        session: session,
        llm: ScriptedWaifuLlm([
          const LlmToolResponse(
            calls: [
              LlmToolCall(
                name: 'todowrite',
                arguments: {
                  'todos': [
                    {
                      'id': 's1',
                      'content': 'Fix the parser',
                      'status': 'completed',
                    },
                  ],
                },
              ),
            ],
            text: '',
          ),
          const LlmToolResponse(calls: [], text: 'Hmph. Looking around first.'),
        ]),
        store: WaifuStore(storeDir.path),
        onAsk: (_) async => WaifuAskDecision.allowAlways,
      ).send('mark the first plan step done');
      expect(session.todos.items.single.status, isNot('completed'));
      final disk = await waifuTodosFile(root.path).readAsString();
      expect(disk, isNot(contains('"completed"')));
    },
  );

  test('A9: forceTool holds until mutate+verify; speechOnly is exempt', () {
    final turn = WaifuTurn.start('fix parser.rs', null);
    expect(turn.shouldForceTool, isTrue);
    turn.noteResult(
      kWaifuToolWrite,
      _writeOk('parser.rs'),
      _writeOk('parser.rs').write,
      args: {'path': 'parser.rs', 'contents': 'new'},
    );
    expect(turn.mutationSucceeded, isTrue);
    expect(turn.verifyRequired, isTrue);
    expect(turn.shouldForceTool, isTrue);
    _read(turn.contract, 'parser.rs');
    _bash(turn.contract, 'cargo test');
    expect(turn.verified, isTrue);
    expect(turn.shouldForceTool, isFalse);
    turn.requestSpeech();
    expect(turn.speechOnly, isTrue);
    expect(turn.shouldForceTool, isFalse);
  });

  test('A10: lookup and run-plan-step cues are stack-agnostic', () {
    expect(kWaifuLookupCue.toLowerCase(), isNot(contains('flutter')));
    expect(kWaifuLookupCue, isNot(contains('docs.flutter.dev')));
    expect(kWaifuLookupCue, isNot(contains('pub.dev')));
    expect(kWaifuLookupCue, isNot(contains('dart.dev')));
    expect(kWaifuLookupCue, contains('web_search'));
    final prompt = waifuLoopUserPrompt(
      folderName: 'app',
      coworkerName: 'Iris',
      transcript: const [],
      todos: '',
      mentionBlock: '',
    );
    expect(prompt, contains(kWaifuLookupCue));
    expect(prompt, isNot(contains('flutter test, dart analyze')));
  });

  test(
    'live generate meters the messages request, not a second blob',
    () async {
      final root = await Directory.systemTemp.createTemp('waifu_req_');
      addTearDown(() async {
        if (await root.exists()) await root.delete(recursive: true);
      });
      final llm = ScriptedWaifuLlm([
        const LlmToolResponse(calls: [], text: 'Hmph. Looking around first.'),
      ]);
      final session = WaifuSession(
        folderRoot: root.path,
        coworker: CharacterCard(name: 'Iris'),
      );
      await WaifuHarness(session: session, llm: llm).send('look around');
      expect(llm.calls, isNotEmpty);
      final call = llm.calls.first;
      expect(call.messages, isNotNull);
      expect(call.prompt, waifuMessagesMeterText(call.messages!));
      expect(
        call.messages!.where((m) => m['role'] == 'user').length,
        greaterThanOrEqualTo(2),
      );
    },
  );
}
