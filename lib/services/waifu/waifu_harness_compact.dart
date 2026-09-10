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
  String _safeCue() {
    try {
      return _turn.cue;
    } catch (_) {
      return '';
    }
  }

  List<Map<String, dynamic>> _mcpToolsNow() {
    try {
      return List<Map<String, dynamic>>.from(mcpToolsOf?.call() ?? mcpTools);
    } catch (_) {
      return mcpTools;
    }
  }

  WaifuMcpCallFn? _mcpCallNow() {
    try {
      return mcpCallOf?.call() ?? mcpCall;
    } catch (_) {
      return mcpCall;
    }
  }

  List<Map<String, dynamic>> _advertisedTools({required bool speechOnly}) {
    if (speechOnly) return const <Map<String, dynamic>>[];
    return waifuAdvertisedTools(
      exploreOnly: exploreOnly,
      includeWebSearch: webSearch != null,
      mcpOptIn: mcpOptIn,
      mcpTools: _mcpToolsNow(),
      includeTask: depth < kWaifuMaxTaskDepth,
      includeWorkflow: depth == 0,
      pathMode: session.pathMode,
      mode: session.mode,
    );
  }

  void _pruneTraces() {
    waifuPruneOldToolMessages(
      session.transcript,
      budget: session.contextBudget,
    );
  }

  WaifuBudgetSnapshot _measureLive({
    List<Map<String, dynamic>>? tools,
    List<String>? images,
    LlmToolResponse? resp,
    String streamed = '',
  }) {
    return waifuMeasureRequest(
      systemPrompt: _system(),
      prompt: waifuMessagesMeterText(_openaiMessages()),
      budget: session.contextBudget,
      tools: tools ?? _advertisedTools(speechOnly: false),
      images: images ?? _turnImages,
      promptTokens: resp?.promptTokens,
      completionTokens: resp?.completionTokens,
      totalTokens: resp?.totalTokens,
      streamed: streamed,
    );
  }

  void _armBudget({List<Map<String, dynamic>>? tools, List<String>? images}) {
    final snap = _measureLive(tools: tools, images: images);
    if (!session.tokensFromApi || session.tokensUsed < 1) {
      session.tokensUsed = snap.used;
      session.tokensFromApi = snap.fromApi;
      return;
    }
    if (snap.used > session.tokensUsed) {
      session.tokensUsed = snap.used;
      session.tokensFromApi = false;
    }
  }

  int _remainingTokens({
    required List<Map<String, dynamic>> tools,
    List<String>? images,
  }) {
    return waifuOutputTokenBudget(
      budget: session.contextBudget,
      used: _measureLive(tools: tools, images: images).used,
    );
  }

  Future<void> _warmIdleMeter() async {
    try {
      await _refreshPlanBlock();
      await skills.refreshLocal();
    } catch (_) {}
    if (_aborted || session.running) return;
    refreshMeter();
  }

  void _applyUsage(LlmToolResponse resp) {
    final used = resp.usedTokens;
    if (used == null || used < 1) return;
    session.tokensUsed = used;
    session.tokensFromApi = true;
  }

  Future<void> _maybeCompact({bool force = false}) async {
    _pruneTraces();
    if (!force) {
      final live = _measureLive(tools: _advertisedTools(speechOnly: false))
          .used;
      final used = session.tokensFromApi && session.tokensUsed > 0
          ? (session.tokensUsed > live ? session.tokensUsed : live)
          : live;
      if (!waifuShouldCompact(used: used, budget: session.contextBudget)) {
        return;
      }
    }
    await _compactNow(force: force);
  }

  Future<void> _compactNow({required bool force}) async {
    final msgs = session.transcript;
    waifuPruneOldToolMessages(
      msgs,
      budget: session.contextBudget,
      protectTokens: kWaifuCompactToolProtectTokens,
    );
    final cut = waifuCompactTailIndex(msgs);
    final folded = cut > 0 ? msgs.sublist(0, cut) : <WaifuMessage>[];
    final recent = cut > 0 ? msgs.sublist(cut) : List<WaifuMessage>.from(msgs);
    var recap = '';
    final ledger = folded.isEmpty
        ? ''
        : waifuMachineLedger(
            folded: folded,
            planPin: session.activePlanPath,
            todos: todos.read(),
          );
    if (folded.isNotEmpty) {
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
      try {
        final resp = await llm.generate(
          systemPrompt: kWaifuCompactSystem,
          prompt: waifuCompactUserPrompt(
            foldedSpeech: speech,
            previousRecap: prev,
            ledger: ledger,
          ),
          tools: const [],
          maxTokens: kWaifuCompactOutputTokens,
          forceTool: false,
        );
        final summary = waifuVisibleText(resp?.text ?? '').trim();
        recap = summary.isEmpty ? '' : '$kWaifuCompactPrefix\n$summary';
      } catch (_) {
        recap = '';
      }
    }
    if (folded.isNotEmpty && recap.isEmpty) {
      recap = waifuCompactTranscript(folded, force: true, keep: 0).first.text;
    }
    if (folded.isNotEmpty) {
      recap = waifuInjectMachineLedger(recap, ledger);
    }
    session.transcript
      ..clear()
      ..addAll([if (folded.isNotEmpty) WaifuMessage.recap(recap), ...recent]);
    session.compactPasses++;
    try {
      _turn.live = null;
    } catch (_) {}
    if (force) {
      session.transcript.add(const WaifuMessage.assistant('Folded old turns.'));
    }
    session.tokensFromApi = false;
    _emit();
  }
}
