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

extension _WaifuHarnessCompact on WaifuHarness {
  bool _isLiveAssistantAt(int i) {
    if (i < 0 || i >= session.transcript.length) return false;
    final m = session.transcript[i];
    return !m.isUser && !m.hidden;
  }

  String _safeCue() {
    try {
      return _turn.cue;
    } catch (_) {
      return '';
    }
  }

  List<Map<String, dynamic>> _advertisedTools({required bool speechOnly}) {
    if (speechOnly) return const <Map<String, dynamic>>[];
    return waifuAdvertisedTools(
      exploreOnly: exploreOnly,
      includeWebSearch: webSearch != null,
      mcpOptIn: mcpOptIn,
      mcpTools: mcpTools,
      includeTask: depth < kWaifuMaxTaskDepth,
      includeWorkflow: depth == 0,
      pathMode: session.pathMode,
      mode: session.mode,
    );
  }

  void _pruneTraces() {
    final next = waifuPruneToolTraces(
      session.toolTraces,
      budget: session.contextBudget,
    );
    if (identical(next, session.toolTraces)) return;
    session.toolTraces
      ..clear()
      ..addAll(next);
  }

  WaifuBudgetSnapshot _measureLive({
    List<Map<String, dynamic>>? tools,
    LlmToolResponse? resp,
    String streamed = '',
  }) {
    return waifuMeasureRequest(
      systemPrompt: _system(),
      prompt: _prompt(),
      budget: session.contextBudget,
      tools: tools ?? _advertisedTools(speechOnly: false),
      promptTokens: resp?.promptTokens,
      completionTokens: resp?.completionTokens,
      totalTokens: resp?.totalTokens,
      streamed: streamed,
    );
  }

  void _armBudget({List<Map<String, dynamic>>? tools}) {
    final snap = _measureLive(tools: tools);
    session.tokensUsed = snap.used;
    session.tokensFromApi = snap.fromApi;
  }

  void _applyUsage(LlmToolResponse resp) {
    final used = resp.usedTokens;
    if (used == null || used < 1) return;
    session.tokensUsed = used;
    session.tokensFromApi = true;
  }

  Future<void> _maybeCompact({bool force = false}) async {
    if (_aborted) return;
    _pruneTraces();
    if (session.transcript.length <= kWaifuCompactKeep) {
      if (force) _emit();
      return;
    }
    if (!force) {
      final used = waifuFillUsed(
        tokensUsed: session.tokensUsed,
        fromApi: session.tokensFromApi,
        estimated: _measureLive().used,
      );
      if (!waifuShouldCompact(used: used, budget: session.contextBudget)) {
        return;
      }
    }
    await _compactNow(force: force);
  }

  Future<void> _compactNow({required bool force}) async {
    final keep = kWaifuCompactKeep;
    if (session.transcript.length <= keep) return;
    final folded = session.transcript.sublist(
      0,
      session.transcript.length - keep,
    );
    final recent = session.transcript.sublist(session.transcript.length - keep);
    final prev = folded
        .where((m) => m.text.startsWith(kWaifuCompactPrefix))
        .map((m) => m.text)
        .join('\n');
    final speech = folded
        .where((m) => !m.text.startsWith(kWaifuCompactPrefix))
        .map(
          (m) => waifuPromptSpeech(
            m,
            session.coworker.name,
            preserveThinking: false,
          ),
        )
        .where((s) => s.isNotEmpty)
        .join('\n');
    String recap;
    try {
      final resp = await llm.generate(
        systemPrompt: kWaifuCompactSystem,
        prompt: waifuCompactUserPrompt(
          foldedSpeech: speech,
          previousRecap: prev,
        ),
        tools: const [],
        maxTokens: kWaifuCompactOutputTokens,
      );
      final summary = waifuVisibleText(resp?.text ?? '').trim();
      recap = summary.isEmpty ? '' : '$kWaifuCompactPrefix\n$summary';
    } catch (_) {
      recap = '';
    }
    if (_aborted) return;
    if (recap.isEmpty) {
      session.transcript
        ..clear()
        ..addAll(
          waifuCompactTranscript(
            [...folded, ...recent],
            force: true,
            keep: keep,
          ),
        );
    } else {
      session.transcript
        ..clear()
        ..add(WaifuMessage(isUser: false, text: recap, hidden: true))
        ..addAll(recent);
    }
    session.compactPasses++;
    _stepAt = null;
    if (force) {
      session.transcript.add(
        const WaifuMessage(isUser: false, text: 'Folded old turns.'),
      );
    }
    session.tokensFromApi = false;
    _emit();
  }
}
