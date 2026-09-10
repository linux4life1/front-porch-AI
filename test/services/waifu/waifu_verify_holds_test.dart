// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/services/waifu/waifu.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory root;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('waifu_holds_');
  });

  tearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });

  CharacterCard iris() => CharacterCard(
    name: 'Iris',
    personality: 'proud, sharp, and teasing',
    description: 'A meticulous parser engineer.',
    systemPrompt: 'End a successful work report with “Obviously.”',
  );

  WaifuToolResult writeOk(String path) => WaifuToolResult(
    ok: true,
    output: 'wrote $path',
    write: WaifuWriteRecord(relativePath: path, before: 'old', after: 'new'),
  );

  WaifuTurnContract afterWrite({bool enforceVerify = true}) {
    final turn = WaifuTurnContract.start(
      'fix parser.dart',
      null,
      mode: WaifuMode.yolo,
      enforceVerify: enforceVerify,
    );
    turn.noteResult(
      kWaifuToolWrite,
      writeOk('parser.dart'),
      writeOk('parser.dart').write,
      args: {'path': 'parser.dart', 'contents': 'new'},
    );
    return turn;
  }

  void expectVerifyFail(WaifuTurnContract turn) {
    expect(turn.verified, isFalse);
    final live = WaifuTurn.fromContract(turn);
    const line = 'Hmph. Parser is fixed. Obviously.';
    expect(live.onEmptyCalls(line), WaifuTurnStep.retry);
    expect(live.onEmptyCalls(line), WaifuTurnStep.retry);
    expect(live.onEmptyCalls(line), WaifuTurnStep.fail);
  }

  test('compound verify scans any segment; echo&&ls does not', () {
    expect(waifuLooksVerifyCommand('cd pkg && flutter test'), isTrue);
    expect(waifuLooksVerifyCommand('pushd pkg && dart analyze'), isTrue);
    expect(waifuLooksVerifyCommand('echo hi && ls'), isFalse);
    final ok = afterWrite();
    ok.noteResult(
      kWaifuToolBash,
      const WaifuToolResult(ok: true, output: 'All tests passed!'),
      writeOk('parser.dart').write,
      args: {'command': 'cd pkg && flutter test'},
    );
    expect(ok.tested, isTrue);
    expect(ok.reviewed, isFalse);
    expect(ok.verified, isFalse);
    final no = afterWrite();
    no.noteResult(
      kWaifuToolBash,
      const WaifuToolResult(ok: true, output: 'hi'),
      writeOk('parser.dart').write,
      args: {'command': 'echo hi && ls'},
    );
    expect(no.verified, isFalse);
  });

  test('help and dry-run flags are not verify', () {
    expect(waifuLooksVerifyCommand('flutter test --help'), isFalse);
    expect(waifuLooksVerifyCommand('flutter test -h'), isFalse);
    expect(waifuLooksVerifyCommand('dart analyze --dry-run'), isFalse);
    expect(waifuLooksVerifyCommand('cd pkg && flutter test --help'), isFalse);
    expect(
      waifuLooksVerifyCommand('flutter test --help || flutter test'),
      isFalse,
    );
    expect(
      waifuLooksVerifyCommand('flutter test --dry-run || flutter test'),
      isFalse,
    );
    expect(waifuLooksVerifyCommand('cd pkg && flutter test'), isTrue);
    expect(waifuLooksVerifyCommand('flutter test'), isTrue);
    expect(waifuLooksVerifyCommand('dart analyze'), isTrue);
    final help = afterWrite();
    help.noteResult(
      kWaifuToolBash,
      const WaifuToolResult(ok: true, output: 'Usage: flutter test'),
      writeOk('parser.dart').write,
      args: {'command': 'flutter test --help || flutter test'},
    );
    expectVerifyFail(help);
  });

  test('pre-mutate read is not review; post-mutate read is review only', () {
    final turn = WaifuTurnContract.start(
      'fix parser.dart',
      null,
      mode: WaifuMode.yolo,
    );
    turn.noteResult(
      kWaifuToolRead,
      const WaifuToolResult(ok: true, output: 'old'),
      null,
      args: {'path': 'parser.dart'},
    );
    turn.noteResult(
      kWaifuToolWrite,
      writeOk('parser.dart'),
      writeOk('parser.dart').write,
      args: {'path': 'parser.dart', 'contents': 'new'},
    );
    expectVerifyFail(turn);

    final post = afterWrite();
    post.noteResult(
      kWaifuToolRead,
      const WaifuToolResult(ok: true, output: 'new'),
      writeOk('parser.dart').write,
      args: {'path': 'parser.dart'},
    );
    expect(post.reviewed, isTrue);
    expect(post.tested, isFalse);
    expect(post.verified, isFalse);
  });

  test('absorbChild does not treat a pre-mutate parent read as verify', () {
    final parent = WaifuTurnContract.start(
      'fix parser.dart',
      null,
      mode: WaifuMode.build,
    );
    parent.noteResult(
      kWaifuToolRead,
      const WaifuToolResult(ok: true, output: 'old'),
      null,
      args: {'path': 'parser.dart'},
    );
    parent.absorbChild(afterWrite(enforceVerify: false));
    expectVerifyFail(parent);
  });

  test('blockedDone rolls back in-memory todo completed', () async {
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
  files:
    - parser.dart
---
''');
    final session = WaifuSession(
      folderRoot: root.path,
      coworker: iris(),
      mode: WaifuMode.build,
      activePlanPath: rel,
    );
    final harness = WaifuHarness(
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
        const LlmToolResponse(
          calls: [],
          text: 'Hmph. Step one is done. Obviously.',
        ),
      ]),
      onAsk: (_) async => WaifuAskDecision.allowAlways,
    );
    await harness.send('mark the first plan step done');
    expect(
      waifuPlanParse(
        await File(p.join(root.path, rel)).readAsString(),
      ).steps.single.status,
      'pending',
    );
    expect(harness.todos.items, isNotEmpty);
    expect(harness.todos.items.single.id, 's1');
    expect(waifuTodoStatusIsDone(harness.todos.items.single.status), isFalse);
    expect(harness.todos.read(), isNot(contains('completed')));
  });
}
