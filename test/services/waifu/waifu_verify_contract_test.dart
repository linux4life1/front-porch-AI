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
    root = await Directory.systemTemp.createTemp('waifu_verify_');
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

  WaifuTurnContract afterWrite({
    WaifuMode mode = WaifuMode.yolo,
    String path = 'parser.dart',
    bool enforceVerify = true,
  }) {
    final turn = WaifuTurnContract.start(
      'fix $path',
      null,
      mode: mode,
      enforceVerify: enforceVerify,
    );
    turn.noteAttempt(kWaifuToolWrite);
    turn.noteResult(
      kWaifuToolWrite,
      writeOk(path),
      writeOk(path).write,
      args: {'path': path, 'contents': 'new'},
    );
    return turn;
  }

  test('verify command pins test/analyze and rejects echo/ls', () {
    expect(
      waifuLooksVerifyCommand('flutter test test/parser_test.dart'),
      isTrue,
    );
    expect(waifuLooksVerifyCommand('dart analyze lib/parser.dart'), isTrue);
    expect(waifuLooksVerifyCommand('npm test'), isTrue);
    expect(waifuLooksVerifyCommand('cargo clippy'), isTrue);
    expect(waifuLooksVerifyCommand('echo flutter test'), isFalse);
    expect(waifuLooksVerifyCommand('ls -la'), isFalse);
    expect(waifuLooksVerifyCommand('test -f parser.dart'), isFalse);
  });

  test('mutate without verify fails the contract', () {
    final turn = afterWrite();
    expect(turn.mutationSucceeded, isTrue);
    expect(turn.verifyRequired, isTrue);
    expect(turn.verified, isFalse);
    expect(turn.allowsPlanStepDone, isFalse);
    expect(
      turn.decideFinal('Hmph. Parser is fixed. Obviously.'),
      WaifuFinalAction.retryVerify,
    );
    turn.requestVerify();
    expect(turn.cue, contains('Re-read a touched path'));
    expect(
      turn.decideFinal('Hmph. Parser is fixed. Obviously.'),
      WaifuFinalAction.retryVerify,
    );
    turn.requestVerify();
    expect(
      turn.decideFinal('Hmph. Parser is fixed. Obviously.'),
      WaifuFinalAction.failVerify,
    );
    expect(turn.failureLine('Hmph.'), contains('did not re-read or test'));
  });

  test('mutate then re-read the touched path passes', () {
    final turn = afterWrite();
    turn.noteAttempt(kWaifuToolRead);
    turn.noteResult(
      kWaifuToolRead,
      const WaifuToolResult(ok: true, output: 'String parse() => "new";\n'),
      writeOk('parser.dart').write,
      args: {'path': 'parser.dart'},
    );
    expect(turn.verified, isTrue);
    expect(turn.allowsPlanStepDone, isTrue);
    expect(
      turn.decideFinal('Hmph. Parser is fixed. Obviously.'),
      WaifuFinalAction.accept,
    );
  });

  test('mutate then flutter test bash passes; echo does not', () {
    final echo = afterWrite();
    echo.noteAttempt(kWaifuToolBash);
    echo.noteResult(
      kWaifuToolBash,
      const WaifuToolResult(ok: true, output: 'ok'),
      writeOk('parser.dart').write,
      args: {'command': 'echo flutter test'},
    );
    expect(echo.verified, isFalse);
    expect(
      echo.decideFinal('Hmph. Done talking.'),
      WaifuFinalAction.retryVerify,
    );

    final testRun = afterWrite();
    testRun.noteAttempt(kWaifuToolBash);
    testRun.noteResult(
      kWaifuToolBash,
      const WaifuToolResult(ok: true, output: 'All tests passed!'),
      writeOk('parser.dart').write,
      args: {'command': 'flutter test test/parser_test.dart'},
    );
    expect(testRun.verified, isTrue);
    expect(
      testRun.decideFinal('Hmph. Tests are green. Obviously.'),
      WaifuFinalAction.accept,
    );
  });

  test('reading a different file is not verify', () {
    final turn = afterWrite();
    turn.noteResult(
      kWaifuToolRead,
      const WaifuToolResult(ok: true, output: '# notes'),
      writeOk('parser.dart').write,
      args: {'path': 'README.md'},
    );
    expect(turn.verified, isFalse);
    expect(turn.decideFinal('Hmph. Fixed.'), WaifuFinalAction.retryVerify);
  });

  test('Plan artifact writes do not require verify', () {
    final turn = WaifuTurnContract.start(
      'write a plan',
      null,
      mode: WaifuMode.plan,
    );
    turn.noteAttempt(kWaifuToolWrite);
    turn.noteResult(
      kWaifuToolWrite,
      writeOk('.waifu/plans/empty-email.md'),
      writeOk('.waifu/plans/empty-email.md').write,
      args: {'path': '.waifu/plans/empty-email.md', 'contents': 'plan'},
    );
    expect(turn.mutationSucceeded, isTrue);
    expect(turn.verifyRequired, isFalse);
    expect(
      turn.decideFinal('Hmph. The plan is on the porch. Obviously.'),
      WaifuFinalAction.accept,
    );
  });

  test('freeform Build uses the same verify-after-mutate gate', () async {
    await File(p.join(root.path, 'parser.dart')).writeAsString('old\n');
    final llm = ScriptedWaifuLlm([
      const LlmToolResponse(
        calls: [
          LlmToolCall(
            name: 'write',
            arguments: {'path': 'parser.dart', 'contents': 'new\n'},
          ),
        ],
        text: '',
      ),
      const LlmToolResponse(
        calls: [],
        text: 'Hmph. Parser is fixed. Obviously.',
      ),
      const LlmToolResponse(
        calls: [],
        text: 'Hmph. Parser is fixed. Obviously.',
      ),
      const LlmToolResponse(
        calls: [],
        text: 'Hmph. Parser is fixed. Obviously.',
      ),
    ]);
    final session = WaifuSession(
      folderRoot: root.path,
      coworker: iris(),
      mode: WaifuMode.build,
    );
    await WaifuHarness(
      session: session,
      llm: llm,
      onAsk: (_) async => WaifuAskDecision.allowAlways,
    ).send('fix parser.dart');

    expect(
      await File(p.join(root.path, 'parser.dart')).readAsString(),
      'new\n',
    );
    final reply = session.transcript.where((m) => !m.isUser).single;
    expect(reply.chips.last.ok, isFalse);
    expect(reply.chips.last.detail, contains('no verify'));
    expect(reply.text, contains('did not re-read or test'));
  });

  test('Build mutate then re-read may accept', () async {
    await File(p.join(root.path, 'parser.dart')).writeAsString('old\n');
    final llm = ScriptedWaifuLlm([
      const LlmToolResponse(
        calls: [
          LlmToolCall(
            name: 'write',
            arguments: {'path': 'parser.dart', 'contents': 'new\n'},
          ),
        ],
        text: '',
      ),
      const LlmToolResponse(
        calls: [
          LlmToolCall(name: 'read', arguments: {'path': 'parser.dart'}),
        ],
        text: '',
      ),
      const LlmToolResponse(
        calls: [],
        text: 'Hmph. Parser is fixed. Obviously.',
      ),
    ]);
    final session = WaifuSession(
      folderRoot: root.path,
      coworker: iris(),
      mode: WaifuMode.build,
    );
    await WaifuHarness(
      session: session,
      llm: llm,
      onAsk: (_) async => WaifuAskDecision.allowAlways,
    ).send('fix parser.dart');

    final reply = session.transcript.where((m) => !m.isUser).single;
    expect(reply.chips.last.ok, isTrue);
    expect(reply.text, contains('Obviously.'));
    expect(reply.text, isNot(contains('did not re-read')));
  });

  test('accepted plan step stays pending without mutate+verify', () async {
    final rel = '.waifu/plans/empty-email.md';
    await Directory(
      p.join(root.path, '.waifu', 'plans'),
    ).create(recursive: true);
    await File(p.join(root.path, rel)).writeAsString('''
---
id: empty-email
slug: empty-email
title: Empty email fix
goal: Make the empty-email test pass
status: accepted
assumptions:
- []
constraints:
- []
risks:
- []
openQuestions:
- []
steps:
- id: s1
  title: Fix the parser
  detail: Treat empty as invalid
  verify: flutter test test/parser_test.dart
  status: pending
  files:
    - parser.dart
---

# Empty email fix
''');
    final session = WaifuSession(
      folderRoot: root.path,
      coworker: iris(),
      mode: WaifuMode.build,
      activePlanPath: rel,
    );
    final llm = ScriptedWaifuLlm([
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
    ]);
    await WaifuHarness(
      session: session,
      llm: llm,
      onAsk: (_) async => WaifuAskDecision.allowAlways,
    ).send('mark the first plan step done');
    final after = waifuPlanParse(
      await File(p.join(root.path, rel)).readAsString(),
    );
    expect(after.steps.single.status, 'pending');
    expect(
      session.toolChips.any((c) => c.name == kWaifuToolTodoWrite && !c.ok),
      isTrue,
    );
  });

  test('accepted plan step completes after mutate+verify', () async {
    final rel = '.waifu/plans/empty-email.md';
    await Directory(
      p.join(root.path, '.waifu', 'plans'),
    ).create(recursive: true);
    await File(p.join(root.path, rel)).writeAsString('''
---
id: empty-email
slug: empty-email
title: Empty email fix
goal: Make the empty-email test pass
status: accepted
assumptions:
- []
constraints:
- []
risks:
- []
openQuestions:
- []
steps:
- id: s1
  title: Fix the parser
  detail: Treat empty as invalid
  verify: flutter test test/parser_test.dart
  status: pending
  files:
    - parser.dart
---

# Empty email fix
''');
    await File(p.join(root.path, 'parser.dart')).writeAsString('old\n');
    final session = WaifuSession(
      folderRoot: root.path,
      coworker: iris(),
      mode: WaifuMode.build,
      activePlanPath: rel,
    );
    final llm = ScriptedWaifuLlm([
      const LlmToolResponse(
        calls: [
          LlmToolCall(
            name: 'write',
            arguments: {'path': 'parser.dart', 'contents': 'new\n'},
          ),
        ],
        text: '',
      ),
      const LlmToolResponse(
        calls: [
          LlmToolCall(name: 'read', arguments: {'path': 'parser.dart'}),
        ],
        text: '',
      ),
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
    ]);
    await WaifuHarness(
      session: session,
      llm: llm,
      onAsk: (_) async => WaifuAskDecision.allowAlways,
    ).send('implement the first plan step');
    final after = waifuPlanParse(
      await File(p.join(root.path, rel)).readAsString(),
    );
    expect(after.steps.single.status, 'completed');
  });

  test(
    'built-in run-plan-step workflow is always listable and loadable',
    () async {
      final items = await waifuListWorkflows(root.path);
      expect(items.map((i) => i.name), contains(kWaifuBuiltinRunPlanStep));
      expect(
        waifuWorkflowListing(items),
        contains(kWaifuBuiltinRunPlanStepDescription),
      );
      final loaded = await waifuLoadWorkflow(
        root.path,
        kWaifuBuiltinRunPlanStep,
      );
      expect(loaded.error, isNull);
      expect(loaded.workflow!.steps, hasLength(2));
      expect(loaded.workflow!.steps.first.agents.single.subagent, 'general');
      expect(
        loaded.workflow!.steps.last.agents.single.prompt,
        contains('Verify'),
      );
      expect(kWaifuBuildVerifyCue, contains(kWaifuBuiltinRunPlanStep));
    },
  );

  test('parent absorbs child mutate then child re-read as verify', () {
    final parent = WaifuTurnContract.start(
      'implement the first plan step',
      null,
      mode: WaifuMode.build,
    );
    final childMutate = afterWrite(enforceVerify: false);
    parent.absorbChild(childMutate);
    expect(parent.mutationSucceeded, isTrue);
    expect(parent.verifyRequired, isTrue);
    expect(parent.verified, isFalse);

    final childVerify = WaifuTurnContract.start(
      'verify the change',
      null,
      mode: WaifuMode.build,
      enforceVerify: false,
    );
    childVerify.noteResult(
      kWaifuToolRead,
      const WaifuToolResult(ok: true, output: 'new'),
      null,
      args: {'path': 'parser.dart'},
    );
    parent.absorbChild(childVerify);
    expect(parent.verified, isTrue);
    expect(parent.allowsPlanStepDone, isTrue);
    expect(
      parent.decideFinal('Hmph. Step landed. Obviously.'),
      WaifuFinalAction.accept,
    );
  });
}
