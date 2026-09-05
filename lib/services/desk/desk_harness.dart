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

import 'package:front_porch_ai/services/desk/desk_bash.dart';
import 'package:front_porch_ai/services/desk/desk_compact.dart';
import 'package:front_porch_ai/services/desk/desk_coworker_prompt.dart';
import 'package:front_porch_ai/services/desk/desk_fs.dart';
import 'package:front_porch_ai/services/desk/desk_honesty.dart';
import 'package:front_porch_ai/services/desk/desk_llm.dart';
import 'package:front_porch_ai/services/desk/desk_mentions.dart';
import 'package:front_porch_ai/services/desk/desk_permissions.dart';
import 'package:front_porch_ai/services/desk/desk_question.dart';
import 'package:front_porch_ai/services/desk/desk_session.dart';
import 'package:front_porch_ai/services/desk/desk_skills.dart';
import 'package:front_porch_ai/services/desk/desk_store.dart';
import 'package:front_porch_ai/services/desk/desk_todos.dart';
import 'package:front_porch_ai/services/desk/desk_tools.dart';
import 'package:front_porch_ai/services/desk/desk_undo.dart';
import 'package:front_porch_ai/services/desk/desk_webfetch.dart';
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
    DeskBash? bash,
    DeskUndo? undo,
    DeskTodos? todos,
    this.onQuestion,
    DeskWebFetch? webfetch,
    this.webSearch,
    this.mcpTools = const [],
    this.mcpOptIn = false,
    this.mcpCall,
    this.store,
  }) : fs = fs ?? DeskFs(session.folderRoot),
       webfetch = webfetch ?? DeskWebFetch(),
       permissions = permissions ?? DeskPermissions(mode: session.mode),
       bash = bash ?? DeskBash(session.folderRoot),
       undoLog = undo ?? DeskUndo(),
       todos = todos ?? DeskTodos();

  final DeskSession session;
  final DeskLlm llm;
  final DeskFs fs;
  final DeskPermissions permissions;
  final DeskBash bash;
  final DeskUndo undoLog;
  final DeskTodos todos;
  final DeskWebFetch webfetch;
  final DeskWebSearchFn? webSearch;
  final List<Map<String, dynamic>> mcpTools;
  bool mcpOptIn;
  final DeskMcpCallFn? mcpCall;
  final DeskStore? store;
  void Function()? onChanged;
  DeskAskFn? onAsk;
  DeskQuestionFn? onQuestion;

  bool _aborted = false;
  String _trace = '';
  final _chips = <DeskToolChip>[];
  Completer<DeskAskDecision>? _askWait;
  Completer<String>? _questionWait;
  String _mentionBlock = '';

  bool get isRunning => session.running;
  bool get canUndo => undoLog.canUndo;
  bool get canRedo => undoLog.canRedo;

  Future<void> undo() async {
    final rec = await undoLog.undo(session.folderRoot);
    if (rec == null) return;
    session.lastWrite = rec;
    _emit();
  }

  Future<void> redo() async {
    final rec = await undoLog.redo(session.folderRoot);
    if (rec == null) return;
    session.lastWrite = rec;
    _emit();
  }

  Future<void> send(String task) async {
    final text = task.trim();
    if (text.isEmpty || session.running) return;
    _aborted = false;
    _trace = '';
    _chips.clear();
    session.running = true;
    session.transcript.add(DeskMessage(isUser: true, text: text));
    if (session.title.isEmpty) session.title = deskTitleFrom(text);
    _mentionBlock = await deskExpandMentions(text, session.folderRoot);
    _emit();
    try {
      if (text == '/init' || text.startsWith('/init ')) {
        await _runTool(kDeskToolWrite, {
          'path': kDeskAgentsPath,
          'contents': kDeskAgentsTemplate,
        });
      }
      await _loop();
      final compacted = deskCompactTranscript(session.transcript);
      session.transcript
        ..clear()
        ..addAll(compacted);
      await store?.saveLast(session);
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
    final q = _questionWait;
    if (q != null && !q.isCompleted) q.complete('');
    _emit();
  }

  Future<void> _loop() async {
    final system = buildDeskCoworkerPrompt(session.coworker);
    for (var step = 0; step < kDeskMaxSteps; step++) {
      if (_aborted) return;
      final resp = await llm.generate(
        systemPrompt: system,
        prompt: _prompt(),
        tools: advertisedTools(),
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

  List<Map<String, dynamic>> advertisedTools() {
    return [
      ...kDeskFileTools,
      kDeskWebFetchToolSchema,
      if (webSearch != null) kDeskWebSearchToolSchema,
      if (mcpOptIn) ...mcpTools,
    ];
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
    final result = await _dispatch(canon, args);
    if (result.write != null) {
      session.lastWrite = result.write;
      undoLog.push(result.write!);
    }
    final detail = result.ok ? _okDetail(canon, args, result) : result.output;
    _chips.add(DeskToolChip(name: canon, detail: detail, ok: result.ok));
    _trace += '\n[$canon] ${result.ok ? 'ok' : 'error'}\n${result.output}\n';
    _emit();
  }

  Future<DeskToolResult> _dispatch(
    String canon,
    Map<String, dynamic> args,
  ) async {
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
        final body = await deskLoadSkill(
          session.folderRoot,
          args['name']?.toString() ?? '',
        );
        return DeskToolResult(
          ok: !body.startsWith('skill not found'),
          output: body,
        );
      case kDeskToolWebFetch:
        return webfetch.get(args['url']?.toString() ?? '');
      case kDeskToolWebSearch:
        return _search(args['query']?.toString() ?? '');
      default:
        if (mcpOptIn && mcpCall != null && _mcpNames.contains(canon)) {
          return mcpCall!(canon, args);
        }
        return fs.dispatch(canon, args);
    }
  }

  Future<DeskToolResult> _answerQuestion(Map<String, dynamic> args) async {
    final req = deskQuestionFromArgs(args);
    final ask = onQuestion;
    if (ask == null) {
      return DeskToolResult.error('question: no UI');
    }
    final wait = Completer<String>();
    _questionWait = wait;
    ask(req).then((d) {
      if (!wait.isCompleted) wait.complete(d);
    });
    final answer = await wait.future;
    if (identical(_questionWait, wait)) _questionWait = null;
    if (_aborted || answer.isEmpty) {
      return DeskToolResult.error('question: cancelled');
    }
    return DeskToolResult(ok: true, output: 'user chose: $answer');
  }

  Future<DeskToolResult> _search(String query) async {
    final fn = webSearch;
    if (fn == null) {
      return DeskToolResult.error('web_search: not available');
    }
    final snippet = await fn(query);
    return DeskToolResult(
      ok: snippet.trim().isNotEmpty,
      output: 'UNTRUSTED search:\n$snippet',
    );
  }

  Set<String> get _mcpNames => {
    for (final t in mcpTools)
      ((t['function'] as Map?)?['name'] ?? '').toString(),
  }.difference({''});

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
    if (todos.items.isNotEmpty) {
      buf
        ..writeln('Todos:')
        ..writeln(todos.read())
        ..writeln();
    }
    if (_mentionBlock.isNotEmpty) {
      buf
        ..writeln(_mentionBlock)
        ..writeln();
    }
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
