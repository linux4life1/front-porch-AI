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

import 'package:front_porch_ai/services/waifu/waifu_session.dart';
import 'package:front_porch_ai/services/waifu/waifu_stage.dart';
import 'package:front_porch_ai/services/waifu/waifu_todos.dart';

final _testCommand = RegExp(
  r'\b(flutter test|dart test|pytest|npm (run )?test|yarn test|pnpm test|'
  r'cargo test|go test|jest|vitest|mvn test|gradle test|ctest)\b',
);

/// What the coworker is doing right now, said with their name, for the line
/// above the composer. Null when no turn is running.
///
/// The running tool wins, then the todo marked in progress, then thinking.
String? waifuStatusLine(WaifuSession session) {
  if (!session.running) return null;
  final name = WaifuStage.of(session).name;
  for (final m in session.transcript.reversed) {
    if (m.kind == WaifuMsgKind.user) break;
    for (final c in m.chips.reversed) {
      if (c.pending) return '$name ${waifuToolDoing(c.name, c.detail)}…';
    }
  }
  for (final t in session.todos.items) {
    if (waifuTodoMark(t.status) == 'in_progress') {
      return '$name is working on: ${_clip(t.content, 60)}';
    }
  }
  return '$name is thinking…';
}

/// "is running tests", "is reading lib/main.dart". OpenCode sends the tool
/// name and, once known, a title that is the path or the command.
String waifuToolDoing(String tool, String detail) {
  final what = detail.trim();
  final known = what.isNotEmpty && what != 'pending' && what != 'running';
  switch (tool.toLowerCase()) {
    case 'bash':
      if (known && _testCommand.hasMatch(what)) return 'is running tests';
      return known ? 'is running ${_clip(what, 48)}' : 'is running a command';
    case 'read':
      return known ? 'is reading ${_clip(what, 48)}' : 'is reading a file';
    case 'edit':
    case 'write':
    case 'patch':
    case 'multiedit':
      return known ? 'is editing ${_clip(what, 48)}' : 'is editing a file';
    case 'glob':
    case 'grep':
    case 'list':
    case 'ls':
      return 'is looking around the project';
    case 'webfetch':
    case 'websearch':
      return 'is reading the web';
    case 'todowrite':
    case 'todoread':
      return 'is updating the plan';
    case 'task':
      return 'is handing off a side task';
    case 'question':
      return 'has a question';
    default:
      return 'is using $tool';
  }
}

String _clip(String s, int max) {
  final one = s.split('\n').first.trim();
  return one.length <= max ? one : '${one.substring(0, max - 1).trimRight()}…';
}
