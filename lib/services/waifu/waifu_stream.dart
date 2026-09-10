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

import 'package:front_porch_ai/services/llm_service.dart';
import 'package:front_porch_ai/services/waifu/waifu_session.dart';
import 'package:front_porch_ai/services/waifu/waifu_tool_leak.dart';
import 'package:front_porch_ai/utils/utils.dart';

export 'waifu_tool_leak.dart';

WaifuMessage waifuBeginStream(WaifuMessage last, int nowMs) {
  return WaifuMessage.assistant(
    '',
    chips: last.chips,
    reasoning: last.reasoning,
    thinkingStartMs: last.thinkingStartMs,
    thinkingMs: last.thinkingMs,
  );
}

WaifuMessage waifuApplyChunk({
  required WaifuMessage last,
  required String priorReasoning,
  required String streamBuf,
  bool paintBody = true,
  int? nowMs,
}) {
  final split = splitMessageForEdit(streamBuf);
  final think = waifuStripToolLeak(split.thinking);
  final prior = waifuStripToolLeak(
    priorReasoning.isEmpty ? last.reasoning : priorReasoning,
  );
  final reasoning = think.isEmpty ? prior : think;
  final visible = waifuStripToolLeak(split.body);
  final dump = waifuLooksThinkDump(visible);
  final parked = dump
      ? (reasoning.trim().isEmpty ? visible : reasoning)
      : reasoning;
  return last.copyWith(
    text: !paintBody || visible.isEmpty || dump ? last.text : visible,
    reasoning: parked,
    thinkingStartMs: parked.trim().isEmpty || last.thinkingStartMs != null
        ? last.thinkingStartMs
        : nowMs,
  );
}

WaifuMessage? waifuMergeReasoning(WaifuMessage last, LlmToolResponse resp) {
  final split = splitMessageForEdit(resp.text);
  var thinking = waifuStripToolLeak(resp.reasoning).trim();
  if (thinking.isEmpty) thinking = waifuStripToolLeak(split.thinking);
  if (thinking.isEmpty) return null;
  if (last.reasoning == thinking) return null;
  return last.copyWith(reasoning: thinking);
}

String waifuVisibleText(String raw) =>
    waifuStripToolLeak(splitMessageForEdit(raw).body);

/// Nano-GPT / GLM often stream planning as `content` with no think tags.
/// That is not the porch line.
bool waifuLooksThinkDump(String text) {
  final t = text.trim();
  if (t.isEmpty) return false;
  final lower = t.toLowerCase();
  if (RegExp(r'^the user\b').hasMatch(lower)) return true;
  if (lower.contains('the user wants') || lower.contains('the user asked')) {
    return true;
  }
  if (t.length < 160) return false;
  return t.length > 280 &&
      (lower.contains('let me look') ||
          lower.contains('let me check') ||
          lower.contains('the current implementation') ||
          lower.contains('this is a significant'));
}

/// Porch line when wrap-up was a think dump or empty. Not a harness essay.
const kWaifuStuckWrap = "That's as far as I got.";

/// Wrap-up speech. Think dumps and leaked protocol are not spoken.
String waifuSpokenLine(String raw, {String reasoning = ''}) {
  final body = waifuVisibleText(raw).trim();
  if (body.isEmpty || waifuLooksThinkDump(body)) return '';
  final r = reasoning.trim();
  if (r.isNotEmpty && (body == r || body.startsWith(r) || r.startsWith(body))) {
    if (body.length > 80) return '';
  }
  return body;
}

String waifuClipChipError(String raw) {
  final t = raw.trim().replaceAll(RegExp(r'\s+'), ' ');
  if (t.length <= 160) return t;
  return '${t.substring(0, 160).trimRight()}…';
}

WaifuMessage waifuEndStream(WaifuMessage last, int nowMs) {
  if (last.reasoning.trim().isEmpty) {
    return last.copyWith(thinkingMs: 0);
  }
  final start = last.thinkingStartMs;
  return last.copyWith(
    thinkingMs: start == null ? last.thinkingMs : nowMs - start,
  );
}
