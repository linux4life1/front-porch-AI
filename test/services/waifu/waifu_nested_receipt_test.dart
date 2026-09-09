// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/llm_service.dart';
import 'package:front_porch_ai/services/waifu/waifu.dart';
import 'package:path/path.dart' as p;

void main() {
  test('absorb copies child mutate receipts onto the parent', () {
    final parent = WaifuTurnContract.start('parent', null);
    parent.readPaths.add('lib/a.dart');
    final child = WaifuTurnContract.start('write lib/b.dart', null);
    child.mutatedPaths.add('lib/b.dart');
    child.readPaths.add('lib/b.dart');
    child.mutationSucceeded = true;
    parent.absorbChild(child);
    expect(parent.mutatedPaths, contains('lib/b.dart'));
    expect(parent.readPaths, contains('lib/b.dart'));
    expect(parent.readPaths, isNot(contains('lib/a.dart')));
  });

  test('nested worker does not saveLast over parent todos.json', () async {
    final root = await Directory.systemTemp.createTemp('waifu_nested_todos_');
    final storeDir = await Directory.systemTemp.createTemp(
      'waifu_nested_store_',
    );
    addTearDown(() async {
      if (await root.exists()) await root.delete(recursive: true);
      if (await storeDir.exists()) await storeDir.delete(recursive: true);
    });
    await File(p.join(root.path, 'notes.txt')).writeAsString('hi');
    final store = WaifuStore(storeDir.path);
    final session = WaifuSession(
      folderRoot: root.path,
      coworker: CharacterCard(name: 'Iris'),
      mode: WaifuMode.yolo,
    );
    session.todos.write([
      {'id': 'keep', 'content': 'parent task', 'status': 'pending'},
    ]);
    await store.saveLast(session);
    final llm = ScriptedWaifuLlm([
      const LlmToolResponse(
        calls: [
          LlmToolCall(
            name: 'task',
            arguments: {'subagent': 'explore', 'prompt': 'look around'},
          ),
        ],
        text: '',
      ),
      const LlmToolResponse(
        calls: [
          LlmToolCall(name: 'glob', arguments: {'pattern': '*'}),
        ],
        text: '',
      ),
      const LlmToolResponse(calls: [], text: 'Saw notes.txt.'),
      const LlmToolResponse(calls: [], text: 'Parent wrap.'),
    ]);
    await WaifuHarness(
      session: session,
      llm: llm,
      store: store,
    ).send('nest a look');
    expect(session.todos.items.single.content, 'parent task');
    final loaded = await store.loadSession(root.path);
    expect(loaded!.todos.items.single.content, 'parent task');
  });
}
