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

import 'dart:convert';

import 'package:front_porch_ai/services/waifu/waifu_brand.dart';
import 'package:front_porch_ai/services/waifu/waifu_session.dart';
import 'package:front_porch_ai/services/waifu/waifu_tools.dart';
import 'package:front_porch_ai/services/waifu/waifu_turn_contract.dart';

const kWaifuTranscriptBudgetChars = 12000;
const kWaifuCompactKeep = 8;

/// Tool bodies kept on a fold. The rest stub. 25% of a 277k window was ~70k.
const kWaifuCompactToolProtectTokens = 4000;
const kWaifuRecapClipChars = 1500;
const kWaifuCompactAt = 0.75;
const kWaifuDefaultContextTokens = 8192;
const kWaifuCompactOutputTokens = 4096;
const kWaifuPruneProtectMaxTokens = 40000;
const kWaifuPruneMinimumTokens = 2000;
const kWaifuCompactPrefix = '[Session compact]';
const kWaifuExtractiveRecapPrefix = 'Earlier recap:';

/// Recap lines are not spoken by the user or the coworker.
bool waifuIsPromptRecap(WaifuMessage m) => m.kind == WaifuMsgKind.recap;

/// Fallback only — the bar prefers server `usage` when the backend sent it.
int waifuEstimateTokens(String text) {
  if (text.isEmpty) return 0;
  return (text.length / 4).ceil();
}

int waifuEstimateToolsTokens(List<Map<String, dynamic>> tools) {
  if (tools.isEmpty) return 0;
  return waifuEstimateTokens(jsonEncode(tools));
}

/// Photo parts on every generate of the send. Floor 85 per image so a
/// tiny PNG still counts; larger base64 rides chars/4 like the rest.
int waifuEstimateImageTokens(List<String>? images) {
  if (images == null || images.isEmpty) return 0;
  var n = 0;
  for (final img in images) {
    final guess = waifuEstimateTokens(img);
    n += guess < 85 ? 85 : guess;
  }
  return n;
}

int waifuPruneProtectTokens(int budget) {
  final cap = budget < 1 ? kWaifuDefaultContextTokens : budget;
  var protect = (cap * 0.25).round();
  if (protect < 2000) protect = 2000;
  if (protect > kWaifuPruneProtectMaxTokens) {
    protect = kWaifuPruneProtectMaxTokens;
  }
  return protect;
}

class WaifuBudgetSnapshot {
  const WaifuBudgetSnapshot({
    required this.used,
    required this.budget,
    this.fromApi = false,
  });

  final int used;
  final int budget;
  final bool fromApi;
  double get fill => budget <= 0 ? 0 : used / budget;
  bool get shouldCompact => fill >= kWaifuCompactAt;
}

bool waifuShouldCompact({required int used, required int budget}) {
  final cap = budget < 1 ? kWaifuDefaultContextTokens : budget;
  if (cap <= 0) return false;
  return used >= (cap * kWaifuCompactAt).ceil();
}

/// Same number the sidebar bar shows: API usage when we have it.
int waifuFillUsed({
  required int tokensUsed,
  required bool fromApi,
  required int estimated,
}) => fromApi && tokensUsed > 0 ? tokensUsed : estimated;

/// System + user + advertised tools. [totalTokens] / [promptTokens] from
/// the last API `usage` win over the chars/4 guess.
WaifuBudgetSnapshot waifuMeasureRequest({
  required String systemPrompt,
  required String prompt,
  required int budget,
  List<Map<String, dynamic>> tools = const [],
  List<String>? images,
  int? promptTokens,
  int? completionTokens,
  int? totalTokens,
  String streamed = '',
}) {
  final cap = budget < 1 ? kWaifuDefaultContextTokens : budget;
  if (totalTokens != null && totalTokens > 0) {
    return WaifuBudgetSnapshot(used: totalTokens, budget: cap, fromApi: true);
  }
  if (promptTokens != null && promptTokens > 0) {
    final completion = completionTokens ?? waifuEstimateTokens(streamed);
    return WaifuBudgetSnapshot(
      used: promptTokens + completion,
      budget: cap,
      fromApi: true,
    );
  }
  return WaifuBudgetSnapshot(
    used:
        waifuEstimateTokens(systemPrompt) +
        waifuEstimateTokens(prompt) +
        waifuEstimateToolsTokens(tools) +
        waifuEstimateImageTokens(images) +
        waifuEstimateTokens(streamed),
    budget: cap,
  );
}

