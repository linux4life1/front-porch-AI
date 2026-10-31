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

import 'package:flutter/foundation.dart';

import 'package:front_porch_ai/services/chat/session_state.dart';

import 'transfer_host.dart';

/// Kick existing MemoryService window backfill after import (fire-and-forget).
///
/// Chunks one window at a time with an `isGenerating` re-check so a Send
/// never sits behind hundreds of import embeds on the ONNX FIFO queue.
/// Works for 1:1 and group via [TransferHost.ragCharacterId] (group bucket).
///
/// Contract: if the whole backfill is paused for generation, remaining
/// windows stay missing until this loop resumes or the live post-gen path
/// fills gaps (idempotent). Half-embedded is safe — never blocks Send.
Future<void> backfillRagAfterImport(
  ChatSessionState session,
  TransferHost host,
) async {
  final sid = session.currentSessionId;
  final mem = host.memory();
  if (sid == null || mem == null) return;
  if (!mem.isOperational) return;
  final charId = host.ragCharacterId();
  if (charId.isEmpty) return;

  await host.awaitHistoryHydrated();
  if (session.currentSessionId != sid) return;
  final formatted = host.formatForRagEmbedding(session.messages);
  final offset = host.historyBasePosition();
  // Bound wall-clock work: each successful window resets stall; null-embed
  // / abort only retry a limited number of times so we never busy-spin the
  // event loop (Muse review of 03d46d9a).
  var stallStreak = 0;
  const maxStall = 40;
  for (var i = 0; i < 50000; i++) {
    // User left this chat / imported another — stop writing orphans.
    if (session.currentSessionId != sid) {
      debugPrint(
        '[fpchat] RAG backfill stopped — session changed away from $sid',
      );
      return;
    }
    if (host.isGenerating()) {
      stallStreak++;
      if (stallStreak > maxStall) {
        debugPrint(
          '[fpchat] RAG backfill paused for generation too long — '
          'leaving remaining windows for live catch-up',
        );
        return;
      }
      await Future<void>.delayed(const Duration(milliseconds: 400));
      continue;
    }
    try {
      final pass = await mem.embedMessageWindow(
        sessionId: sid,
        characterId: charId,
        formattedMessages: formatted,
        totalMessageCount: formatted.length,
        positionOffset: offset,
        maxWindows: 1,
        shouldContinue: () =>
            !host.isGenerating() && session.currentSessionId == sid,
      );
      if (pass.aborted) {
        stallStreak++;
        if (stallStreak > maxStall) return;
        await Future<void>.delayed(const Duration(milliseconds: 400));
        continue;
      }
      if (!pass.hasMore) return;
      if (pass.stored == 0) {
        // Null embed / skip — backoff, do not Duration.zero spin.
        stallStreak++;
        if (stallStreak > maxStall) {
          debugPrint(
            '[fpchat] RAG backfill giving up after repeated empty passes',
          );
          return;
        }
        await Future<void>.delayed(const Duration(milliseconds: 200));
        continue;
      }
      stallStreak = 0;
    } catch (e) {
      debugPrint('[fpchat] RAG backfill after import failed: $e');
      return;
    }
    // ~one frame — enough yield without starving the event loop.
    await Future<void>.delayed(const Duration(milliseconds: 16));
  }
}
