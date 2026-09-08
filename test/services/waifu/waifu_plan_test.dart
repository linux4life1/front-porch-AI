// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/services/waifu/waifu.dart';
import 'package:path/path.dart' as p;

CharacterCard _iris() => CharacterCard(
  name: 'Iris',
  personality: 'proud, sharp, and teasing',
  description: 'A meticulous planner who still does the work.',
  systemPrompt: 'End a successful work report with “Obviously.”',
);

const _planMd = '''
---
id: empty-email
slug: empty-email
title: Empty email fix
goal: Make the empty-email test pass
status: draft
assumptions:
- Validator lives in parser.dart
constraints:
- Do not change the public API
risks:
- Hidden callers
openQuestions:
- Null or blank?
steps:
- id: s1
  title: Add failing test
  detail: Cover the empty string
  verify: flutter test test/parser_test.dart
  status: pending
  files:
    - test/parser_test.dart
- id: s2
  title: Fix the parser
  detail: Treat empty as invalid
  verify: flutter test test/parser_test.dart
  status: pending
  files:
    - lib/parser.dart
---

# Empty email fix

Write the test first, then the parser.
''';

void main() {
  late Directory root;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('waifu_plan_');
  });

  tearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });

  test('plan codec round-trips front matter and steps', () {
    final plan = waifuPlanParse(
      _planMd,
      relativePath: '.waifu/plans/empty-email.md',
    );
    expect(plan.slug, 'empty-email');
    expect(plan.title, 'Empty email fix');
    expect(plan.goal, contains('empty-email'));
    expect(plan.status, WaifuPlanStatus.draft);
    expect(plan.assumptions, contains('Validator lives in parser.dart'));
    expect(plan.steps, hasLength(2));
    expect(plan.steps.first.id, 's1');
    expect(plan.steps.first.files, ['test/parser_test.dart']);
    final again = waifuPlanParse(waifuPlanEncode(plan));
    expect(again.title, plan.title);
    expect(again.steps.map((s) => s.id), ['s1', 's2']);
  });

  test('Plan write under .waifu/plans/ lands; lib write is denied', () async {
    await File(p.join(root.path, 'lib', 'parser.dart')).create(recursive: true);
    final llm = ScriptedWaifuLlm([
      const LlmToolResponse(
        calls: [
          LlmToolCall(
            name: 'write',
            arguments: {'path': 'lib/parser.dart', 'contents': 'evil();\n'},
          ),
          LlmToolCall(
            name: 'write',
            arguments: {
              'path': '.waifu/plans/empty-email.md',
              'contents': _planMd,
            },
          ),
        ],
        text: '',
      ),
      const LlmToolResponse(
        calls: [],
        text: 'Hmph. The plan is on the porch. Obviously.',
      ),
    ]);
    final session = WaifuSession(
      folderRoot: root.path,
      coworker: _iris(),
      mode: WaifuMode.plan,
    );
    await WaifuHarness(session: session, llm: llm).send('fix parser.dart');

    expect(
      await File(p.join(root.path, 'lib', 'parser.dart')).readAsString(),
      '',
    );
    final planFile = File(
      p.join(root.path, '.waifu', 'plans', 'empty-email.md'),
    );
    expect(await planFile.exists(), isTrue);
    expect(await planFile.readAsString(), contains('Empty email fix'));
    expect(session.activePlanPath, '.waifu/plans/empty-email.md');
    final chips = session.toolChips;
    expect(chips.any((c) => c.name == 'write' && !c.ok), isTrue);
    expect(chips.any((c) => c.name == 'write' && c.ok), isTrue);
  });

  test('Plan denies symlink and absolute Whole-disk escape', () async {
    final lib = File(p.join(root.path, 'lib', 'secret.dart'))
      ..createSync(recursive: true);
    await lib.writeAsString('keep\n');
    final plans = Directory(p.join(root.path, '.waifu', 'plans'))
      ..createSync(recursive: true);
    final link = Link(p.join(plans.path, 'escape.md'));
    await link.create(lib.path);

    final outside = File(
      p.join(Directory.systemTemp.path, 'waifu_plan_escape.md'),
    );
    if (await outside.exists()) await outside.delete();

    final homeEscape = p.join(
      Platform.environment['HOME'] ?? Directory.systemTemp.path,
      'waifu_plan_home.md',
    );

    final pms = WaifuPermissions(
      mode: WaifuMode.plan,
      workingDirectory: root.path,
    );
    expect(
      pms.hardBlock(
        name: 'write',
        args: {'path': '/tmp/waifu_plan_escape.md', 'contents': 'x'},
      ),
      isNotNull,
    );
    expect(
      pms.hardBlock(
        name: 'write',
        args: {'path': '~/waifu_plan_home.md', 'contents': 'x'},
      ),
      isNotNull,
    );
    expect(
      await waifuPlanWriteLiveBlock(root.path, '.waifu/plans/escape.md'),
      isNotNull,
    );

    final llm = ScriptedWaifuLlm([
      LlmToolResponse(
        calls: [
          LlmToolCall(
            name: 'write',
            arguments: {
              'path': '/tmp/waifu_plan_escape.md',
              'contents': 'escaped\n',
            },
          ),
          LlmToolCall(
            name: 'write',
            arguments: {'path': '~/waifu_plan_home.md', 'contents': 'home\n'},
          ),
          const LlmToolCall(
            name: 'write',
            arguments: {
              'path': '.waifu/plans/escape.md',
              'contents': 'pwned\n',
            },
          ),
        ],
        text: '',
      ),
      const LlmToolResponse(calls: [], text: 'Jail held. Obviously.'),
    ]);
    final session = WaifuSession(
      folderRoot: root.path,
      coworker: _iris(),
      mode: WaifuMode.plan,
      pathMode: WaifuPathMode.wholeDisk,
    );
    await WaifuHarness(session: session, llm: llm).send('plan the escape');

    expect(await lib.readAsString(), 'keep\n');
    expect(await outside.exists(), isFalse);
    expect(File(homeEscape).existsSync(), isFalse);
    expect(session.toolChips.every((c) => !c.ok), isTrue);
  });

  test('no-artifact Plan turn fails the contract', () async {
    final llm = ScriptedWaifuLlm([
      for (var i = 0; i < 3; i++)
        const LlmToolResponse(calls: [], text: 'Hmph. Consider it planned.'),
    ]);
    final session = WaifuSession(
      folderRoot: root.path,
      coworker: _iris(),
      mode: WaifuMode.plan,
    );
    await WaifuHarness(session: session, llm: llm).send('fix parser.dart');

    expect(session.lastWrite, isNull);
    expect(
      Directory(p.join(root.path, '.waifu', 'plans')).existsSync(),
      isFalse,
    );
    final reply = session.transcript.where((m) => !m.isUser).single;
    expect(reply.chips.last.ok, isFalse);
    expect(reply.text, contains('could not write a plan file'));
    expect(reply.text, isNot(contains('Consider it planned')));
    expect(
      llm.calls.skip(1).every((c) => c.prompt.contains('.waifu/plans')),
      isTrue,
    );
  });

  test('Accept → Build injects plan path, digest, and steps', () async {
    final rel = '.waifu/plans/empty-email.md';
    await File(p.join(root.path, rel)).create(recursive: true);
    await File(p.join(root.path, rel)).writeAsString(_planMd);
    final session = WaifuSession(
      folderRoot: root.path,
      coworker: _iris(),
      mode: WaifuMode.plan,
      activePlanPath: rel,
    );
    final llm = ScriptedWaifuLlm([
      const LlmToolResponse(calls: [], text: 'Hmph. I see the accepted plan.'),
    ]);
    final harness = WaifuHarness(session: session, llm: llm);
    final accepted = await harness.acceptActivePlan();
    expect(accepted, isNotNull);
    expect(session.mode, WaifuMode.build);
    expect(session.activePlanPath, rel);
    expect(
      harness.todos.items.map((t) => t.content),
      contains('Add failing test'),
    );
    expect(
      waifuPlanParse(await File(p.join(root.path, rel)).readAsString()).status,
      WaifuPlanStatus.accepted,
    );

    await harness.send('summarize the accepted plan');
    expect(llm.calls, isNotEmpty);
    final prompt = llm.calls.first.prompt;
    expect(prompt, contains('ACCEPTED PLAN'));
    expect(prompt, contains(rel));
    expect(prompt, contains('Empty email fix'));
    expect(prompt, contains(waifuPlanDigest(waifuPlanEncode(accepted!))));
    expect(prompt, contains('Add failing test'));
    expect(prompt, contains('Put code on disk with tools'));
    expect(
      waifuLoopUserPrompt(
        folderName: root.path,
        coworkerName: 'Iris',
        transcript: const [],
        todos: '',
        mentionBlock: '',
        toolTrace: '',
        mode: WaifuMode.plan,
      ),
      isNot(contains('Put code on disk')),
    );
    expect(
      waifuLoopUserPrompt(
        folderName: root.path,
        coworkerName: 'Iris',
        transcript: const [],
        todos: '',
        mentionBlock: '',
        toolTrace: '',
        mode: WaifuMode.plan,
      ),
      contains(kWaifuPlanModeCue),
    );
  });

  test('Plan catalog is honest and todowrite is unlocked', () {
    final tools = waifuAdvertisedTools(
      exploreOnly: false,
      includeWebSearch: false,
      mcpOptIn: false,
      mcpTools: const [],
      includeTask: true,
      includeWorkflow: true,
      mode: WaifuMode.plan,
    );
    final named = <String, String>{
      for (final t in tools)
        (t['function'] as Map)['name'] as String:
            (t['function'] as Map)['description'] as String,
    };
    expect(named.keys, containsAll([kWaifuToolWrite, kWaifuToolTodoWrite]));
    expect(named.keys, isNot(contains(kWaifuToolSkillInstall)));
    expect(named.keys, isNot(contains(kWaifuToolWorkflow)));
    expect(named[kWaifuToolWrite], contains(kWaifuPlansDir));
    expect(named[kWaifuToolBash], contains('read-only'));

    final pms = WaifuPermissions(
      mode: WaifuMode.plan,
      workingDirectory: root.path,
    );
    expect(
      pms.hardBlock(
        name: 'todowrite',
        args: {
          'todos': [
            {'id': '1', 'content': 'draft the plan', 'status': 'pending'},
          ],
        },
      ),
      isNull,
    );
    expect(pms.hardBlock(name: 'bash', args: {'command': 'ls'}), isNull);
    expect(
      pms.hardBlock(name: 'bash', args: {'command': 'rm -rf build'}),
      isNotNull,
    );
  });

  test('Discard clears the pin; Revise returns Plan', () async {
    final rel = '.waifu/plans/empty-email.md';
    await File(p.join(root.path, rel)).create(recursive: true);
    await File(p.join(root.path, rel)).writeAsString(_planMd);
    final session = WaifuSession(
      folderRoot: root.path,
      coworker: _iris(),
      mode: WaifuMode.build,
      activePlanPath: rel,
    );
    final harness = WaifuHarness(
      session: session,
      llm: ScriptedWaifuLlm(const []),
    );
    await harness.reviseActivePlan();
    expect(session.mode, WaifuMode.plan);
    expect(
      waifuPlanParse(await File(p.join(root.path, rel)).readAsString()).status,
      WaifuPlanStatus.draft,
    );
    await harness.discardActivePlan();
    expect(session.activePlanPath, isNull);
    expect(
      waifuPlanParse(await File(p.join(root.path, rel)).readAsString()).status,
      WaifuPlanStatus.discarded,
    );
  });
}
