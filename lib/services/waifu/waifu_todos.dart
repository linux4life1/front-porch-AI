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

const kWaifuTodoPending = 'pending';
const kWaifuTodoInProgress = 'in_progress';
const kWaifuTodoCompleted = 'completed';

class WaifuTodo {
  WaifuTodo({required this.id, required this.content, this.status = 'pending'});

  final String id;
  String content;
  String status;
}

String waifuNormalizeTodoStatus(String? raw) {
  final key = (raw ?? '').trim().toLowerCase().replaceAll(
    RegExp(r'[\s-]+'),
    '_',
  );
  return switch (key) {
    'done' || 'complete' || 'completed' => kWaifuTodoCompleted,
    'in_progress' || 'inprogress' || 'progress' => kWaifuTodoInProgress,
    _ => kWaifuTodoPending,
  };
}

/// Spoken line claims a todo/task was completed — not a generic "done".
bool waifuSpeechClaimsTodoDone(String body) {
  final t = body.toLowerCase();
  if (!RegExp(r'\b(todo|todos|todowrite|task|tasks)\b').hasMatch(t)) {
    return false;
  }
  return RegExp(r'\b(completed|complete|done|finished|marked)\b').hasMatch(t);
}

/// Null when [raw] is not a list (or a once-parsed JSON array).
List<WaifuTodo>? waifuParseTodoWrite(Object? raw) {
  final list = _coerceTodoList(raw);
  if (list == null) return null;
  final out = <WaifuTodo>[];
  for (final e in list) {
    if (e is! Map) continue;
    final id = e['id']?.toString() ?? '${out.length + 1}';
    final content = e['content']?.toString() ?? e['text']?.toString() ?? '';
    if (content.isEmpty) continue;
    out.add(
      WaifuTodo(
        id: id,
        content: content,
        status: waifuNormalizeTodoStatus(e['status']?.toString()),
      ),
    );
  }
  return out;
}

List<dynamic>? _coerceTodoList(Object? raw) {
  if (raw is List) return raw;
  if (raw is String) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return null;
    try {
      final decoded = jsonDecode(trimmed);
      if (decoded is List) return decoded;
      if (decoded is Map && decoded['todos'] is List) {
        return decoded['todos'] as List<dynamic>;
      }
    } catch (_) {}
  }
  return null;
}

class WaifuTodos {
  final items = <WaifuTodo>[];

  String read() {
    if (items.isEmpty) return '(no todos)';
    return items.map((t) => '${t.id} [${t.status}] ${t.content}').join('\n');
  }

  /// Replace the list. Bad shape leaves items unchanged and returns `error:`.
  String write(Object? raw) {
    final parsed = waifuParseTodoWrite(raw);
    if (parsed == null) {
      return 'error: todos must be an array of {id, content, status}';
    }
    items
      ..clear()
      ..addAll(parsed);
    return read();
  }
}
