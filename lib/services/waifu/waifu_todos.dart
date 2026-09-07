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

class WaifuTodo {
  WaifuTodo({required this.id, required this.content, this.status = 'pending'});

  final String id;
  String content;
  String status;
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
          status: e['status']?.toString() ?? 'pending',
        ),
      );
    }
    return read();
  }
}
