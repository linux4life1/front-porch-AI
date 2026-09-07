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

import 'package:front_porch_ai/services/desk/desk_brand.dart';
import 'package:front_porch_ai/services/desk/desk_session.dart';

const kDeskTranscriptBudgetChars = 12000;
const kDeskCompactKeep = 8;
const kDeskRecapClipChars = 1500;
const kDeskCompactAt = 0.75;
const kDeskDefaultContextTokens = 8192;

/// Same chars/4 estimate the Context Viewer uses.
int deskEstimateTokens(String text) {
  if (text.isEmpty) return 0;
  return (text.length / 4).ceil();
}

class DeskBudgetSnapshot {
  const DeskBudgetSnapshot({required this.used, required this.budget});

  final int used;
  final int budget;
  double get fill => budget <= 0 ? 0 : used / budget;
  bool get shouldCompact => fill >= kDeskCompactAt;
}

DeskBudgetSnapshot deskMeasurePrompt({
  required String systemPrompt,
  required String prompt,
  required int budget,
}) {
  final cap = budget < 1 ? kDeskDefaultContextTokens : budget;
  return DeskBudgetSnapshot(
    used: deskEstimateTokens(systemPrompt) + deskEstimateTokens(prompt),
    budget: cap,
  );
}

/// Fold when [budgetTokens] is set and fill ≥ 75%. [budgetChars] stays for
/// older tests that pass a tiny character cap. Extractive recap only —
/// no invented filenames.
List<DeskMessage> deskCompactTranscript(
  List<DeskMessage> msgs, {
  int budgetChars = kDeskTranscriptBudgetChars,
  int? budgetTokens,
  int keep = kDeskCompactKeep,
}) {
  if (budgetTokens != null) {
    final used = deskEstimateTokens(
      msgs.map((m) => '${m.text}\n${m.reasoning}').join('\n'),
    );
    if (used < budgetTokens * kDeskCompactAt || msgs.length <= keep) {
      return List<DeskMessage>.from(msgs);
    }
  } else {
    final total = msgs.fold<int>(0, (n, m) => n + m.text.length);
    if (total <= budgetChars || msgs.length <= keep) {
      return List<DeskMessage>.from(msgs);
    }
  }
  final dropped = msgs.length - keep;
  final excerpt = msgs.take(dropped).map((m) => m.text).join('\n');
  final clipped = excerpt.length <= kDeskRecapClipChars
      ? excerpt
      : '${excerpt.substring(0, kDeskRecapClipChars).trimRight()}\n…';
  final recap = DeskMessage(
    isUser: false,
    text:
        'Earlier recap: $dropped messages folded. Facts only from those '
        'lines. Do not invent files.\n$clipped',
  );
  return [recap, ...msgs.sublist(dropped)];
}

String deskTitleFrom(String task) {
  final t = task.trim().replaceAll(RegExp(r'\s+'), ' ');
  if (t.isEmpty) return kWaifuCoderName;
  if (t.length <= 48) return t;
  return '${t.substring(0, 48).trimRight()}…';
}
