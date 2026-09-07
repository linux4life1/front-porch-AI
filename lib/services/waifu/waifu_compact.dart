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

import 'package:front_porch_ai/services/waifu/waifu_brand.dart';
import 'package:front_porch_ai/services/waifu/waifu_session.dart';

const kWaifuTranscriptBudgetChars = 12000;
const kWaifuCompactKeep = 8;
const kWaifuRecapClipChars = 1500;
const kWaifuCompactAt = 0.75;
const kWaifuDefaultContextTokens = 8192;

/// Same chars/4 estimate the Context Viewer uses.
int waifuEstimateTokens(String text) {
  if (text.isEmpty) return 0;
  return (text.length / 4).ceil();
}

class WaifuBudgetSnapshot {
  const WaifuBudgetSnapshot({required this.used, required this.budget});

  final int used;
  final int budget;
  double get fill => budget <= 0 ? 0 : used / budget;
  bool get shouldCompact => fill >= kWaifuCompactAt;
}

WaifuBudgetSnapshot waifuMeasurePrompt({
  required String systemPrompt,
  required String prompt,
  required int budget,
}) {
  final cap = budget < 1 ? kWaifuDefaultContextTokens : budget;
  return WaifuBudgetSnapshot(
    used: waifuEstimateTokens(systemPrompt) + waifuEstimateTokens(prompt),
    budget: cap,
  );
}

/// How many tokens this turn may write. Not the chat Max Output Tokens
/// slider (2048 default) — that cuts tool calls mid-file. The window
/// itself is the cap.
int waifuOutputTokenBudget({required int budget, required int used}) {
  final cap = budget < 1 ? kWaifuDefaultContextTokens : budget;
  final left = cap - used;
  return left < 1 ? 1 : left;
}

/// Fold when [budgetTokens] is set and fill ≥ 75%. [budgetChars] stays for
/// older tests that pass a tiny character cap. Extractive recap only —
/// no invented filenames.
List<WaifuMessage> waifuCompactTranscript(
  List<WaifuMessage> msgs, {
  int budgetChars = kWaifuTranscriptBudgetChars,
  int? budgetTokens,
  int keep = kWaifuCompactKeep,
}) {
  if (budgetTokens != null) {
    final used = waifuEstimateTokens(
      msgs.map((m) => '${m.text}\n${m.reasoning}').join('\n'),
    );
    if (used < budgetTokens * kWaifuCompactAt || msgs.length <= keep) {
      return List<WaifuMessage>.from(msgs);
    }
  } else {
    final total = msgs.fold<int>(0, (n, m) => n + m.text.length);
    if (total <= budgetChars || msgs.length <= keep) {
      return List<WaifuMessage>.from(msgs);
    }
  }
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
