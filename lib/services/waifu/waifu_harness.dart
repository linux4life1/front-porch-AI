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
import 'package:front_porch_ai/services/waifu/waifu_turn.dart';
import 'package:front_porch_ai/services/waifu/waifu_turn_contract.dart';
import 'package:front_porch_ai/services/waifu/waifu_undo.dart';
import 'package:front_porch_ai/services/waifu/waifu_webfetch.dart';
import 'package:front_porch_ai/services/waifu/waifu_workflow.dart';

part 'waifu_harness_dispatch.dart';
part 'waifu_harness_plan.dart';
part 'waifu_harness_spawn.dart';
part 'waifu_harness_turn.dart';
part 'waifu_harness_compact.dart';

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
    this.mcpToolsOf,
    this.mcpOptIn = false,
    this.mcpCall,
    this.mcpCallOf,
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
             pathMode: session.pathMode,
           ),
       bash = bash ?? WaifuBash(session.folderRoot, pathMode: session.pathMode),
       undoLog = undo ?? WaifuUndo(),
       todos = todos ?? session.todos,
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
  final List<Map<String, dynamic>> Function()? mcpToolsOf;
  bool mcpOptIn;
  final WaifuMcpCallFn? mcpCall;
  final WaifuMcpCallFn? Function()? mcpCallOf;
  final WaifuStore? store;
  final int depth;
  final bool exploreOnly;
  final WaifuSkillHub skills;
  void Function()? onChanged;
  WaifuAskFn? onAsk;
  WaifuQuestionFn? onQuestion;

  bool _aborted = false;
  String _streamBuf = '';
  String _priorReasoning = '';
  Completer<WaifuAskDecision>? _askWait;
  Completer<String>? _questionWait;
  String _mentionBlock = '';
  String _planBlock = '';
  List<String>? _turnImages;
  final _children = <WaifuHarness>[];
  late WaifuTurn _turn;

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
    _turnImages = imagePng == null ? null : [base64Encode(imagePng)];
    _turn = WaifuTurn.start(
      text,
      session.lastWrite,
      mode: session.mode,
      exploreOnly: exploreOnly,
      enforceVerify: depth == 0 && !exploreOnly,
    );
    _clearTurnReceipts();
    // Record the send before any await so live thought chrome can paint.
    session.running = true;
    session.transcript.add(WaifuMessage.user(text, imagePath: imagePath));
    if (session.title.isEmpty) session.title = waifuTitleFrom(text);
    await _refreshPlanBlock();
    _mentionBlock = await waifuExpandMentions(text, session.folderRoot);
    waifuRewriteSlashUser(session.transcript, text);
    await skills.refreshLocal();
    _emit();
    try {
      if (_refuseIfToolsUnsupported()) return;
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
      await _maybeCompact();
      _armBudget();
      await store?.saveLast(session);
    } finally {
      _turnImages = null;
      session.running = false;
      _emit();
    }
  }

  /// `/compact`. LLM recap when there is enough history; always remeters.
  Future<void> compact() async {
    await _maybeCompact(force: true);
    _armBudget();
    await store?.saveLast(session);
    _emit();
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
      final live = _turn.live;
      if (live != null && live.text.trim().isNotEmpty) {
        _turn.live = null;
      }
      _say('Stopped.');
    }
    _emit();
  }

  Future<void> _runTool(String name, Map<String, dynamic> args) async {
    permissions.mode = session.mode;
    permissions.pathMode = session.pathMode;
    final call = WaifuCall.parse(
      name,
      args,
      mcpMutates: waifuMcpMutationHint(name, _mcpToolsNow()),
    );
    final work = call.args;
    final kind = waifuSubagentKind(name, work);
    final canon = call.name;
    _turn.noteAttempt(canon);
    _pushChip(
      WaifuToolChip(
        name: canon,
        detail: waifuChipDetail(canon, work),
        ok: false,
        pending: true,
      ),
    );
    try {
      if (exploreOnly &&
          !kWaifuExploreToolNames.contains(canon) &&
          canon != kWaifuToolTask) {
        permissions.record(name: name, args: work);
        _reject(canon, 'explore is read-only');
        return;
      }
      final verdict = permissions.decide(call, pathMode: session.pathMode);
      switch (verdict.kind) {
        case WaifuDecisionKind.deny:
          permissions.record(name: name, args: work);
          _reject(canon, verdict.reason);
          return;
        case WaifuDecisionKind.ask:
          final doom = permissions.isDoom(name, work);
          final decision = await _decide(
            WaifuAskRequest(
              toolName: canon,
              summary: permissions.summaryFor(name, work),
              why: permissions.whyFor(name: name, args: work, doomLoop: doom),
              doomLoop: doom,
            ),
          );
          if (_aborted) {
            _pushChip(WaifuToolChip(name: canon, detail: 'stopped', ok: false));
            return;
          }
          if (decision == WaifuAskDecision.deny) {
            permissions.record(name: name, args: work);
            _reject(canon, 'denied by user');
            return;
          }
          if (decision == WaifuAskDecision.allowAlways) {
            permissions.allowAlways();
          }
        case WaifuDecisionKind.allow:
          break;
      }
      if (session.mode == WaifuMode.plan &&
          (canon == kWaifuToolWrite ||
              canon == kWaifuToolEdit ||
              canon == kWaifuToolApplyPatch)) {
        final path = call.path;
        final live = path == null
            ? 'plan mode can only write under $kWaifuPlansDir'
            : await waifuPlanWriteLiveBlock(session.folderRoot, path);
        if (live != null) {
          permissions.record(name: name, args: work);
          _reject(canon, live);
          return;
        }
      }
      permissions.record(name: name, args: work);
      final result = switch (canon) {
        kWaifuToolTask => await _runTask(kind, work),
        kWaifuToolWorkflow => await _runWorkflow(work),
        _ => await _dispatch(canon, work, original: name),
      };
      if (_aborted) {
        _pushChip(WaifuToolChip(name: canon, detail: 'stopped', ok: false));
        return;
      }
      if (result.write != null) {
        _noteDiskWrite(result.write!);
      }
      if (session.mode == WaifuMode.plan &&
          result.write != null &&
          waifuRelativeIsPlanArtifact(result.write!.relativePath)) {
        session.activePlanPath = result.write!.relativePath;
      }
      _turn.noteResult(canon, result, session.lastWrite, args: work);
      _noteVerifyReceipt();
      final detail = result.ok
          ? waifuChipDetail(canon, work)
          : waifuClipChipError(result.output);
      _pushChip(WaifuToolChip(name: canon, detail: detail, ok: result.ok));
      _noteToolHistory(canon, result.output, result.ok, path: call.path);
    } catch (e) {
      _reject(canon, '$e');
    } finally {
      _settlePendingChip(canon);
    }
  }

  Set<String> get _mcpNames => {
    for (final t in waifuKeepMcpTools(_mcpToolsNow()))
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
    _noteToolHistory(name, message, false);
  }

  void _pushChip(WaifuToolChip chip) {
    final last = _liveAssistant();
    final chips = List<WaifuToolChip>.from(last.chips);
    if (!chip.pending) {
      final i = chips.lastIndexWhere((c) => c.pending && c.name == chip.name);
      if (i >= 0) {
        chips[i] = chip;
      } else {
        chips.add(chip);
      }
    } else {
      chips.add(chip);
    }
    _writeLive(last.copyWith(chips: chips));
    _emit();
  }

  String _system() => buildWaifuCoworkerPrompt(session.coworker);

  String _prompt() {
    return waifuLoopUserPrompt(
      folderName: session.folderRoot,
      coworkerName: session.coworker.name,
      transcript: session.transcript,
      todos: todos.items.isEmpty ? '' : todos.read(),
      mentionBlock: _mentionBlock,
      toolTrace: '',
      skillBlock: skills.catalogPrompt,
      mcpBlock: mcpOptIn
          ? waifuMcpToolsLine(waifuKeepMcpTools(_mcpToolsNow()))
          : '',
      preserveThinking: session.preserveThinking,
      pathMode: session.pathMode,
      taskDepthRemaining: kWaifuMaxTaskDepth - depth,
      turnContractCue: _safeCue(),
      mode: session.mode,
      planBlock: _planBlock,
    );
  }

  void _emit() => onChanged?.call();
}
