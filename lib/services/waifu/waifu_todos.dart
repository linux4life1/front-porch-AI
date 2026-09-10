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

import 'dart:convert';
import 'dart:io';

import 'package:front_porch_ai/services/waifu/waifu_brand.dart';
import 'package:path/path.dart' as p;

const kWaifuTodosRel = '$kWaifuDotDir/todos.json';

String? waifuTodoCanonicalStatus(String raw) {
  switch (raw.trim().toLowerCase().replaceAll('-', '_')) {
    case 'completed':
    case 'complete':
    case 'done':
      return 'completed';
    case 'in_progress':
    case 'doing':
    case 'active':
      return 'in_progress';
    case 'pending':
    case 'todo':
      return 'pending';
    default:
      return null;
  }
}

String? waifuTodoWriteError(Object? raw) {
  if (raw is! List) return 'todowrite: todos must be an array of objects';
  for (final e in raw) {
    if (e is! Map) return 'todowrite: each item must be an object';
    final id = e['id']?.toString().trim() ?? '';
    final content = (e['content'] ?? e['text'])?.toString().trim() ?? '';
    final status = e['status']?.toString();
    if (id.isEmpty) return 'todowrite: each item needs id';
    if (content.isEmpty) return 'todowrite: each item needs content';
    if (status == null || status.trim().isEmpty) {
      return 'todowrite: each item needs status';
    }
    if (waifuTodoCanonicalStatus(status) == null) {
      return 'todowrite: status must be pending, in_progress, or completed';
    }
  }
  return null;
}

bool waifuTodoStatusIsDone(String status) {
  switch (status.trim().toLowerCase()) {
    case 'completed':
    case 'complete':
    case 'done':
      return true;
    default:
      return false;
  }
}

class WaifuTodo {
  WaifuTodo({required this.id, required this.content, this.status = 'pending'});

  final String id;
  String content;
  String status;
}

/// Display kind only. [WaifuTodos.write] still stores the raw status string.
String waifuTodoMark(String raw) {
  switch (raw.trim().toLowerCase().replaceAll('-', '_')) {
    case 'completed':
    case 'complete':
    case 'done':
      return 'completed';
    case 'in_progress':
    case 'doing':
    case 'active':
      return 'in_progress';
    default:
      return 'pending';
  }
}

class WaifuTodos {
  final items = <WaifuTodo>[];

  String read() {
    if (items.isEmpty) return '(no todos)';
    return items.map((t) => '${t.id} [${t.status}] ${t.content}').join('\n');
  }

  String write(Object? raw) {
    items.clear();
    final list = raw is List ? raw : const [];
    for (final e in list) {
      if (e is! Map) continue;
      final id = e['id']?.toString() ?? '${items.length + 1}';
      final content = e['content']?.toString() ?? e['text']?.toString() ?? '';
      if (content.isEmpty) continue;
      items.add(
        WaifuTodo(
          id: id,
          content: content,
          status:
              waifuTodoCanonicalStatus(e['status']?.toString() ?? '') ??
              'pending',
        ),
      );
    }
    return read();
  }

  List<Map<String, String>> toJson() => [
    for (final t in items)
      {'id': t.id, 'content': t.content, 'status': t.status},
  ];
}

File waifuTodosFile(String folderRoot) =>
    File(p.join(folderRoot, kWaifuDotDir, 'todos.json'));

/// Sit-down folder copy. Claude keeps session state in a hidden project
/// folder; this is that file for the task list.
Future<void> waifuSaveTodos(String folderRoot, WaifuTodos todos) async {
  final file = waifuTodosFile(folderRoot);
  await file.parent.create(recursive: true);
  await file.writeAsString(
    const JsonEncoder.withIndent('  ').convert(todos.toJson()),
  );
}

Future<void> waifuLoadTodos(String folderRoot, WaifuTodos todos) async {
  final file = waifuTodosFile(folderRoot);
  if (!await file.exists()) return;
  try {
    final decoded = jsonDecode(await file.readAsString());
    if (decoded is List) todos.write(decoded);
  } catch (_) {}
}
