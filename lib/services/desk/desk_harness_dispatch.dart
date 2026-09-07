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

part of 'desk_harness.dart';

extension _DeskHarnessDispatch on DeskHarness {
  Future<DeskToolResult> _dispatch(
    String canon,
    Map<String, dynamic> args, {
    String original = '',
  }) async {
    switch (canon) {
      case kDeskToolBash:
        return bash.run(args);
      case kDeskToolTodoRead:
        return DeskToolResult(ok: true, output: todos.read());
      case kDeskToolTodoWrite:
        return DeskToolResult(ok: true, output: todos.write(args['todos']));
      case kDeskToolQuestion:
        return _answerQuestion(args);
      case kDeskToolSkill:
        final body = await skills.load(args['name']?.toString() ?? '');
        return DeskToolResult(
          ok: !body.startsWith('skill not found'),
          output: body,
        );
      case kDeskToolSkillInstall:
        final out = await skills.install(args['name']?.toString() ?? '');
        return DeskToolResult(ok: out.startsWith('installed'), output: out);
      case kDeskToolWebFetch:
        return webfetch.get(args['url']?.toString() ?? '');
      case kDeskToolWebSearch:
        return _search(args['query']?.toString() ?? '');
      default:
        final raw = original.isEmpty ? canon : original;
        if (deskMcpNameBlocked(raw) || deskMcpNameBlocked(canon)) {
          return fs.dispatch(canon, args);
        }
        if (mcpOptIn &&
            mcpCall != null &&
            (_mcpNames.contains(raw) || _mcpNames.contains(canon))) {
          final result = await mcpCall!(raw, args);
          return DeskToolResult(
            ok: result.ok,
            output: deskSanitizeMcpOutput(result.output),
            write: result.write,
          );
        }
        return fs.dispatch(canon, args);
    }
  }
}
