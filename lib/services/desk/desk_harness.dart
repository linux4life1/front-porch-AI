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
import 'dart:convert';
import 'dart:typed_data';

import 'package:front_porch_ai/services/desk/desk_bash.dart';
import 'package:front_porch_ai/services/desk/desk_compact.dart';
import 'package:front_porch_ai/services/desk/desk_coworker_prompt.dart';
import 'package:front_porch_ai/services/desk/desk_fs.dart';
import 'package:front_porch_ai/services/desk/desk_honesty.dart';
import 'package:front_porch_ai/services/desk/desk_llm.dart';
import 'package:front_porch_ai/services/desk/desk_mcp_filter.dart';
import 'package:front_porch_ai/services/desk/desk_mentions.dart';
import 'package:front_porch_ai/services/desk/desk_permissions.dart';
import 'package:front_porch_ai/services/desk/desk_question.dart';
import 'package:front_porch_ai/services/desk/desk_session.dart';
import 'package:front_porch_ai/services/desk/desk_skill_market.dart';
import 'package:front_porch_ai/services/desk/desk_skills.dart';
import 'package:front_porch_ai/services/desk/desk_sit_down.dart';
import 'package:front_porch_ai/services/desk/desk_slash.dart';
import 'package:front_porch_ai/services/desk/desk_store.dart';
import 'package:front_porch_ai/services/desk/desk_stream.dart';
import 'package:front_porch_ai/services/desk/desk_subagent.dart';
import 'package:front_porch_ai/services/desk/desk_todos.dart';
import 'package:front_porch_ai/services/desk/desk_tools.dart';
import 'package:front_porch_ai/services/desk/desk_undo.dart';
import 'package:front_porch_ai/services/desk/desk_webfetch.dart';
import 'package:front_porch_ai/services/desk/desk_workflow.dart';
import 'package:front_porch_ai/services/llm_service.dart';

