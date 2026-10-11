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

import 'package:front_porch_ai/services/waifu/waifu_session.dart';

/// One transcript row per OpenCode tool call. OpenCode re-sends the part as
/// it goes pending → running → completed; a known [callId] in the current
/// turn is updated in place instead of stacking a row per status.
void waifuUpsertToolRow(
  List<WaifuMessage> transcript, {
  required String name,
  required String detail,
  required bool ok,
  required bool pending,
  required String callId,
}) {
  final row = WaifuMessage.tool(
    name: name,
    output: detail,
    ok: pending ? true : ok,
    callId: callId.isEmpty ? null : callId,
  );
  if (callId.isNotEmpty) {
    for (var i = transcript.length - 1; i >= 0; i--) {
      final m = transcript[i];
      if (m.kind == WaifuMsgKind.user) break;
      if (m.kind == WaifuMsgKind.tool && m.toolCallId == callId) {
        transcript[i] = row;
        return;
      }
    }
  }
  transcript.add(row);
}

/// [message] with [chip] replacing the chip for the same call (by id, else
/// the pending chip of the same tool), or appended.
WaifuMessage waifuWithToolChip(WaifuMessage message, WaifuToolChip chip) {
  final chips = [...message.chips];
  var i = -1;
  if (chip.callId.isNotEmpty) {
    i = chips.indexWhere((c) => c.callId == chip.callId);
  }
  if (i < 0) {
    i = chips.indexWhere((c) => c.pending && c.name == chip.name);
  }
  if (i >= 0) {
    chips[i] = chip;
  } else {
    chips.add(chip);
  }
  return message.copyWith(chips: chips);
}
