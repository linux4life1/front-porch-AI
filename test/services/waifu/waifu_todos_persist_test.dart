// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Proven red: saveLast/loadSession dropped the task list, and sitting
// down again on the same folder minted empty WaifuTodos. Progress gone.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/services/waifu/waifu.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory dir;
  late Directory project;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('waifu_todos_persist_');
    project = await Directory(p.join(dir.path, 'app')).create();
  });

  tearDown(() async {
    if (await dir.exists()) await dir.delete(recursive: true);
  });

  WaifuSession session() => WaifuSession(
    folderRoot: project.path,
    coworker: CharacterCard(name: 'Iris'),
    title: 'epub reader',
  );

  test('saveLast round-trips pending and completed todos', () async {
    final store = WaifuStore(dir.path);
    final s = session();
    s.todos.write([
      {'id': '1', 'content': 'Create SPM package', 'status': 'completed'},
      {'id': '2', 'content': 'Create EPUB Engine', 'status': 'in_progress'},
      {'id': '3', 'content': 'Create Reader UI', 'status': 'pending'},
    ]);
    await store.saveLast(s);

    final loaded = await store.loadSession(project.path);
    expect(loaded, isNotNull);
    expect(loaded!.todos.items, hasLength(3));
    expect(loaded.todos.items[0].status, 'completed');
    expect(loaded.todos.items[1].content, 'Create EPUB Engine');
    expect(loaded.todos.items[2].status, 'pending');
    expect(await waifuTodosFile(project.path).exists(), isTrue);
  });

  test(
    'sit-down folder file restores todos when session JSON has none',
    () async {
      final todos = WaifuTodos()
        ..write([
          {'id': '1', 'content': 'Wire App entry', 'status': 'pending'},
        ]);
      await waifuSaveTodos(project.path, todos);
      final store = WaifuStore(dir.path);
      await store.saveLast(session());
      // Empty session JSON would have wiped the file; put the list back
      // the way a previous sit-down left `.waifu/todos.json`.
      await waifuSaveTodos(project.path, todos);

      final loaded = await store.loadSession(project.path);
      expect(loaded!.todos.items, hasLength(1));
      expect(loaded.todos.items.single.content, 'Wire App entry');
    },
  );

  test('harness todowrite lands in .waifu/todos.json via store', () async {
    await File(p.join(project.path, 'notes.txt')).writeAsString('old');
    final store = WaifuStore(dir.path);
    final s = session();
    final llm = ScriptedWaifuLlm([
      const LlmToolResponse(
        calls: [
          LlmToolCall(
            name: 'todowrite',
            arguments: {
              'todos': [
                {'id': '1', 'content': 'add helper', 'status': 'pending'},
              ],
            },
          ),
        ],
        text: '',
      ),
      const LlmToolResponse(calls: [], text: 'Hmph. The list is up.'),
    ]);
    await WaifuHarness(
      session: s,
      llm: llm,
      store: store,
    ).send('plan the helper');
    expect(s.todos.items, hasLength(1));
    final loaded = await store.loadSession(project.path);
    expect(loaded!.todos.items.single.content, 'add helper');
    final onDisk = await waifuTodosFile(project.path).readAsString();
    expect(onDisk, contains('add helper'));
  });
}
