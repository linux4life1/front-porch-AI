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

import 'package:front_porch_ai/services/services.dart' show LlmToolResponse;
import 'package:front_porch_ai/services/waifu/waifu_bash.dart';
import 'package:front_porch_ai/services/waifu/waifu_compact.dart';
import 'package:front_porch_ai/services/waifu/waifu_coworker_prompt.dart';
import 'package:front_porch_ai/services/waifu/waifu_fs.dart';
import 'package:front_porch_ai/services/waifu/waifu_honesty.dart';
import 'package:front_porch_ai/services/waifu/waifu_llm.dart';
import 'package:front_porch_ai/services/waifu/waifu_mcp_filter.dart';
import 'package:front_porch_ai/services/waifu/waifu_mentions.dart';
import 'package:front_porch_ai/services/waifu/waifu_permissions.dart';
import 'package:front_porch_ai/services/waifu/waifu_plan.dart';
import 'package:front_porch_ai/services/waifu/waifu_plan_codec.dart';
import 'package:front_porch_ai/services/waifu/waifu_question.dart';
import 'package:front_porch_ai/services/waifu/waifu_session.dart';
import 'package:front_porch_ai/services/waifu/waifu_skill_market.dart';
import 'package:front_porch_ai/services/waifu/waifu_skills.dart';
import 'package:front_porch_ai/services/waifu/waifu_sit_down.dart';
import 'package:front_porch_ai/services/waifu/waifu_slash.dart';
import 'package:front_porch_ai/services/waifu/waifu_store.dart';
import 'package:front_porch_ai/services/waifu/waifu_stream.dart';
import 'package:front_porch_ai/services/waifu/waifu_subagent.dart';
import 'package:front_porch_ai/services/waifu/waifu_todos.dart';
import 'package:front_porch_ai/services/waifu/waifu_tools.dart';
import 'package:front_porch_ai/services/waifu/waifu_turn_contract.dart';
import 'package:front_porch_ai/services/waifu/waifu_undo.dart';
import 'package:front_porch_ai/services/waifu/waifu_webfetch.dart';
import 'package:front_porch_ai/services/waifu/waifu_workflow.dart';

part 'waifu_harness_dispatch.dart';
part 'waifu_harness_plan.dart';
part 'waifu_harness_spawn.dart';
part 'waifu_harness_turn.dart';

/// In-process generateWithTools loop. Max [kWaifuMaxSteps]. Abort stops
/// further tools; disk is left as the last successful write.
class WaifuHarness {
  WaifuHarness({
    required this.session,
    required this.llm,
    WaifuFs? fs,
    this.onChanged,
    this.onAsk,
    WaifuPermissions? permissions,
    WaifuBash? bash,
    WaifuUndo? undo,
    WaifuTodos? todos,
    this.onQuestion,
    WaifuWebFetch? webfetch,
    this.webSearch,
    this.mcpTools = const [],
    this.mcpOptIn = false,
    this.mcpCall,
    this.store,
    this.depth = 0,
    this.exploreOnly = false,
    WaifuSkillHub? skills,
  }) : fs = fs ?? WaifuFs(session.folderRoot, pathMode: session.pathMode),
       webfetch = webfetch ?? WaifuWebFetch(),
       permissions =
           permissions ??
           WaifuPermissions(
             mode: session.mode,
             workingDirectory: session.folderRoot,
           ),
       bash = bash ?? WaifuBash(session.folderRoot, pathMode: session.pathMode),
       undoLog = undo ?? WaifuUndo(),
       todos = todos ?? WaifuTodos(),
       skills = skills ?? WaifuSkillHub(projectRoot: session.folderRoot);

  final WaifuSession session;
  final WaifuLlm llm;
  final WaifuFs fs;
  final WaifuPermissions permissions;
  final WaifuBash bash;
  final WaifuUndo undoLog;
  final WaifuTodos todos;
  final WaifuWebFetch webfetch;
  final WaifuWebSearchFn? webSearch;
  final List<Map<String, dynamic>> mcpTools;
  bool mcpOptIn;
  final WaifuMcpCallFn? mcpCall;
  final WaifuStore? store;
  final int depth;
  final bool exploreOnly;
  final WaifuSkillHub skills;
  void Function()? onChanged;
  WaifuAskFn? onAsk;
  WaifuQuestionFn? onQuestion;

