// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/llm_service.dart';
import 'package:front_porch_ai/services/llm_tool_parsing.dart';
import 'package:front_porch_ai/services/waifu/waifu.dart';
import 'package:path/path.dart' as p;

CharacterCard _iris() => CharacterCard(name: 'Iris');

Uint8List _png() => Uint8List.fromList([
  137,
  80,
  78,
  71,
  13,
  10,
  26,
  10,
  0,
  0,
  0,
  13,
  73,
  72,
  68,
  82,
  0,
  0,
  0,
  1,
  0,
  0,
  0,
  1,
  8,
  6,
  0,
  0,
  0,
  31,
  21,
  196,
  137,
  0,
  0,
  0,
  13,
  73,
  68,
  65,
  84,
  120,
  156,
  99,
  248,
  207,
  192,
  240,
  31,
  0,
  5,
  0,
  1,
  255,
  17,
  43,
  179,
  141,
  0,
  0,
  0,
  0,
  73,
  69,
  78,
  68,
  174,
  66,
  96,
  130,
]);

void main() {
  test(
    'B1: follow-up queue holds photo bytes and drain restores them',
    () async {
      final root = await Directory.systemTemp.createTemp('waifu_b1_');
      addTearDown(() async {
        if (await root.exists()) await root.delete(recursive: true);
      });
      final png = _png();
      final gate = Completer<void>();
      final llm = ScriptedWaifuLlm(
        [
          const LlmToolResponse(calls: [], text: 'first done'),
          const LlmToolResponse(calls: [], text: 'saw the shot'),
        ],
        beforeGenerate: (i) async {
          if (i == 0) await gate.future;
        },
      );
      final session = WaifuSession(folderRoot: root.path, coworker: _iris());
      final harness = WaifuHarness(session: session, llm: llm);
      final first = harness.send('first');
      for (var i = 0; i < 40 && !session.running; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      await harness.send('what is this', imagePng: png, imagePath: 'shot.png');
      expect(session.queued, hasLength(1));
      expect(session.queued.single.text, 'what is this');
      expect(session.queued.single.imagePng, png);
      expect(session.queued.single.imagePath, 'shot.png');
      gate.complete();
      await first;
      expect(session.queued, isEmpty);
      expect(llm.calls, hasLength(2));
      expect(llm.calls.last.images, isNotNull);
      expect(llm.calls.last.images!.single, base64Encode(png));
      expect(
        session.transcript.where((m) => m.isUser).last.imagePath,
        'shot.png',
      );
    },
  );

  test('B2: fold injects machine ledger; prune keeps path status args', () {
    final folded = [
      const WaifuMessage.user('fix the rust parser'),
      WaifuMessage.tool(
        name: kWaifuToolWrite,
        output: 'wrote src/main.rs',
        ok: true,
        path: 'src/main.rs',
        args: {'path': 'src/main.rs', 'contents': 'fn main() {}'},
      ),
      WaifuMessage.tool(
        name: kWaifuToolBash,
        output: 'ok',
        ok: true,
        args: {'command': 'cargo test --lib'},
      ),
      WaifuMessage.tool(
        name: kWaifuToolBash,
        output: 'ok',
        ok: true,
        args: {'command': 'ls'},
      ),
    ];
    final ledger = waifuMachineLedger(
      folded: folded,
      planPin: '.waifu/plans/parser.md',
      todos: 's1 [pending] Add failing test',
    );
    expect(ledger, contains(kWaifuMachineLedgerTitle));
    expect(ledger, contains('src/main.rs'));
    expect(ledger, contains('cargo test --lib'));
    expect(ledger, contains('.waifu/plans/parser.md'));
    expect(ledger, contains('s1 [pending] Add failing test'));
    expect(ledger, isNot(contains('lib/invented.dart')));
    expect(ledger, isNot(contains('dart analyze assumed')));
    final verifyBlock = ledger
        .split('verify as-run:')
        .last
        .split('plan:')
        .first;
    expect(verifyBlock, contains('cargo test --lib'));
    expect(verifyBlock, isNot(contains('ls')));

    final recap = waifuInjectMachineLedger(
      '$kWaifuCompactPrefix\nEdited lib/invented.dart. Tests not run.',
      ledger,
    );
    final facts = recap.split(kWaifuMachineLedgerTitle).last;
    expect(facts, contains('src/main.rs'));
    expect(
      facts.split('verify as-run').first,
      isNot(contains('lib/invented.dart')),
    );
    final poisoned = waifuInjectMachineLedger(
      '$kWaifuCompactPrefix\n$kWaifuMachineLedgerTitle\n'
      'paths:\n  lib/invented.dart',
      ledger,
    );
    expect(poisoned, contains('src/main.rs'));
    expect(poisoned, contains('cargo test --lib'));

    final msgs = <WaifuMessage>[
      for (var i = 0; i < 12; i++)
        WaifuMessage.tool(
          name: 'read',
          output: 'read\n${'x' * 4000}',
          ok: true,
          path: 'f$i.rs',
          callId: 'call_$i',
          args: {'path': 'f$i.rs', 'offset': i},
        ),
    ];
    waifuPruneOldToolMessages(msgs, budget: 8000);
    final stub = msgs.first;
    expect(stub.text.contains('pruned, was'), isTrue);
    expect(stub.toolPath, 'f0.rs');
    expect(stub.toolOk, isTrue);
    expect(stub.toolCallId, 'call_0');
    expect(stub.toolArgs, {'path': 'f0.rs', 'offset': 0});
  });

  test(
    'B3: generate meters serialized messages, not a stuffed User: blob',
    () async {
      final root = await Directory.systemTemp.createTemp('waifu_b3_');
      addTearDown(() async {
        if (await root.exists()) await root.delete(recursive: true);
      });
      final llm = ScriptedWaifuLlm([
        const LlmToolResponse(
          calls: [
            LlmToolCall(name: 'glob', arguments: {'pattern': '*'}),
          ],
          text: '',
        ),
        const LlmToolResponse(calls: [], text: 'Hmph. Empty folder.'),
      ]);
      final session = WaifuSession(folderRoot: root.path, coworker: _iris());
      await WaifuHarness(session: session, llm: llm).send('look around');
      expect(llm.calls, isNotEmpty);
      final call = llm.calls.last;
      expect(call.messages, isNotNull);
      expect(call.prompt, waifuMessagesMeterText(call.messages!));
      expect(call.messages!.any((m) => m['role'] == 'tool'), isTrue);
      final prefix = call.messages!.first['content'] as String;
      expect(prefix, isNot(contains('User: look around')));
      expect(prefix, isNot(contains('Iris: Hmph')));
    },
  );

  test('B4: provider tool_call id and args survive history rebuild', () async {
    final root = await Directory.systemTemp.createTemp('waifu_b4_');
    addTearDown(() async {
      if (await root.exists()) await root.delete(recursive: true);
    });
    final parsed = parseOpenAiToolResponse(
      jsonEncode({
        'choices': [
          {
            'message': {
              'content': '',
              'tool_calls': [
                {
                  'id': 'call_provider_9',
                  'type': 'function',
                  'function': {
                    'name': 'glob',
                    'arguments': '{"pattern":"*.rs"}',
                  },
                },
              ],
            },
          },
        ],
      }),
    )!;
    expect(parsed.calls.single.id, 'call_provider_9');
    expect(parsed.calls.single.arguments, {'pattern': '*.rs'});

    final llm = ScriptedWaifuLlm([
      const LlmToolResponse(
        calls: [
          LlmToolCall(
            name: 'glob',
            arguments: {'pattern': '*.rs', 'path': 'src'},
            id: 'call_provider_9',
          ),
        ],
        text: '',
      ),
      const LlmToolResponse(calls: [], text: 'No rust files.'),
    ]);
    final session = WaifuSession(folderRoot: root.path, coworker: _iris());
    await WaifuHarness(session: session, llm: llm).send('find rust');
    final tool = session.transcript
        .where((m) => m.kind == WaifuMsgKind.tool)
        .first;
    expect(tool.toolCallId, 'call_provider_9');
    expect(tool.toolOk, isFalse);
    expect(tool.toolArgs, {'pattern': '*.rs', 'path': 'src'});
    final rebuilt = waifuOpenAiMessages(
      folderName: root.path,
      coworkerName: 'Iris',
      transcript: session.transcript,
      todos: '',
      mentionBlock: '',
    );
    final calls = rebuilt
        .where((m) => m['role'] == 'assistant' && m['tool_calls'] != null)
        .expand((m) => m['tool_calls'] as List)
        .cast<Map>();
    expect(calls.single['id'], 'call_provider_9');
    expect(
      jsonDecode((calls.single['function'] as Map)['arguments'] as String),
      {'pattern': '*.rs', 'path': 'src'},
    );
  });

  test('B5: child ok follows receipts; parent todos are shared', () async {
    final root = await Directory.systemTemp.createTemp('waifu_b5_');
    addTearDown(() async {
      if (await root.exists()) await root.delete(recursive: true);
    });
    final failLlm = ScriptedWaifuLlm([
      const LlmToolResponse(
        calls: [
          LlmToolCall(
            name: 'task',
            arguments: {
              'subagent': 'general',
              'prompt': 'please write hello.txt',
            },
          ),
        ],
        text: '',
      ),
      const LlmToolResponse(calls: [], text: 'I will write it.'),
      const LlmToolResponse(calls: [], text: 'Still thinking.'),
      const LlmToolResponse(calls: [], text: 'All set.'),
      const LlmToolResponse(calls: [], text: 'Parent wrap.'),
    ]);
    final failSession = WaifuSession(
      folderRoot: root.path,
      coworker: _iris(),
      mode: WaifuMode.yolo,
    );
    await WaifuHarness(session: failSession, llm: failLlm).send('nest a write');
    expect(failSession.toolChips.any((c) => c.name == 'task' && !c.ok), isTrue);

    final shareLlm = ScriptedWaifuLlm([
      const LlmToolResponse(
        calls: [
          LlmToolCall(
            name: 'task',
            arguments: {
              'subagent': 'general',
              'prompt': 'update the todo list',
            },
          ),
        ],
        text: '',
      ),
      const LlmToolResponse(
        calls: [
          LlmToolCall(
            name: 'todowrite',
            arguments: {
              'todos': [
                {'id': 'keep', 'content': 'parent task', 'status': 'completed'},
                {'id': 'child', 'content': 'from child', 'status': 'pending'},
              ],
            },
          ),
        ],
        text: '',
      ),
      const LlmToolResponse(calls: [], text: 'List updated.'),
      const LlmToolResponse(calls: [], text: 'Parent wrap.'),
    ]);
    final share = WaifuSession(
      folderRoot: root.path,
      coworker: _iris(),
      mode: WaifuMode.yolo,
    );
    share.todos.write([
      {'id': 'keep', 'content': 'parent task', 'status': 'pending'},
    ]);
    await WaifuHarness(session: share, llm: shareLlm).send('nest a todo');
    expect(share.todos.items.map((t) => t.id), containsAll(['keep', 'child']));
    expect(share.todos.items.first.status, 'completed');
  });

  test('B5: run-plan-step injects next step verbatim; docs stay serial', () {
    const plan = WaifuPlan(
      id: 'parser',
      slug: 'parser',
      title: 'Fix parser',
      goal: 'cargo test green',
      status: WaifuPlanStatus.accepted,
      steps: [
        WaifuPlanStep(
          id: 's1',
          title: 'Add failing test',
          detail: 'Cover empty input',
          files: ['src/lib.rs', 'tests/empty.rs'],
          verify: 'cargo test --lib',
        ),
      ],
    );
    final wf = waifuMaterializeRunPlanStepWorkflow(plan);
    final mutate = wf.steps.first.agents.single.prompt;
    final verify = wf.steps.last.agents.single.prompt;
    expect(mutate, contains('id: s1'));
    expect(mutate, contains('src/lib.rs'));
    expect(mutate, contains('tests/empty.rs'));
    expect(mutate, contains('cargo test --lib'));
    expect(verify, contains('cargo test --lib'));
    expect(verify, isNot(contains('dart analyze assumed')));
    expect(verify, isNot(contains('flutter test')));
    expect(
      jsonEncode(kWaifuWorkflowToolSchema),
      contains('serial until a real'),
    );
    expect(waifuWorkflowListing(const []), contains('serial today'));
  });

  test(
    'B6: discover prefers accepted, never discarded, pin beats mtime',
    () async {
      final root = await Directory.systemTemp.createTemp('waifu_b6_');
      addTearDown(() async {
        if (await root.exists()) await root.delete(recursive: true);
      });
      final dir = Directory(p.join(root.path, kWaifuPlansDir));
      await dir.create(recursive: true);
      final accepted = File(p.join(dir.path, 'accepted.md'));
      final discarded = File(p.join(dir.path, 'discarded.md'));
      final draft = File(p.join(dir.path, 'draft.md'));
      await accepted.writeAsString(
        waifuPlanEncode(
          const WaifuPlan(
            id: 'accepted',
            slug: 'accepted',
            title: 'Keep me',
            goal: 'real work',
            status: WaifuPlanStatus.accepted,
            relativePath: '.waifu/plans/accepted.md',
          ),
        ),
      );
      await discarded.writeAsString(
        waifuPlanEncode(
          const WaifuPlan(
            id: 'junk',
            slug: 'junk',
            title: 'Throw me',
            goal: 'nope',
            status: WaifuPlanStatus.discarded,
            relativePath: '.waifu/plans/discarded.md',
          ),
        ),
      );
      await draft.writeAsString(
        waifuPlanEncode(
          const WaifuPlan(
            id: 'draft',
            slug: 'draft',
            title: 'Pinned draft',
            goal: 'wip',
            status: WaifuPlanStatus.draft,
            relativePath: '.waifu/plans/draft.md',
          ),
        ),
      );
      final old = DateTime.now().subtract(const Duration(hours: 2));
      await accepted.setLastModified(old);
      await draft.setLastModified(old.add(const Duration(minutes: 1)));
      await discarded.setLastModified(DateTime.now());

      final found = await waifuDiscoverLatestPlan(root.path);
      expect(found, isNotNull);
      expect(found!.status, WaifuPlanStatus.accepted);
      expect(found.relativePath, '.waifu/plans/accepted.md');

      final session = WaifuSession(
        folderRoot: root.path,
        coworker: _iris(),
        activePlanPath: '.waifu/plans/discarded.md',
      );
      final skipDiscarded = await waifuLoadActivePlan(session);
      expect(skipDiscarded!.status, WaifuPlanStatus.accepted);

      session.activePlanPath = '.waifu/plans/draft.md';
      final pinWins = await waifuLoadActivePlan(session);
      expect(pinWins!.status, WaifuPlanStatus.draft);
      expect(pinWins.relativePath, '.waifu/plans/draft.md');
    },
  );

  test(
    'B7: fuse reason is spoken; empty wrap after retries is not theater',
    () {
      final fuse = WaifuTurn.start('loop forever', null);
      expect(fuse.fuseSpeech(), contains('runaway fuse stopped this turn'));
      expect(fuse.failReason, 'runaway fuse stopped this turn');
      expect(fuse.fuseSpeech(), isNot(equals(kWaifuStuckWrap)));

      final turn = WaifuTurn.start('please write hello.txt', null);
      turn.noteResult(
        kWaifuToolWrite,
        WaifuToolResult(
          ok: true,
          output: 'wrote hello.txt',
          write: const WaifuWriteRecord(
            relativePath: 'hello.txt',
            before: '',
            after: 'hi',
          ),
        ),
        const WaifuWriteRecord(
          relativePath: 'hello.txt',
          before: '',
          after: 'hi',
        ),
        args: {'path': 'hello.txt', 'contents': 'hi'},
      );
      turn.noteResult(
        kWaifuToolRead,
        const WaifuToolResult(ok: true, output: 'hi'),
        const WaifuWriteRecord(
          relativePath: 'hello.txt',
          before: '',
          after: 'hi',
        ),
        args: {'path': 'hello.txt'},
      );
      turn.noteResult(
        kWaifuToolBash,
        const WaifuToolResult(ok: true, output: 'ok'),
        const WaifuWriteRecord(
          relativePath: 'hello.txt',
          before: '',
          after: 'hi',
        ),
        args: {'command': 'cargo test'},
      );
      turn.rememberToolSpeech('Hmph. Real words from the tool step.');
      expect(turn.onEmptyCalls(''), WaifuTurnStep.retry);
      expect(turn.onEmptyCalls('Done.'), WaifuTurnStep.retry);
      expect(turn.onEmptyCalls(''), WaifuTurnStep.fail);
      expect(turn.pendingSpeech, kWaifuStuckWrap);
      expect(turn.pendingSpeech, isNot(contains('Real words')));
      expect(turn.failReason, contains('spoken wrap-up'));
      expect(turn.failureLine(''), isNot(contains('Real words')));
    },
  );
}
