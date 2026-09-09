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

const kWaifuTranscriptBudgetChars = 12000;
const kWaifuCompactKeep = 8;
const kWaifuRecapClipChars = 1500;
const kWaifuCompactAt = 0.75;
const kWaifuDefaultContextTokens = 8192;
const kWaifuCompactOutputTokens = 4096;
const kWaifuPruneProtectMaxTokens = 40000;
const kWaifuPruneMinimumTokens = 2000;
const kWaifuCompactPrefix = '[Session compact]';

/// Fallback only — the bar prefers server `usage` when the backend sent it.
int waifuEstimateTokens(String text) {
  if (text.isEmpty) return 0;
  return (text.length / 4).ceil();
}

int waifuEstimateToolsTokens(List<Map<String, dynamic>> tools) {
  if (tools.isEmpty) return 0;
  return waifuEstimateTokens(jsonEncode(tools));
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

/// System + user + advertised tools. [totalTokens] / [promptTokens] from
/// the last API `usage` win over the chars/4 guess.
WaifuBudgetSnapshot waifuMeasureRequest({
  required String systemPrompt,
  required String prompt,
  required int budget,
  List<Map<String, dynamic>> tools = const [],
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

String waifuRenderToolTrace(List<String> traces) {
  if (traces.isEmpty) return '';
  return traces.join('\n');
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
  final recap = WaifuMessage(
    isUser: false,
    text:
        'Earlier recap: $dropped messages folded. Facts only from those '
        'lines. Do not invent files.\n$clipped',
  );
  return [recap, ...msgs.sublist(dropped)];
}

String waifuTitleFrom(String task) {
  final t = task.trim().replaceAll(RegExp(r'\s+'), ' ');
  if (t.isEmpty) return kWaifuCoderName;
  if (t.length <= 48) return t;
  return '${t.substring(0, 48).trimRight()}…';
}