  bool _aborted = false;
  int? _stepAt;
  String _trace = '';
  String _streamBuf = '';
  String _priorReasoning = '';
  Completer<WaifuAskDecision>? _askWait;
  Completer<String>? _questionWait;
  String _mentionBlock = '';
  String _planBlock = '';
  List<String>? _turnImages;
  final _children = <WaifuHarness>[];
  late WaifuTurnContract _turn;

  bool get isRunning => session.running;
  bool get canUndo => undoLog.canUndo;
  bool get canRedo => undoLog.canRedo;

  Future<void> undo() async {
    final rec = await undoLog.undo(
      session.folderRoot,
      pathMode: session.pathMode,
    );
    if (rec == null) return;
    session.lastWrite = rec;
    _emit();
  }

  Future<void> redo() async {
    final rec = await undoLog.redo(
      session.folderRoot,
      pathMode: session.pathMode,
    );
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
    _turn = WaifuTurnContract.start(
      text,
      session.lastWrite,
      mode: session.mode,
      exploreOnly: exploreOnly,
    );
    await _refreshPlanBlock();
    session.running = true;
    session.transcript.add(
      WaifuMessage(isUser: true, text: text, imagePath: imagePath),
    );
    if (session.title.isEmpty) session.title = waifuTitleFrom(text);
    _mentionBlock = await waifuExpandMentions(text, session.folderRoot);
    waifuRewriteSlashUser(session.transcript, text);
    await skills.refreshLocal();
    _emit();
    try {
      if (text == '/init' || text.startsWith('/init ')) {
        await _runTool(kWaifuToolWrite, {
          'path': kWaifuAgentsPath,
          'contents': kWaifuAgentsTemplate,
        });
      }
      final wf = waifuWorkflowSlashArgs(text);
      if (wf != null) {
        await _runTool(kWaifuToolWorkflow, wf);
      }
      await _loop();
      final compacted = waifuCompactTranscript(session.transcript);
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
    for (final c in List<WaifuHarness>.from(_children)) {
      c.abort();
    }
    llm.abort();
    bash.abort();
    final waiting = _askWait;
    if (waiting != null && !waiting.isCompleted) {
      waiting.complete(WaifuAskDecision.deny);
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
    _emit();
  }

  Future<void> _runTool(String name, Map<String, dynamic> args) async {
    permissions.mode = session.mode;
    final work = waifuNormalizeToolArgs(name, args);
    final kind = waifuSubagentKind(name, work);
    final canon = canonicalWaifuToolName(name);
    _turn.noteAttempt(canon);
    final mcpMutates = waifuMcpMutationHint(name, mcpTools);
    if (exploreOnly &&
        !kWaifuExploreToolNames.contains(canon) &&
        canon != kWaifuToolTask) {
      permissions.record(name: name, args: work);
      _reject(canon, 'explore is read-only');
      return;
    }
    final block = permissions.hardBlock(
      name: name,
      args: work,
      mutates: mcpMutates,
    );
    if (block != null) {
      permissions.record(name: name, args: work);
      _reject(canon, block);
      return;
    }
    if (session.mode == WaifuMode.plan &&
        (canon == kWaifuToolWrite ||
            canon == kWaifuToolEdit ||
            canon == kWaifuToolApplyPatch)) {
      final path = waifuToolPathArg(work);
      final live = path == null
          ? 'plan mode can only write under $kWaifuPlansDir'
          : await waifuPlanWriteLiveBlock(session.folderRoot, path);
      if (live != null) {
        permissions.record(name: name, args: work);
        _reject(canon, live);
        return;
      }
    }
    if (permissions.needsAsk(name: name, args: work, mutates: mcpMutates)) {
      final doom = permissions.isDoom(name, work);
      final decision = await _decide(
        WaifuAskRequest(
          toolName: canon,
          summary: permissions.summaryFor(name, work),
          doomLoop: doom,
        ),
      );
      if (_aborted) return;
      if (decision == WaifuAskDecision.deny) {
        permissions.record(name: name, args: work);
        _reject(canon, 'denied by user');
        return;
      }
      if (decision == WaifuAskDecision.allowAlways) {
        permissions.allowAlways();
      }
    }
    permissions.record(name: name, args: work);
    final result = switch (canon) {
      kWaifuToolTask => await _runTask(kind, work),
      kWaifuToolWorkflow => await _runWorkflow(work),
      _ => await _dispatch(canon, work, original: name),
    };
    if (_aborted) return;
    if (result.write != null) {
      session.lastWrite = result.write;
      undoLog.push(result.write!);
    }
    if (session.mode == WaifuMode.plan &&
        result.write != null &&
        waifuRelativeIsPlanArtifact(result.write!.relativePath)) {
      session.activePlanPath = result.write!.relativePath;
    }
    _turn.noteResult(canon, result, session.lastWrite);
    final detail = result.ok
        ? waifuChipDetail(canon, work)
        : waifuClipChipError(result.output);
    _pushChip(WaifuToolChip(name: canon, detail: detail, ok: result.ok));
    _trace += '\n[$canon] ${result.ok ? 'ok' : 'error'}\n${result.output}\n';
  }

  Set<String> get _mcpNames => {
    for (final t in waifuKeepMcpTools(mcpTools))
      ((t['function'] as Map?)?['name'] ?? '').toString(),
  }.difference({''});

  Future<WaifuAskDecision> _decide(WaifuAskRequest req) async {
    final ask = onAsk;
    if (ask == null) {
      return req.doomLoop ? WaifuAskDecision.deny : WaifuAskDecision.allowOnce;
    }
    final wait = Completer<WaifuAskDecision>();
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
      WaifuToolChip(name: name, detail: waifuClipChipError(message), ok: false),
    );
    _trace += '\n[$name] error\n$message\n';
  }

  void _pushChip(WaifuToolChip chip) {
    final last = _liveAssistant();
    _writeLive(
      WaifuMessage(
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

  WaifuMessage _liveAssistant() {
    final i = _stepAt;
    if (i != null &&
        i >= 0 &&
        i < session.transcript.length &&
        !session.transcript[i].isUser) {
      return session.transcript[i];
    }
    session.transcript.add(const WaifuMessage(isUser: false, text: ''));
    _stepAt = session.transcript.length - 1;
    return session.transcript.last;
  }

  void _writeLive(WaifuMessage msg) {
    final i = _stepAt ?? session.transcript.length - 1;
    session.transcript[i] = msg;
  }

  void _beginStream() {
    _streamBuf = '';
    _priorReasoning = '';
    _writeLive(
      waifuBeginStream(_liveAssistant(), DateTime.now().millisecondsSinceEpoch),
    );
    _emit();
  }

  void _onChunk(String chunk) {
    if (_aborted || chunk.isEmpty) return;
    _streamBuf += chunk;
    _writeLive(
      waifuApplyChunk(
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
      waifuEndStream(_liveAssistant(), DateTime.now().millisecondsSinceEpoch),
    );
    _emit();
  }

  void _noteReasoning(LlmToolResponse resp) {
    final next = waifuMergeReasoning(_liveAssistant(), resp);
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
        WaifuMessage(
          isUser: false,
          text: text,
          chips: last.chips,
          reasoning: last.reasoning,
          thinkingStartMs: last.thinkingStartMs,
          thinkingMs: last.thinkingMs,
        ),
      );
    } else {
      session.transcript.add(WaifuMessage(isUser: false, text: text));
      _stepAt = session.transcript.length - 1;
    }
    _emit();
  }

  String _system() => buildWaifuCoworkerPrompt(session.coworker);

  void _setBudget(String system, String prompt) {
    final snap = waifuMeasurePrompt(
      systemPrompt: system,
      prompt: prompt,
      budget: session.contextBudget,
    );
    session.tokensUsed = snap.used;
  }

  String _prompt() {
    return waifuLoopUserPrompt(
      folderName: session.folderRoot,
      coworkerName: session.coworker.name,
      transcript: session.transcript,
      todos: todos.items.isEmpty ? '' : todos.read(),
      mentionBlock: _mentionBlock,
      toolTrace: _trace,
      skillBlock: skills.catalogPrompt,
      mcpBlock: mcpOptIn ? waifuMcpToolsLine(waifuKeepMcpTools(mcpTools)) : '',
      preserveThinking: session.preserveThinking,
      pathMode: session.pathMode,
      taskDepthRemaining: kWaifuMaxTaskDepth - depth,
      turnContractCue: _turn.cue,
      mode: session.mode,
      planBlock: _planBlock,
    );
  }

  void _emit() => onChanged?.call();
}
