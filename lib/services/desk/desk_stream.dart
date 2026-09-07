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

import 'package:front_porch_ai/services/desk/desk_session.dart';
import 'package:front_porch_ai/services/llm_service.dart';
import 'package:front_porch_ai/utils/utils.dart';

DeskMessage deskBeginStream(DeskMessage last, int nowMs) {
  return DeskMessage(
    isUser: false,
    text: last.text,
    chips: last.chips,
    reasoning: last.reasoning,
    thinkingStartMs: nowMs,
    thinkingMs: 0,
  );
}

DeskMessage deskApplyChunk({
  required DeskMessage last,
  required String priorReasoning,
  required String streamBuf,
}) {
  final split = splitMessageForEdit(streamBuf);
  final think = split.thinking;
  final reasoning = think.isEmpty
      ? (priorReasoning.isEmpty ? last.reasoning : priorReasoning)
      : think;
  return DeskMessage(
    isUser: false,
    text: split.body.isEmpty ? last.text : split.body,
    chips: last.chips,
    reasoning: reasoning,
    thinkingStartMs: last.thinkingStartMs,
  );
}

DeskMessage? deskMergeReasoning(DeskMessage last, LlmToolResponse resp) {
  final split = splitMessageForEdit(resp.text);
  var thinking = resp.reasoning.trim();
  if (thinking.isEmpty) thinking = split.thinking;
  if (thinking.isEmpty) return null;
  if (last.reasoning == thinking) return null;
  return DeskMessage(
    isUser: false,
    text: last.text,
    chips: last.chips,
    reasoning: thinking,
    thinkingStartMs: last.thinkingStartMs,
    thinkingMs: last.thinkingMs,
  );
}

String deskVisibleText(String raw) => splitMessageForEdit(raw).body.trim();

String deskClipChipError(String raw) {
  final t = raw.trim().replaceAll(RegExp(r'\s+'), ' ');
  if (t.length <= 48) return t;
  return '${t.substring(0, 48).trimRight()}…';
}

DeskMessage deskEndStream(DeskMessage last, int nowMs) {
  final start = last.thinkingStartMs;
  return DeskMessage(
    isUser: false,
    text: last.text,
    chips: last.chips,
    reasoning: last.reasoning,
    thinkingStartMs: start,
    thinkingMs: start == null ? last.thinkingMs : nowMs - start,
  );
}
