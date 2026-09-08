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

part of 'waifu_harness.dart';

extension _WaifuHarnessDispatch on WaifuHarness {
  Future<WaifuToolResult> _dispatch(
    String canon,
    Map<String, dynamic> args, {
    String original = '',
  }) async {
    switch (canon) {
      case kWaifuToolBash:
        return bash.run(args);
      case kWaifuToolTodoRead:
        return WaifuToolResult(ok: true, output: todos.read());
      case kWaifuToolTodoWrite:
        final out = todos.write(args['todos']);
        await waifuSyncTodosOntoPlan(session: session, todos: todos);
        return WaifuToolResult(ok: true, output: out);
      case kWaifuToolQuestion:
        return _answerQuestion(args);
      case kWaifuToolSkill:
        final body = await skills.load(args['name']?.toString() ?? '');
        return WaifuToolResult(
          ok: !body.startsWith('skill not found'),
          output: body,
        );
      case kWaifuToolSkillInstall:
        final out = await skills.install(args['name']?.toString() ?? '');
        return WaifuToolResult(ok: out.startsWith('installed'), output: out);
      case kWaifuToolWebFetch:
        return webfetch.get(args['url']?.toString() ?? '');
      case kWaifuToolWebSearch:
        return _search(args['query']?.toString() ?? '');
      default:
        final raw = original.isEmpty ? canon : original;
        if (kWaifuFsToolNames.contains(canon)) {
          return fs.dispatch(canon, args);
        }
        if (waifuMcpNameBlocked(raw) || waifuMcpNameBlocked(canon)) {
          return fs.dispatch(canon, args);
        }
        if (mcpOptIn &&
            mcpCall != null &&
            (_mcpNames.contains(raw) || _mcpNames.contains(canon))) {
          final result = await mcpCall!(raw, args);
          return WaifuToolResult(
            ok: result.ok,
            output: waifuSanitizeMcpOutput(result.output),
            write: result.write,
          );
        }
        return fs.dispatch(canon, args);
    }
  }
}