WaifuBudgetSnapshot waifuMeasurePrompt({
  required String systemPrompt,
  required String prompt,
  required int budget,
}) => waifuMeasureRequest(
  systemPrompt: systemPrompt,
  prompt: prompt,
  budget: budget,
);

/// How many tokens this turn may write. Not the chat Max Output Tokens
/// slider (2048 default) — that cuts tool calls mid-file. The window
/// itself is the cap.
int waifuOutputTokenBudget({required int budget, required int used}) {
  final cap = budget < 1 ? kWaifuDefaultContextTokens : budget;
  final left = cap - used;
  return left < 1 ? 1 : left;
}

/// OpenCode-style: keep the newest tool output, stub the rest.
List<String> waifuPruneToolTraces(List<String> traces, {required int budget}) {
  if (traces.isEmpty) return const [];
  final protect = waifuPruneProtectTokens(budget);
  var kept = 0;
  var pruneFrom = -1;
  for (var i = traces.length - 1; i >= 0; i--) {
    kept += waifuEstimateTokens(traces[i]);
    if (kept > protect) {
      pruneFrom = i;
      break;
    }
  }
  if (pruneFrom < 0) return List<String>.from(traces);
  var saved = 0;
  final out = List<String>.from(traces);
  for (var i = 0; i <= pruneFrom; i++) {
    if (out[i].contains('(pruned)')) continue;
    final tokens = waifuEstimateTokens(out[i]);
    saved += tokens;
    out[i] = _stubTrace(out[i], tokens);
  }
  if (saved < kWaifuPruneMinimumTokens) return List<String>.from(traces);
  return out;
}

String _stubTrace(String raw, int tokens) {
  final first = raw.split('\n').first.trim();
  final name = first.isEmpty ? 'tool' : first;
  return '$name\n(pruned, was $tokens tokens)';
}

/// Index of the last user line (start of the live turn). 0 if none.
int waifuCompactTailIndex(List<WaifuMessage> msgs) {
  for (var i = msgs.length - 1; i >= 0; i--) {
    if (msgs[i].kind == WaifuMsgKind.user) return i;
  }
  return 0;
}

/// Stub old tool-kind messages in the live transcript.
void waifuPruneOldToolMessages(
  List<WaifuMessage> msgs, {
  required int budget,
  int? protectTokens,
}) {
  final tools = <int>[];
  for (var i = 0; i < msgs.length; i++) {
    if (msgs[i].kind == WaifuMsgKind.tool) tools.add(i);
  }
  if (tools.isEmpty) return;
  final protect = protectTokens ?? waifuPruneProtectTokens(budget);
  var kept = 0;
  var pruneFrom = -1;
  for (var t = tools.length - 1; t >= 0; t--) {
    kept += waifuEstimateTokens(msgs[tools[t]].text);
    if (kept > protect) {
      pruneFrom = t;
      break;
    }
  }
  if (pruneFrom < 0) return;
  var saved = 0;
  for (var t = 0; t <= pruneFrom; t++) {
    final i = tools[t];
    if (msgs[i].text.contains('(pruned)')) continue;
    final tokens = waifuEstimateTokens(msgs[i].text);
    saved += tokens;
    final name = msgs[i].toolName ?? 'tool';
    msgs[i] = WaifuMessage.tool(
      name: name,
      output: '$name\n(pruned, was $tokens tokens)',
      ok: msgs[i].toolOk == true,
      path: msgs[i].toolPath,
      callId: msgs[i].toolCallId,
      args: msgs[i].toolArgs,
    );
  }
  if (saved < kWaifuPruneMinimumTokens) {
    // already stubbed; leave it — next compact is the real fold
  }
}

const kWaifuDuplicateInHistory = 'already in history, unchanged';

bool waifuIsDuplicateToolStub(String output) =>
    output.startsWith(kWaifuDuplicateInHistory);

String? waifuDuplicateReadStub({
  required List<WaifuMessage> transcript,
  required String path,
  Map<String, dynamic>? args,
}) {
  final want = waifuNormalizeVerifyPath(path);
  if (want.isEmpty) return null;
  final wantWindow = waifuReadWindowKey(args);
  for (final m in transcript.reversed) {
    if (m.kind != WaifuMsgKind.tool) continue;
    final name = m.toolName ?? '';
    if (kWaifuReceiptMutationTools.contains(name) && m.toolOk == true) {
      // Only the mutated path is stale. Sibling reads stay in history.
      if (waifuReadVerifiesMutate(want, [m.toolPath ?? ''])) {
        return null;
      }
      continue;
    }
    if (name == kWaifuToolRead &&
        m.toolOk == true &&
        waifuNormalizeVerifyPath(m.toolPath ?? '') == want &&
        !m.text.contains('(pruned)') &&
        waifuReadWindowKey(m.toolArgs) == wantWindow) {
      return kWaifuDuplicateInHistory;
    }
  }
  return null;
}

