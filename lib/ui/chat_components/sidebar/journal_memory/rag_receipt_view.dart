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

import 'package:front_porch_ai/services/chat/chat.dart'
    show
        kRagReceiptError,
        kRagReceiptNotOperational,
        kRagReceiptOk,
        kRagReceiptSkippedNoCues;
import 'package:front_porch_ai/ui/theme/theme.dart';
import 'package:front_porch_ai/ui/chat_components/chat_components.dart';

/// "What memory just did" — renders the last reply's RAG receipt
/// (`rag_receipt` message metadata, wire shape in rag_injection.dart) inside
/// the sidebar Memory panel. This is the anti-black-box surface: every
/// decision the retrieval made (found / deduped against the journal /
/// trimmed for budget / injected, each line with its story-day stamp) was
/// previously a debugPrint and nothing else. Tapping a line from THIS chat
/// jumps the transcript to the exact message it quoted (journal-receipts
/// jump machinery); cross-chat lines have nowhere to jump and don't offer.
class RagReceiptView extends StatelessWidget {
  /// The last character reply's receipt, or null when that reply needed no
  /// retrieval (nothing had fallen out of context).
  final Map<String, dynamic>? receipt;

  /// Journal-receipts tap-to-jump (absolute message position). Null hides
  /// the jump affordance (e.g. a host that has no transcript to seek).
  final ValueChanged<int>? onJumpToMessage;

  final Color accent;

  const RagReceiptView({
    super.key,
    required this.receipt,
    required this.onJumpToMessage,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    final r = receipt;
    final injected = (r?['injected'] as List?) ?? const [];
    final trimmed = (r?['budget_trimmed'] as num?)?.toInt() ?? 0;
    final deduped = (r?['journal_deduped'] as num?)?.toInt() ?? 0;
    final status = r?['status'] as String? ?? kRagReceiptOk;

    final String summary;
    if (r == null) {
      summary =
          'Last reply: nothing had scrolled out of view — no lookup '
          'needed.';
    } else if (status == kRagReceiptError) {
      // audit P2.17 — never "no lookup needed" after a failed attempt
      summary =
          'Last reply: tried to search the archive but the memory engine '
          'hit an error — nothing was brought back.';
    } else if (status == kRagReceiptSkippedNoCues) {
      summary =
          'Last reply: older messages had scrolled out of view, but there '
          'was no cue to look them up (quote the line to reach back).';
    } else if (status == kRagReceiptNotOperational) {
      summary =
          'Last reply: older messages had scrolled out of view, but the '
          'memory engine is not ready — install/start Memory to look them up.';
    } else if (injected.isEmpty) {
      summary =
          'Last reply: searched the archive — nothing relevant enough to '
          'bring back.${_countsSuffix(trimmed, deduped)}';
    } else {
      summary =
          'Last reply: ${injected.length} '
          '${injected.length == 1 ? 'memory' : 'memories'} woven in.'
          '${_countsSuffix(trimmed, deduped)}';
    }

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 8),
      padding: SidebarTokens.wellPadding,
      decoration: BoxDecoration(
        color: AppColors.sunkenSurfaceOf(context),
        borderRadius: BorderRadius.circular(SidebarTokens.wellRadius),
        border: Border.all(color: AppColors.borderOf(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            summary,
            style: TextStyle(
              fontSize: 10,
              color: AppColors.textTertiary(context),
            ),
          ),
          for (final line in injected)
            if (line is Map) _lineRow(context, line.cast<String, dynamic>()),
        ],
      ),
    );
  }

  static String _countsSuffix(int trimmed, int deduped) {
    final parts = [
      if (trimmed > 0) '$trimmed trimmed for space',
      if (deduped > 0) '$deduped already covered by the journal',
    ];
    return parts.isEmpty ? '' : ' (${parts.join(', ')})';
  }

  Widget _lineRow(BuildContext context, Map<String, dynamic> line) {
    final pos = (line['pos'] as num?)?.toInt();
    final day = (line['day'] as num?)?.toInt();
    final otherChat = line['other_chat'] == true;
    final preview = line['preview'] as String? ?? '';
    final stamp = otherChat
        ? 'another chat'
        : day != null
        ? 'Day $day'
        : null;
    final canJump = !otherChat && pos != null && onJumpToMessage != null;

    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (stamp != null)
            Padding(
              padding: const EdgeInsets.only(right: 6, top: 1),
              child: Text(
                stamp,
                style: TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.w600,
                  color: accent,
                ),
              ),
            ),
          Expanded(child: ExpandableSidebarText(text: preview, maxLines: 4)),
          // Jump lives on the icon so a tap on the preview can expand
          // instead of seeking the transcript.
          if (canJump)
            InkWell(
              onTap: () => onJumpToMessage!(pos),
              borderRadius: BorderRadius.circular(4),
              child: Padding(
                padding: const EdgeInsets.only(left: 4),
                child: Icon(
                  Icons.north_east,
                  size: 11,
                  color: AppColors.iconSecondary(context),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
