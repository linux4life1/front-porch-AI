// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/desk/desk.dart';
import 'package:front_porch_ai/services/llm_service.dart';
import 'package:path/path.dart' as p;

void main() {
  test('JSON steps parse; Rhai is rejected', () {
    final ok = parseDeskWorkflow({
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
    expect(deskFillPrev('see {{prev}}', 'bugs'), 'see bugs');
    expect(deskWorkflowRhaiReject('review.rhai', null), contains('not Rhai'));
    expect(
      deskWorkflowRhaiReject('', 'let meta = #{ name: "x" };'),
      contains('Rhai'),
    );
  });

  test('empty folder lists the JSON how-to, not a crash', () async {
    final root = await Directory.systemTemp.createTemp('desk_wf_empty_');
    addTearDown(() async {
      if (await root.exists()) await root.delete(recursive: true);
    });
    final items = await deskListWorkflows(root.path);
    expect(items, isEmpty);
    expect(deskWorkflowListing(items), contains(kDeskWorkflowDir));
    expect(deskWorkflowListing(items), contains('Not a Rhai'));
  });

  test('saved JSON workflow runs nested explore, not a grandchild', () async {
    final root = await Directory.systemTemp.createTemp('desk_wf_run_');
    addTearDown(() async {
      if (await root.exists()) await root.delete(recursive: true);
    });
    final dir = Directory(p.join(root.path, kDeskWorkflowDir));
    await dir.create(recursive: true);
    await File(p.join(dir.path, 'audit.json')).writeAsString(
      '{"name":"audit","description":"look","steps":['
      '{"subagent":"explore","prompt":"look around"}]}',
    );
    final llm = ScriptedDeskLlm([
      const LlmToolResponse(
        calls: [
          LlmToolCall(name: 'workflow', arguments: {'name': 'audit'}),
        ],
        text: '',
      ),
      const LlmToolResponse(calls: [], text: 'Explore: empty folder.'),
      const LlmToolResponse(calls: [], text: 'Hmph. Done.'),
    ]);
    final session = DeskSession(
      folderRoot: root.path,
      coworker: CharacterCard(name: 'Iris'),
      mode: DeskMode.yolo,
    );
    await DeskHarness(session: session, llm: llm).send('run audit');
    expect(llm.calls, hasLength(3));
    expect(
      llm.calls[1].tools.map((t) => (t['function'] as Map)['name']).toList(),
      isNot(contains(kDeskToolTask)),
    );
    expect(session.toolChips.any((c) => c.name == kDeskToolWorkflow), isTrue);
    expect(deskWorkflowSlashArgs('/workflow'), isEmpty);
    expect(deskWorkflowSlashArgs('/workflow audit')!['name'], 'audit');
  });
}