String waifuGlobStubKey(String pattern, [String? path]) =>
    '${pattern.trim()}\x1f${waifuNormalizeVerifyPath(path ?? '')}';

String? waifuDuplicateGlobStub({
  required List<WaifuMessage> transcript,
  required String pattern,
  String? path,
}) {
  final want = waifuGlobStubKey(pattern, path);
  if (pattern.trim().isEmpty) return null;
  for (final m in transcript.reversed) {
    if (m.kind != WaifuMsgKind.tool) continue;
    final name = m.toolName ?? '';
    if (kWaifuReceiptMutationTools.contains(name) && m.toolOk == true) {
      return null;
    }
    if (name == kWaifuToolGlob &&
        m.toolOk == true &&
        !m.text.contains('(pruned)')) {
      final have = waifuGlobStubKey(
        (m.toolArgs?['pattern'] ?? m.toolArgs?['glob'] ?? '').toString(),
        m.toolPath ?? m.toolArgs?['path']?.toString(),
      );
      if (have == want) return kWaifuDuplicateInHistory;
    }
  }
  return null;
}

const kWaifuCompactSystem =
    'You write recaps for a coding session that is about to drop older '
    'turns. The next request will not have those turns. Produce a detailed '
    'recap: what the user asked, constraints, files created or edited '
    '(paths that actually appeared), decisions and why, errors, tests, '
    'fixes, and remaining work. Do not invent files, paths, or results. '
    'Do not stay in character. Recap only.';

String waifuCompactUserPrompt({
  required String foldedSpeech,
  String previousRecap = '',
  String ledger = '',
}) {
  final buf = StringBuffer();
  if (previousRecap.trim().isNotEmpty) {
    buf
      ..writeln('Previous recap:')
      ..writeln(previousRecap.trim())
      ..writeln()
      ..writeln('Update that recap with the folded turns below.');
  } else {
    buf.writeln('Fold these turns into a recap for continuing the work.');
  }
  if (ledger.trim().isNotEmpty) {
    buf
      ..writeln()
      ..writeln(
        'Machine ledger (facts only — do not invent paths or commands):',
      )
      ..writeln(ledger.trim());
  }
  buf
    ..writeln()
    ..writeln(foldedSpeech);
  return buf.toString();
}

/// Fold when [budgetTokens] is set and fill ≥ 75%. [budgetChars] stays for
/// older tests that pass a tiny character cap. Extractive recap only —
/// no invented filenames. [force] skips the fill check (LLM-compact fallback).
List<WaifuMessage> waifuCompactTranscript(
  List<WaifuMessage> msgs, {
  int budgetChars = kWaifuTranscriptBudgetChars,
  int? budgetTokens,
  int keep = kWaifuCompactKeep,
  bool force = false,
}) {
  if (!force && budgetTokens != null) {
    final used = waifuEstimateTokens(
      msgs.map((m) => '${m.text}\n${m.reasoning}').join('\n'),
    );
    if (used < budgetTokens * kWaifuCompactAt || msgs.length <= keep) {
      return List<WaifuMessage>.from(msgs);
    }
  } else if (!force) {
    final total = msgs.fold<int>(0, (n, m) => n + m.text.length);
    if (total <= budgetChars || msgs.length <= keep) {
      return List<WaifuMessage>.from(msgs);
    }
  }
  if (msgs.length <= keep) return List<WaifuMessage>.from(msgs);
  final dropped = msgs.length - keep;
  final excerpt = msgs.take(dropped).map((m) => m.text).join('\n');
  final clipped = excerpt.length <= kWaifuRecapClipChars
      ? excerpt
      : '${excerpt.substring(0, kWaifuRecapClipChars).trimRight()}\n…';
  final recap = WaifuMessage.recap(
    '$kWaifuCompactPrefix\n'
    '$kWaifuExtractiveRecapPrefix $dropped messages folded. Facts only '
    'from those lines. Do not invent files.\n$clipped',
  );
  return [recap, ...msgs.sublist(dropped)];
}

String waifuTitleFrom(String task) {
  final t = task.trim().replaceAll(RegExp(r'\s+'), ' ');
  if (t.isEmpty) return kWaifuCoderName;
  if (t.length <= 48) return t;
  return '${t.substring(0, 48).trimRight()}…';
}
