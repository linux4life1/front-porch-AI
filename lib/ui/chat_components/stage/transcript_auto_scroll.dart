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

import 'package:flutter/material.dart';

import 'package:front_porch_ai/models/models.dart';

void applyTranscriptAutoScroll(
  ScrollController controller, {
  required bool generating,
}) {
  // Option B: never pin to newest on send or stream. Do not rewrite
  // offset on every layout — that was the hold that bucked idle scrub.
}

enum TranscriptGrowth { open, prepend, other }

String transcriptTipKey(List<ChatMessage> messages) {
  if (messages.isEmpty) return '';
  final tip = messages.last;
  return '${tip.sender}\u0000${tip.text}';
}

TranscriptGrowth classifyTranscriptGrowth({
  String? sessionId,
  String? prevSession,
  required int prevLen,
  required String prevTip,
  required int nextLen,
  required String nextTip,
}) {
  if (nextLen <= 0) return TranscriptGrowth.other;
  if (prevLen <= 0) return TranscriptGrowth.open;
  if (sessionId != null && sessionId != prevSession) {
    return TranscriptGrowth.open;
  }
  if (nextLen > prevLen && nextTip.isNotEmpty && nextTip == prevTip) {
    return TranscriptGrowth.prepend;
  }
  return TranscriptGrowth.other;
}

/// Forward list: latest is maxScrollExtent. One-shot for open / restore.
bool pinTranscriptToLatest(ScrollController controller) {
  if (!controller.hasClients) return false;
  final max = controller.position.maxScrollExtent;
  if ((controller.offset - max).abs() > 0.5) controller.jumpTo(max);
  return true;
}

/// One-shot when older rows are prepended. Not for tokens, not per layout.
/// Call after maxScrollExtent has settled — the first frame after a
/// prepend can report a stale (too large) max.
void holdTranscriptAfterPrepend(
  ScrollController controller,
  double previousMax,
) {
  if (!controller.hasClients) return;
  final grew = controller.position.maxScrollExtent - previousMax;
  if (grew <= 0) return;
  final next = (controller.offset + grew).clamp(
    controller.position.minScrollExtent,
    controller.position.maxScrollExtent,
  );
  if ((next - controller.offset).abs() > 0.5) controller.jumpTo(next);
}

/// Keep the open-window's first row as the CustomScrollView center so
/// older pages grow above the viewport. No offset rewrite.
int nextTranscriptCenterIndex({
  required int prevCenter,
  required TranscriptGrowth kind,
  required int prevLen,
  required int nextLen,
}) {
  if (kind == TranscriptGrowth.open) return 0;
  if (kind == TranscriptGrowth.prepend && nextLen > prevLen) {
    return prevCenter + (nextLen - prevLen);
  }
  return prevCenter;
}

/// Apply the one-shot open / prepend move after this frame's layout.
void applyTranscriptGrowth(
  ScrollController? controller, {
  required TranscriptGrowth? pending,
  required double previousMax,
}) {
  if (controller == null || !controller.hasClients || pending == null) return;
  switch (pending) {
    case TranscriptGrowth.open:
      pinTranscriptToLatest(controller);
    case TranscriptGrowth.prepend:
      holdTranscriptAfterPrepend(controller, previousMax);
    case TranscriptGrowth.other:
      break;
  }
}
