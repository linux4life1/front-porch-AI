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

import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/chat/group_memory.dart';
import 'package:front_porch_ai/services/chat/doors/turn/turn_deps.dart';
import 'package:front_porch_ai/services/memory/memory.dart';
import 'package:front_porch_ai/services/memory_service.dart';

/// Files the chat's message windows for RAG: the one writer behind the live
/// post-reply embed and the post-import backfill, so both follow one rule.
///
/// 1:1 (and a Scene Guest's own exchange): one id, the chat's. Group: each
/// member present gets their own copy of the stretch they were there for,
/// under their memory key and this chat. Nothing is ever filed under the old
/// shared `group_<id>` id.
class WindowFiler {
  WindowFiler(this._d);

  final TurnDeps _d;

  /// Files the missing windows of [messages] (already formatted as [lines],
  /// one per message). [characterIdOverride] names a single owner (a guest).
  /// Results are summed across owners.
  Future<EmbedPassResult> file({
    required MemoryService memory,
    required String sessionId,
    required List<ChatMessage> messages,
    required List<String> lines,
    required int positionOffset,
    String? characterIdOverride,
    int? maxWindows,
    bool Function()? shouldContinue,
  }) async {
    final group = _d.session.activeGroup;
    if (group == null || characterIdOverride != null) {
      return memory.embedMessageWindow(
        sessionId: sessionId,
        characterId: characterIdOverride ?? _d.session.ragCharacterId(),
        formattedMessages: lines,
        totalMessageCount: lines.length,
        positionOffset: positionOffset,
        maxWindows: maxWindows,
        shouldContinue: shouldContinue,
      );
    }
    final keys = _d.doors.cast().memory.rosterKeys();
    final masks = presentLineMasks(messages, keys);
    final legacy = legacyGroupMemoryBuckets(group.id);
    var stored = 0;
    var hasMore = false;
    var aborted = false;
    for (final key in keys) {
      final pass = await memory.embedMessageWindow(
        sessionId: sessionId,
        characterId: key,
        formattedMessages: lines,
        totalMessageCount: lines.length,
        positionOffset: positionOffset,
        maxWindows: maxWindows,
        shouldContinue: shouldContinue,
        lineMask: masks[key],
        skipRangesStoredUnder: legacy,
      );
      stored += pass.stored;
      hasMore = hasMore || pass.hasMore;
      if (pass.aborted) {
        aborted = true;
        break;
      }
    }
    return (stored: stored, hasMore: hasMore, aborted: aborted);
  }
}
