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

extension _WaifuHarnessSpawn on WaifuHarness {
  WaifuHarness _makeChild({required bool exploreOnly}) {
    final childScope = exploreOnly
        ? WaifuPathMode.folderJail
        : session.pathMode;
    final childSession = WaifuSession(
      folderRoot: session.folderRoot,
      coworker: session.coworker,
      mode: session.mode,
      pathMode: childScope,
      preserveThinking: session.preserveThinking,
      todos: session.todos,
    );
    final childPerms = permissions.fork(mode: childSession.mode)
      ..pathMode = childScope;
    return WaifuHarness(
      session: childSession,
      llm: llm,
      fs: exploreOnly
          ? WaifuFs(session.folderRoot, pathMode: WaifuPathMode.folderJail)
          : fs,
      bash: exploreOnly
          ? WaifuBash(session.folderRoot, pathMode: WaifuPathMode.folderJail)
          : bash,
      undo: undoLog,
      webfetch: webfetch,
      webSearch: webSearch,
      onAsk: onAsk,
      onQuestion: onQuestion,
      onChanged: _emit,
      permissions: childPerms,
      depth: depth + 1,
      exploreOnly: exploreOnly,
      skills: skills,
      mcpTools: mcpTools,
      mcpToolsOf: mcpToolsOf,
      mcpCall: mcpCall,
      mcpCallOf: mcpCallOf,
      mcpOptIn: mcpOptIn,
      // Child must not saveLast over the parent's todos.json.
    );
  }

  String _childSpeech(WaifuHarness child) {
    final out = child.session.transcript
        .where((m) => !m.isUser)
        .map((m) => m.text)
        .join('\n');
    return out.trim().isEmpty ? '(no output)' : out;
  }

  Future<WaifuTurnReceipt> _runNested(String kind, String prompt) async {
    final child = _makeChild(exploreOnly: kind == 'explore');
    _children.add(child);
    try {
      await child.send(prompt);
    } finally {
      _children.remove(child);
    }
    if (child.session.lastWrite != null) {
      session.lastWrite = child.session.lastWrite;
    }
    final receipt = WaifuTurnReceipt(
      speech: _childSpeech(child),
      turn: child._turn,
      ok:
          !child._aborted &&
          child._turn.failReason.isEmpty &&
          child._turn.receiptsReady,
    );
    _turn.absorbChild(receipt.turn);
    return receipt;
  }

  Future<WaifuToolResult> _runTask(
    String? kind,
    Map<String, dynamic> args,
  ) async {
    if (depth >= kWaifuMaxTaskDepth) {
      return WaifuToolResult.error(
        'task: nested worker depth is capped at $kWaifuMaxTaskDepth',
      );
    }
    if (kind != 'explore' && kind != 'general') {
      return WaifuToolResult.error('task: subagent must be explore or general');
    }
    final prompt =
        args['prompt']?.toString() ?? args['description']?.toString() ?? '';
    if (prompt.trim().isEmpty) {
      return WaifuToolResult.error('task: prompt is empty');
    }
    final out = await _runNested(kind!, prompt);
    return WaifuToolResult(ok: out.ok, output: out.speech);
  }

  Future<WaifuToolResult> _runWorkflow(Map<String, dynamic> args) async {
    if (depth > 0) {
      return WaifuToolResult.error(
        'workflow: nested subagents cannot spawn children',
      );
    }
    if (waifuWorkflowWantsList(args)) {
      final items = await waifuListWorkflows(session.folderRoot);
      return WaifuToolResult(ok: true, output: waifuWorkflowListing(items));
    }
    final parsed = await waifuWorkflowFromArgs(session.folderRoot, args);
    if (parsed.error != null) {
      return WaifuToolResult.error(parsed.error!);
    }
    var wf = parsed.workflow!;
    if (wf.name == kWaifuBuiltinRunPlanStep) {
      wf = waifuMaterializeRunPlanStepWorkflow(
        await waifuLoadActivePlan(session),
      );
    }
    final buf = StringBuffer('workflow ${wf.name}\n');
    var prev = '';
    var spent = 0;
    for (var i = 0; i < wf.steps.length; i++) {
      if (_aborted) {
        buf.writeln('stopped');
        return WaifuToolResult(ok: false, output: buf.toString().trim());
      }
      final step = wf.steps[i];
      spent += step.agents.length;
      if (spent > kWaifuWorkflowMaxAgents) {
        buf.writeln('agent budget exhausted');
        return WaifuToolResult(ok: false, output: buf.toString().trim());
      }
      buf.writeln('step ${i + 1}/${wf.steps.length}');
      final out = await _runStep(step, prev);
      prev = out.speech;
      buf.writeln(prev);
      if (!out.ok) {
        return WaifuToolResult(ok: false, output: buf.toString().trim());
      }
    }
    return WaifuToolResult(ok: true, output: buf.toString().trim());
  }

  Future<({String speech, bool ok})> _runStep(
    WaifuWorkflowStep step,
    String prev,
  ) async {
    if (step.agents.length == 1) {
      final a = step.agents.first;
      final out = await _runNested(a.subagent, waifuFillPrev(a.prompt, prev));
      return (speech: out.speech, ok: out.ok);
    }
    // Listed as parallel in JSON; one local model runs them in series.
    // Do not claim concurrent execution until a real parallel engine exists.
    final buf = StringBuffer();
    var ok = true;
    for (var i = 0; i < step.agents.length; i++) {
      if (_aborted) {
        ok = false;
        break;
      }
      final a = step.agents[i];
      final out = await _runNested(a.subagent, waifuFillPrev(a.prompt, prev));
      ok = ok && out.ok;
      buf
        ..writeln('--- ${a.subagent} ${i + 1} ---')
        ..writeln(out.speech);
    }
    return (speech: buf.toString().trim(), ok: ok);
  }

  Future<WaifuToolResult> _answerQuestion(Map<String, dynamic> args) async {
    final req = waifuQuestionFromArgs(args);
    final ask = onQuestion;
    if (ask == null) {
      return WaifuToolResult.error('question: no UI');
    }
    final wait = Completer<String>();
    _questionWait = wait;
    ask(req).then((d) {
      if (!wait.isCompleted) wait.complete(d);
    });
    final answer = await wait.future;
    if (identical(_questionWait, wait)) _questionWait = null;
    if (_aborted || answer.isEmpty) {
      return WaifuToolResult.error('question: cancelled');
    }
    return WaifuToolResult(ok: true, output: 'user chose: $answer');
  }

  Future<WaifuToolResult> _search(String query) async {
    final fn = webSearch;
    if (fn == null) {
      return WaifuToolResult.error('web_search: not available');
    }
    final snippet = await fn(query);
    return WaifuToolResult(
      ok: snippet.trim().isNotEmpty,
      output: 'UNTRUSTED search:\n$snippet',
    );
  }
}
