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

import 'dart:async';

import 'package:front_porch_ai/services/desk/desk_coworker_prompt.dart';
import 'package:front_porch_ai/services/desk/desk_fs.dart';
import 'package:front_porch_ai/services/desk/desk_honesty.dart';
import 'package:front_porch_ai/services/desk/desk_llm.dart';
import 'package:front_porch_ai/services/desk/desk_permissions.dart';
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
    this.onAsk,
    DeskPermissions? permissions,
  }) : fs = fs ?? DeskFs(session.folderRoot),
       permissions = permissions ?? DeskPermissions(mode: session.mode);

  final DeskSession session;
  final DeskLlm llm;
  final DeskFs fs;
  final DeskPermissions permissions;
  void Function()? onChanged;
  DeskAskFn? onAsk;

  bool _aborted = false;
  String _trace = '';
  final _chips = <DeskToolChip>[];
  Completer<DeskAskDecision>? _askWait;

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
    final waiting = _askWait;
    if (waiting != null && !waiting.isCompleted) {
      waiting.complete(DeskAskDecision.deny);
    }
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
        await _runTool(call.name, call.arguments);
      }
    }
    if (!_aborted) {
      _say('Stopped after $kDeskMaxSteps tool steps. Send again to continue.');
    }
  }

  Future<void> _runTool(String name, Map<String, dynamic> args) async {
    permissions.mode = session.mode;
    final canon = canonicalDeskToolName(name);
    final block = permissions.hardBlock(name: name, args: args);
    if (block != null) {
      permissions.record(name: name, args: args);
      _reject(canon, block);
      return;
    }
    if (permissions.needsAsk(name: name, args: args)) {
      final doom = permissions.isDoom(name, args);
      final decision = await _decide(
        DeskAskRequest(
          toolName: canon,
          summary: permissions.summaryFor(name, args),
          doomLoop: doom,
        ),
      );
      if (_aborted) return;
      if (decision == DeskAskDecision.deny) {
        permissions.record(name: name, args: args);
        _reject(canon, 'denied by user');
        return;
      }
      if (decision == DeskAskDecision.allowAlways) {
        permissions.allowAlways();
      }
    }
    permissions.record(name: name, args: args);
    final result = await fs.dispatch(name, args);
    if (result.write != null) session.lastWrite = result.write;
    final detail = result.ok ? _okDetail(canon, args, result) : result.output;
    _chips.add(DeskToolChip(name: canon, detail: detail, ok: result.ok));
    _trace += '\n[$canon] ${result.ok ? 'ok' : 'error'}\n${result.output}\n';
    _emit();
  }

  Future<DeskAskDecision> _decide(DeskAskRequest req) async {
    final ask = onAsk;
    if (ask == null) {
      return req.doomLoop ? DeskAskDecision.deny : DeskAskDecision.allowOnce;
    }
    final wait = Completer<DeskAskDecision>();
    _askWait = wait;
    ask(req).then((d) {
      if (!wait.isCompleted) wait.complete(d);
    });
    final decision = await wait.future;
    if (identical(_askWait, wait)) _askWait = null;
    return decision;
  }

  void _reject(String name, String message) {
    _chips.add(DeskToolChip(name: name, detail: message, ok: false));
    _trace += '\n[$name] error\n$message\n';
    _emit();
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
