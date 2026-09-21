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

import 'package:front_porch_ai/services/waifu/waifu.dart';
import 'package:front_porch_ai/ui/chat_components/chat_components.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';
import 'package:front_porch_ai/ui/waifu/waifu_coworker_face.dart';
import 'package:front_porch_ai/ui/waifu/waifu_tool_log.dart';

/// Session transcript column. Extracted so [WaifuPage] stays under the cap.
class WaifuTranscript extends StatelessWidget {
  const WaifuTranscript({
    super.key,
    required this.session,
    required this.coworker,
  });

  final WaifuSession session;
  final String coworker;

  @override
  Widget build(BuildContext context) {
    if (session.transcript.isEmpty) {
      return Center(
        child: Text(
          waifuEmptyPrompt(session.pathMode, coworker),
          textAlign: TextAlign.center,
          style: TextStyle(color: AppColors.textSecondary(context)),
        ),
      );
    }
    final visible = [
      for (final m in session.transcript)
        if (m.kind == WaifuMsgKind.user || m.kind == WaifuMsgKind.assistant) m,
    ];
    final chats = [for (final m in visible) m.toChatMessage(coworker)];
    return ChatMessageList(
      messages: chats,
      resolveSpeaker: (msg) => msg.isUser
          ? (null, null)
          : (waifuCoworkerFace(context, session.coworker), null),
      characterFor: (_) => session.coworker,
      themeOverrides: session.themeOverrides,
      // Same as chat: Thought stays folded until the chevron. Passing
      // session.running as isGenerating auto-opened the live block and
      // a tool-chip rebuild wiped the pin, so it could not be closed.
      // Tool rows sit below the bubble so a long Thought does not
      // scroll the live actions off the top of the reverse list.
      belowBubble: (msg, index) {
        if (msg.isUser) return null;
        if (index < 0 || index >= visible.length) return null;
        final chips = visible[index].chips;
        if (chips.isEmpty) return null;
        return WaifuToolLog(chips: chips);
      },
    );
  }
}
