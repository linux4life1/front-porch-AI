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

extension _DeskHarnessSpawn on DeskHarness {
  DeskHarness _makeChild({required bool exploreOnly}) {
    final childSession = DeskSession(
      folderRoot: session.folderRoot,
      coworker: session.coworker,
      mode: exploreOnly ? DeskMode.plan : session.mode,
      preserveThinking: session.preserveThinking,
    );
    return DeskHarness(
      session: childSession,
      llm: llm,
      fs: fs,
      bash: bash,
      undo: undoLog,
      webfetch: webfetch,
      webSearch: webSearch,
      onAsk: onAsk,
      onQuestion: onQuestion,
      onChanged: _emit,
      permissions: DeskPermissions(mode: childSession.mode),
      depth: 1,
      exploreOnly: exploreOnly,
      skills: skills,
      mcpTools: mcpTools,
      mcpCall: mcpCall,
      mcpOptIn: mcpOptIn,
    );
  }

  String _childSpeech(DeskHarness child) {
    final out = child.session.transcript
        .where((m) => !m.isUser)
        .map((m) => m.text)
        .join('\n');
    return out.trim().isEmpty ? '(no output)' : out;
  }

  Future<String> _runNested(String kind, String prompt) async {
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
    return _childSpeech(child);
  }

  Future<DeskToolResult> _runTask(
    String? kind,
    Map<String, dynamic> args,
  ) async {
    if (depth > 0) {
      return DeskToolResult.error(
        'task: nested subagents cannot spawn children',
      );
    }
    if (kind != 'explore' && kind != 'general') {
      return DeskToolResult.error('task: subagent must be explore or general');
    }
    final prompt =
        args['prompt']?.toString() ?? args['description']?.toString() ?? '';
    if (prompt.trim().isEmpty) {
      return DeskToolResult.error('task: prompt is empty');
    }
    final out = await _runNested(kind!, prompt);
    return DeskToolResult(ok: true, output: out);
  }

  Future<DeskToolResult> _runWorkflow(Map<String, dynamic> args) async {
    if (depth > 0) {
      return DeskToolResult.error(
        'workflow: nested subagents cannot spawn children',
      );
    }
    if (deskWorkflowWantsList(args)) {
      final items = await deskListWorkflows(session.folderRoot);
      return DeskToolResult(ok: true, output: deskWorkflowListing(items));
    }
    final parsed = await deskWorkflowFromArgs(session.folderRoot, args);
    if (parsed.error != null) {
      return DeskToolResult.error(parsed.error!);
    }
    final wf = parsed.workflow!;
    final buf = StringBuffer('workflow ${wf.name}\n');
    var prev = '';
    var spent = 0;
    for (var i = 0; i < wf.steps.length; i++) {
      if (_aborted) {
        buf.writeln('stopped');
        return DeskToolResult(ok: false, output: buf.toString().trim());
      }
      final step = wf.steps[i];
      spent += step.agents.length;
      if (spent > kDeskWorkflowMaxAgents) {
        buf.writeln('agent budget exhausted');
        return DeskToolResult(ok: false, output: buf.toString().trim());
      }
      buf.writeln('step ${i + 1}/${wf.steps.length}');
      prev = await _runStep(step, prev);
      buf.writeln(prev);
    }
    return DeskToolResult(ok: true, output: buf.toString().trim());
  }

  Future<String> _runStep(DeskWorkflowStep step, String prev) async {
    if (step.agents.length == 1) {
      final a = step.agents.first;
      return _runNested(a.subagent, deskFillPrev(a.prompt, prev));
    }
    // Independent prompts, same {{prev}}. One local model — run in
    // series so generates do not collide.
    final buf = StringBuffer();
    for (var i = 0; i < step.agents.length; i++) {
      if (_aborted) break;
      final a = step.agents[i];
      final out = await _runNested(a.subagent, deskFillPrev(a.prompt, prev));
      buf
        ..writeln('--- ${a.subagent} ${i + 1} ---')
        ..writeln(out);
    }
    return buf.toString().trim();
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
}
