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

String transcriptTipKey(List<ChatMessage> messages) =>
    messages.isEmpty ? '' : _rowKey(messages.last);

/// The oldest row's identity. A prepend puts a new message object first; an
/// append never does. Identity, not text: an older page can start with the
/// same words as the old first row.
String transcriptHeadKey(List<ChatMessage> messages) =>
    messages.isEmpty ? '' : '${identityHashCode(messages.first)}';

String _rowKey(ChatMessage m) => '${m.sender}\u0000${m.text}';

/// Same tip on a longer list reads as older rows above, unless the head
/// is known and unchanged: then the rows were added below, and the tip
/// matches only because the new last line repeats the old one.
bool isTranscriptPrepend({
  required int prevLen,
  required String prevTip,
  required int nextLen,
  required String nextTip,
  String? prevHead,
  String? nextHead,
}) =>
    nextLen > prevLen &&
    nextTip.isNotEmpty &&
    nextTip == prevTip &&
    (prevHead == null || nextHead == null || nextHead != prevHead);

TranscriptGrowth classifyTranscriptGrowth({
  String? sessionId,
  String? prevSession,
  required int prevLen,
  required String prevTip,
  required int nextLen,
  required String nextTip,
  String? prevHead,
  String? nextHead,
}) {
  if (nextLen <= 0) return TranscriptGrowth.other;
  if (prevLen <= 0) return TranscriptGrowth.open;
  if (sessionId != null && sessionId != prevSession) {
    return TranscriptGrowth.open;
  }
  if (isTranscriptPrepend(
    prevLen: prevLen,
    prevTip: prevTip,
    nextLen: nextLen,
    nextTip: nextTip,
    prevHead: prevHead,
    nextHead: nextHead,
  )) {
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

/// Stick-if-at-bottom while a reply is streaming on a forward list.
/// [applyTranscriptAutoScroll] stays a no-op — Rawhide tests call it.
bool followTranscriptWhileStreaming(
  ScrollController? controller, {
  required bool followEnabled,
  required bool generating,
  required double previousMax,
  double slop = 64,
}) {
  if (controller == null || !controller.hasClients) return false;
  if (!followEnabled || !generating) return false;
  if (controller.offset < previousMax - slop) return false;
  return pinTranscriptToLatest(controller);
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
