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

import 'package:flutter/material.dart';

import 'package:front_porch_ai/services/waifu/waifu.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';

class WaifuTodoList extends StatelessWidget {
  const WaifuTodoList({super.key, required this.todos});

  final WaifuTodos todos;

  @override
  Widget build(BuildContext context) {
    if (todos.items.isEmpty) return const SizedBox.shrink();
    return Padding(
      key: const Key('waifu-todos'),
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [for (final t in todos.items) _WaifuTodoRow(todo: t)],
      ),
    );
  }
}

class _WaifuTodoRow extends StatelessWidget {
  const _WaifuTodoRow({required this.todo});

  final WaifuTodo todo;

  @override
  Widget build(BuildContext context) {
    final mark = waifuTodoMark(todo.status);
    final amber = AppColors.porchAmberOf(context);
    final done = mark == 'completed';
    final doing = mark == 'in_progress';
    final color = done
        ? AppColors.textTertiary(context)
        : doing
        ? amber
        : AppColors.textSecondary(context);
    return Padding(
      key: Key('waifu-todo-row-${todo.id}'),
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Semantics(label: mark, child: _markIcon(mark, amber, color)),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              todo.content,
              style: TextStyle(
                color: color,
                fontSize: 13,
                height: 1.3,
                fontWeight: doing ? FontWeight.w600 : FontWeight.w400,
                decoration: done ? TextDecoration.lineThrough : null,
                decorationColor: color,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _markIcon(String mark, Color amber, Color color) {
    return switch (mark) {
      'completed' => Icon(
        Icons.check_box,
        key: Key('waifu-todo-mark-${todo.id}'),
        size: 18,
        color: color,
      ),
      'in_progress' => Icon(
        Icons.play_circle_fill,
        key: Key('waifu-todo-mark-${todo.id}'),
        size: 18,
        color: amber,
      ),
      _ => Icon(
        Icons.check_box_outline_blank,
        key: Key('waifu-todo-mark-${todo.id}'),
        size: 18,
        color: color,
      ),
    };
  }
}
