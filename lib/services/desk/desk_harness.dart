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

import 'package:front_porch_ai/services/desk/desk_coworker_prompt.dart';
import 'package:front_porch_ai/services/desk/desk_fs.dart';
import 'package:front_porch_ai/services/desk/desk_honesty.dart';
import 'package:front_porch_ai/services/desk/desk_llm.dart';
import 'package:front_porch_ai/services/desk/desk_session.dart';
import 'package:front_porch_ai/services/desk/desk_tools.dart';
import 'package:path/path.dart' as p;

/// In-process generateWithTools loop. Max [kDeskMaxSteps]. Abort stops
/// further tools; disk is left as the last successful write.
class DeskHarness {
  DeskHarness({
    required this.session,
    required this.llm,
    DeskFs? fs,
    this.onChanged,
  }) : fs = fs ?? DeskFs(session.folderRoot);

  final DeskSession session;
  final DeskLlm llm;
  final DeskFs fs;
  void Function()? onChanged;

  bool _aborted = false;
  String _trace = '';
  final _chips = <DeskToolChip>[];

  bool get isRunning => session.running;

  Future<void> send(String task) async {
    final text = task.trim();
    if (text.isEmpty || session.running) return;
    _aborted = false;
    _trace = '';
    _chips.clear();
    session.running = true;
    session.transcript.add(DeskMessage(isUser: true, text: text));
    _emit();
    try {
      await _loop();
    } finally {
      session.running = false;
      _emit();
    }
  }

  void abort() {
    _aborted = true;
    llm.abort();
    _emit();
  }

  Future<void> _loop() async {
    final system = buildDeskCoworkerPrompt(session.coworker);
    for (var step = 0; step < kDeskMaxSteps; step++) {
      if (_aborted) return;
      final resp = await llm.generate(
        systemPrompt: system,
        prompt: _prompt(),
        tools: kDeskFileTools,
      );
      if (_aborted) return;
      if (resp == null) {
        _say(kDeskToolsUnsupported);
        return;
      }
      if (resp.calls.isEmpty) {
        _say(resp.text.trim().isEmpty ? 'I could not work.' : resp.text.trim());
        return;
      }
      for (final call in resp.calls) {
        if (_aborted) return;
        final result = await fs.dispatch(call.name, call.arguments);
        if (result.write != null) session.lastWrite = result.write;
        final name = canonicalDeskToolName(call.name);
        final detail = result.ok
            ? _okDetail(name, call.arguments, result)
            : result.output;
        _chips.add(DeskToolChip(name: name, detail: detail, ok: result.ok));
        _trace += '\n[$name] ${result.ok ? 'ok' : 'error'}\n${result.output}\n';
        _emit();
      }
    }
    if (!_aborted) {
      _say('Stopped after $kDeskMaxSteps tool steps. Send again to continue.');
    }
  }

  String _okDetail(
    String name,
    Map<String, dynamic> args,
    DeskToolResult result,
  ) {
    if (result.write != null) return result.write!.relativePath;
    final path = deskToolPathArg(args);
    if (path != null) return path;
    return name;
  }

  void _say(String text) {
    session.transcript.add(
      DeskMessage(isUser: false, text: text, chips: List.of(_chips)),
    );
    _chips.clear();
  }

  String _prompt() {
    final buf = StringBuffer()
      ..writeln('Project folder: ${p.basename(session.folderRoot)}')
      ..writeln(
        'Use tools to do the work. Paths are relative to this folder. '
        'When finished, reply in character with no more tool calls.',
      )
      ..writeln();
    for (final m in session.transcript) {
      if (m.isUser) {
        buf.writeln('User: ${m.text}');
      } else {
        buf.writeln('${session.coworker.name}: ${m.text}');
      }
    }
    if (_trace.isNotEmpty) {
      buf
        ..writeln()
        ..writeln('Tool results for this turn:')
        ..writeln(_trace);
    }
    return buf.toString();
  }

  void _emit() => onChanged?.call();
}
