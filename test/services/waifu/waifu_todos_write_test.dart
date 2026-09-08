// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// This file is part of Front Porch AI.
//
// Front Porch AI is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// Front Porch AI is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
// GNU Affero General Public License for more details.
//
// You should have received a copy of the GNU Affero General Public License
// along with Front Porch AI. If not, see <https://www.gnu.org/licenses/>.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/llm_service.dart';
import 'package:front_porch_ai/services/waifu/waifu.dart';

CharacterCard _mira() => CharacterCard(name: 'Mira', personality: 'tsundere');

void main() {
  test('write with completed is visible on read and items', () {
    final todos = WaifuTodos();
    final out = todos.write([
      {'id': '1', 'content': 'add helper', 'status': 'completed'},
    ]);
    expect(out, contains('[completed]'));
    expect(todos.items.single.status, kWaifuTodoCompleted);
    expect(todos.read(), contains('1 [completed] add helper'));
  });

  test('aliases normalize to completed and in_progress', () {
    final todos = WaifuTodos();
    todos.write([
      {'id': '1', 'content': 'one', 'status': 'done'},
      {'id': '2', 'content': 'two', 'status': 'complete'},
      {'id': '3', 'content': 'three', 'status': 'Completed'},
      {'id': '4', 'content': 'four', 'status': 'in-progress'},
    ]);
    expect(todos.items.map((t) => t.status).toList(), [
      kWaifuTodoCompleted,
      kWaifuTodoCompleted,
      kWaifuTodoCompleted,
      kWaifuTodoInProgress,
    ]);
  });

  test('stringified JSON array is parsed once', () {
    final todos = WaifuTodos();
    final out = todos.write(
      '[{"id":"1","content":"add helper","status":"completed"}]',
    );
    expect(out.startsWith('error:'), isFalse);
    expect(todos.items, hasLength(1));
    expect(todos.items.single.status, kWaifuTodoCompleted);
  });

  test('bad non-list args error without wiping prior todos', () {
    final todos = WaifuTodos();
    todos.write([
      {'id': '1', 'content': 'keep me', 'status': 'in_progress'},
    ]);
    final err = todos.write('not-a-list');
    expect(err, startsWith('error:'));
    expect(todos.items, hasLength(1));
    expect(todos.items.single.content, 'keep me');
    expect(todos.items.single.status, kWaifuTodoInProgress);

    expect(todos.write(null), startsWith('error:'));
    expect(todos.write({'todos': 'nope'}), startsWith('error:'));
    expect(todos.items.single.content, 'keep me');
  });

  test('todowrite schema requires status enum', () {
    final tool = waifuFileToolsFor(WaifuPathMode.folderJail).firstWhere((t) {
      final fn = t['function'] as Map;
      return fn['name'] == kWaifuToolTodoWrite;
    });
    final fn = tool['function'] as Map;
    expect(fn['description'], contains('completed'));
    final props = (fn['parameters'] as Map)['properties'] as Map;
    final todos = props['todos'] as Map;
    final item = todos['items'] as Map;
    expect(item['required'], containsAll(['id', 'content', 'status']));
    final status = (item['properties'] as Map)['status'] as Map;
    expect(status['enum'], ['pending', 'in_progress', 'completed']);
  });

  test('harness todowrite completed reaches todos.read', () async {
    final root = await Directory.systemTemp.createTemp('waifu_todos_write_');
    addTearDown(() async {
      if (await root.exists()) await root.delete(recursive: true);
    });
    final session = WaifuSession(
      folderRoot: root.path,
      coworker: _mira(),
      mode: WaifuMode.yolo,
    );
    final llm = ScriptedWaifuLlm([
      const LlmToolResponse(
        calls: [
          LlmToolCall(
            name: 'todowrite',
            arguments: {
              'todos': [
                {'id': '1', 'content': 'add helper', 'status': 'completed'},
                {'id': '2', 'content': 'next', 'status': 'pending'},
              ],
            },
          ),
        ],
        text: '',
      ),
      const LlmToolResponse(calls: [], text: 'First item is completed.'),
    ]);
    final harness = WaifuHarness(session: session, llm: llm);
    await harness.send('finish the first todo');
    expect(harness.todos.items.first.status, kWaifuTodoCompleted);
    expect(harness.todos.read(), contains('[completed]'));
    expect(
      session.toolChips.where((c) => c.name == kWaifuToolTodoWrite),
      hasLength(1),
    );
    expect(session.toolChips.single.ok, isTrue);
  });

  test(
    'harness bad todowrite args fail the tool and keep prior items',
    () async {
      final root = await Directory.systemTemp.createTemp('waifu_todos_bad_');
      addTearDown(() async {
        if (await root.exists()) await root.delete(recursive: true);
      });
      final session = WaifuSession(
        folderRoot: root.path,
        coworker: _mira(),
        mode: WaifuMode.yolo,
      );
      final llm = ScriptedWaifuLlm([
        const LlmToolResponse(
          calls: [
            LlmToolCall(
              name: 'todowrite',
              arguments: {
                'todos': [
                  {'id': '1', 'content': 'keep me', 'status': 'pending'},
                ],
              },
            ),
          ],
          text: '',
        ),
        const LlmToolResponse(
          calls: [
            LlmToolCall(name: 'todowrite', arguments: {'todos': 'oops'}),
          ],
          text: '',
        ),
        const LlmToolResponse(calls: [], text: 'Still tracking keep me.'),
      ]);
      final harness = WaifuHarness(session: session, llm: llm);
      await harness.send('track then botch it');
      expect(harness.todos.items, hasLength(1));
      expect(harness.todos.items.single.content, 'keep me');
      expect(session.toolChips, hasLength(2));
      expect(session.toolChips.first.ok, isTrue);
      expect(session.toolChips.last.ok, isFalse);
      expect(session.toolChips.last.detail.toLowerCase(), contains('error'));
    },
  );
}