part 'desk_harness_dispatch.dart';
part 'desk_harness_spawn.dart';

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
    this.depth = 0,
    this.exploreOnly = false,
    DeskSkillHub? skills,
  }) : fs = fs ?? DeskFs(session.folderRoot),
       webfetch = webfetch ?? DeskWebFetch(),
       permissions = permissions ?? DeskPermissions(mode: session.mode),
       bash = bash ?? DeskBash(session.folderRoot),
       undoLog = undo ?? DeskUndo(),
       todos = todos ?? DeskTodos(),
       skills = skills ?? DeskSkillHub(projectRoot: session.folderRoot);

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
  final int depth;
  final bool exploreOnly;
  final DeskSkillHub skills;
  void Function()? onChanged;
  DeskAskFn? onAsk;
  DeskQuestionFn? onQuestion;

  bool _aborted = false;
  int? _stepAt;
  String _trace = '';
  String _streamBuf = '';
  String _priorReasoning = '';
  Completer<DeskAskDecision>? _askWait;
  Completer<String>? _questionWait;
  String _mentionBlock = '';
  List<String>? _turnImages;
  final _children = <DeskHarness>[];

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

  Future<void> send(
    String task, {
    Uint8List? imagePng,
    String? imagePath,
  }) async {
    var text = task.trim();
    if ((text.isEmpty && imagePng == null) || session.running) return;
    if (text.isEmpty) text = '(photo)';
    _aborted = false;
    _stepAt = null;
    _trace = '';
    _turnImages = imagePng == null ? null : [base64Encode(imagePng)];
    session.running = true;
    session.transcript.add(
      DeskMessage(isUser: true, text: text, imagePath: imagePath),
    );
    if (session.title.isEmpty) session.title = deskTitleFrom(text);
    _mentionBlock = await deskExpandMentions(text, session.folderRoot);
    deskRewriteSlashUser(session.transcript, text);
    await skills.refreshLocal();
    _emit();
    try {
      if (text == '/init' || text.startsWith('/init ')) {
        await _runTool(kDeskToolWrite, {
          'path': kDeskAgentsPath,
          'contents': kDeskAgentsTemplate,
        });
      }
      final wf = deskWorkflowSlashArgs(text);
      if (wf != null) {
        await _runTool(kDeskToolWorkflow, wf);
      }
      await _loop();
      final compacted = deskCompactTranscript(session.transcript);
      session.transcript
        ..clear()
        ..addAll(compacted);
      _setBudget(_system(), _prompt());
      await store?.saveLast(session);
    } finally {
      _turnImages = null;
      session.running = false;
      _emit();
    }
  }

  void abort() {
    _aborted = true;
    for (final c in List<DeskHarness>.from(_children)) {
      c.abort();
    }
    llm.abort();
    final waiting = _askWait;
    if (waiting != null && !waiting.isCompleted) {
      waiting.complete(DeskAskDecision.deny);
    }
    final q = _questionWait;
    if (q != null && !q.isCompleted) q.complete('');
    if (session.running) {
      final i = _stepAt;
      final keep =
          i != null &&
          i < session.transcript.length &&
          !session.transcript[i].isUser &&
          session.transcript[i].text.trim().isNotEmpty;
      if (keep) _stepAt = null;
      _say('Stopped.');
    }
    session.running = false;
    _emit();
  }

  Future<void> _loop() async {
    final system = _system();
    for (var step = 0; step < kDeskMaxSteps; step++) {
      if (_aborted) return;
      _beginStream();
      final prompt = _prompt();
      _setBudget(system, prompt);
      final resp = await llm.generate(
        systemPrompt: system,
        prompt: prompt,
        tools: deskAdvertisedTools(
          exploreOnly: exploreOnly,
          includeWebSearch: webSearch != null,
          mcpOptIn: mcpOptIn,
          mcpTools: mcpTools,
          includeTask: depth == 0,
        ),
        images: step == 0 ? _turnImages : null,
        onChunk: _onChunk,
      );
      _endStream();
      if (_aborted) return;
      if (resp == null) {
        _say(kDeskToolsUnsupported);
        return;
      }
      _noteReasoning(resp);
      final body = deskVisibleText(resp.text);
      if (resp.calls.isEmpty) {
        _say(body.isEmpty ? 'I could not work.' : body);
        return;
      }
      if (body.isNotEmpty) _say(body);
      for (final call in resp.calls) {
        if (_aborted) return;
        await _runTool(call.name, call.arguments);
      }
      _stepAt = null;
    }
    if (!_aborted) {
      _say('Stopped after $kDeskMaxSteps tool steps. Send again to continue.');
    }
  }

  Future<void> _runTool(String name, Map<String, dynamic> args) async {
    permissions.mode = session.mode;
    final work = deskNormalizeToolArgs(name, args);
    final kind = deskSubagentKind(name, work);
    final canon = canonicalDeskToolName(name);
    if (exploreOnly && !kDeskExploreToolNames.contains(canon)) {
      permissions.record(name: name, args: work);
      _reject(canon, 'explore is read-only');
      return;
    }
    final block = permissions.hardBlock(name: name, args: work);
    if (block != null) {
      permissions.record(name: name, args: work);
      _reject(canon, block);
      return;
    }
    if (permissions.needsAsk(name: name, args: work)) {
      final doom = permissions.isDoom(name, work);
      final decision = await _decide(
        DeskAskRequest(
          toolName: canon,
          summary: permissions.summaryFor(name, work),
          doomLoop: doom,
        ),
      );
      if (_aborted) return;
      if (decision == DeskAskDecision.deny) {
        permissions.record(name: name, args: work);
        _reject(canon, 'denied by user');
        return;
      }
      if (decision == DeskAskDecision.allowAlways) {
        permissions.allowAlways();
      }
    }
    permissions.record(name: name, args: work);
    final result = switch (canon) {
      kDeskToolTask => await _runTask(kind, work),
      kDeskToolWorkflow => await _runWorkflow(work),
      _ => await _dispatch(canon, work, original: name),
    };
    if (result.write != null) {
      session.lastWrite = result.write;
      undoLog.push(result.write!);
    }
    final detail = result.ok
        ? deskChipDetail(canon, work)
        : deskClipChipError(result.output);
    _pushChip(DeskToolChip(name: canon, detail: detail, ok: result.ok));
    _trace += '\n[$canon] ${result.ok ? 'ok' : 'error'}\n${result.output}\n';
  }

  Set<String> get _mcpNames => {
    for (final t in deskKeepMcpTools(mcpTools))
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
    _pushChip(
      DeskToolChip(name: name, detail: deskClipChipError(message), ok: false),
    );
    _trace += '\n[$name] error\n$message\n';
  }

  void _pushChip(DeskToolChip chip) {
    final last = _liveAssistant();
    _writeLive(
      DeskMessage(
        isUser: false,
        text: last.text,
        chips: [...last.chips, chip],
        reasoning: last.reasoning,
        thinkingStartMs: last.thinkingStartMs,
        thinkingMs: last.thinkingMs,
      ),
    );
    _emit();
  }

  DeskMessage _liveAssistant() {
    final i = _stepAt;
    if (i != null &&
        i >= 0 &&
        i < session.transcript.length &&
        !session.transcript[i].isUser) {
      return session.transcript[i];
    }
    session.transcript.add(const DeskMessage(isUser: false, text: ''));
    _stepAt = session.transcript.length - 1;
    return session.transcript.last;
  }

  void _writeLive(DeskMessage msg) {
    final i = _stepAt ?? session.transcript.length - 1;
    session.transcript[i] = msg;
  }

  void _beginStream() {
    session.transcript.add(const DeskMessage(isUser: false, text: ''));
    _stepAt = session.transcript.length - 1;
    _priorReasoning = '';
    _streamBuf = '';
    _writeLive(
      deskBeginStream(_liveAssistant(), DateTime.now().millisecondsSinceEpoch),
    );
    _emit();
  }

  void _onChunk(String chunk) {
    if (_aborted || chunk.isEmpty) return;
    _streamBuf += chunk;
    _writeLive(
      deskApplyChunk(
        last: _liveAssistant(),
        priorReasoning: _priorReasoning,
        streamBuf: _streamBuf,
      ),
    );
    _emit();
  }

  void _endStream() {
    if (_aborted) return;
    _writeLive(
      deskEndStream(_liveAssistant(), DateTime.now().millisecondsSinceEpoch),
    );
    _emit();
  }

  void _noteReasoning(LlmToolResponse resp) {
    final next = deskMergeReasoning(_liveAssistant(), resp);
    if (next == null) return;
    _writeLive(next);
    _emit();
  }

  void _say(String text) {
    final i = _stepAt;
    if (i != null &&
        i >= 0 &&
        i < session.transcript.length &&
        !session.transcript[i].isUser) {
      final last = session.transcript[i];
      _writeLive(
        DeskMessage(
          isUser: false,
          text: text,
          chips: last.chips,
          reasoning: last.reasoning,
          thinkingStartMs: last.thinkingStartMs,
          thinkingMs: last.thinkingMs,
        ),
      );
    } else {
      session.transcript.add(DeskMessage(isUser: false, text: text));
      _stepAt = session.transcript.length - 1;
    }
    _emit();
  }

  String _system() => buildDeskCoworkerPrompt(session.coworker);

  void _setBudget(String system, String prompt) {
    final snap = deskMeasurePrompt(
      systemPrompt: system,
      prompt: prompt,
      budget: session.contextBudget,
    );
    session.tokensUsed = snap.used;
  }

  String _prompt() {
    return deskLoopUserPrompt(
      folderName: session.folderRoot,
      coworkerName: session.coworker.name,
      transcript: session.transcript,
      todos: todos.items.isEmpty ? '' : todos.read(),
      mentionBlock: _mentionBlock,
      toolTrace: _trace,
      skillBlock: skills.catalogPrompt,
      mcpBlock: mcpOptIn ? deskMcpToolsLine(deskKeepMcpTools(mcpTools)) : '',
      preserveThinking: session.preserveThinking,
    );
  }

  void _emit() => onChanged?.call();
}
