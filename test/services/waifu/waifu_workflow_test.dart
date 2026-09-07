// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/services/waifu/waifu.dart';
import 'package:path/path.dart' as p;

void main() {
  test('JSON steps parse; Rhai is rejected', () {
    final ok = parseWaifuWorkflow({
      'name': 'audit',
      'description': 'look then speak',
      'steps': [
        {'subagent': 'explore', 'prompt': 'Find bugs'},
        {
          'parallel': [
            {'subagent': 'explore', 'prompt': 'tests {{prev}}'},
            {'subagent': 'explore', 'prompt': 'docs {{prev}}'},
          ],
        },
      ],
    });
    expect(ok.error, isNull);
    expect(ok.workflow!.agentCount, 3);
    expect(waifuFillPrev('see {{prev}}', 'bugs'), 'see bugs');
    expect(waifuWorkflowRhaiReject('review.rhai', null), contains('not Rhai'));
    expect(
      waifuWorkflowRhaiReject('', 'let meta = #{ name: "x" };'),
      contains('Rhai'),
    );
  });

  test('empty folder lists the JSON how-to, not a crash', () async {
    final root = await Directory.systemTemp.createTemp('waifu_wf_empty_');
    addTearDown(() async {
      if (await root.exists()) await root.delete(recursive: true);
    });
    final items = await waifuListWorkflows(root.path);
    expect(items, isEmpty);
    expect(waifuWorkflowListing(items), contains(kWaifuWorkflowDir));
    expect(waifuWorkflowListing(items), contains('Not a Rhai'));
  });

  test(
    'workflow child may delegate once but cannot launch a workflow',
    () async {
      final root = await Directory.systemTemp.createTemp('waifu_wf_run_');
      addTearDown(() async {
        if (await root.exists()) await root.delete(recursive: true);
      });
      final dir = Directory(p.join(root.path, kWaifuWorkflowDir));
      await dir.create(recursive: true);
      await File(p.join(dir.path, 'audit.json')).writeAsString(
        '{"name":"audit","description":"look","steps":['
        '{"subagent":"explore","prompt":"look around"}]}',
      );
      final llm = ScriptedWaifuLlm([
        const LlmToolResponse(
          calls: [
            LlmToolCall(name: 'workflow', arguments: {'name': 'audit'}),
          ],
          text: '',
        ),
        const LlmToolResponse(calls: [], text: 'Explore: empty folder.'),
        const LlmToolResponse(calls: [], text: 'Hmph. Done.'),
      ]);
      final session = WaifuSession(
        folderRoot: root.path,
        coworker: CharacterCard(name: 'Iris'),
        mode: WaifuMode.yolo,
      );
      await WaifuHarness(session: session, llm: llm).send('run audit');
      expect(llm.calls, hasLength(3));
      expect(
        llm.calls[1].tools.map((t) => (t['function'] as Map)['name']).toList(),
        contains(kWaifuToolTask),
      );
      expect(
        llm.calls[1].tools.map((t) => (t['function'] as Map)['name']).toList(),
        isNot(contains(kWaifuToolWorkflow)),
      );
      expect(
        session.toolChips.any((c) => c.name == kWaifuToolWorkflow),
        isTrue,
      );
      expect(waifuWorkflowSlashArgs('/workflow'), isEmpty);
      expect(waifuWorkflowSlashArgs('/workflow audit')!['name'], 'audit');
    },
  );
}
