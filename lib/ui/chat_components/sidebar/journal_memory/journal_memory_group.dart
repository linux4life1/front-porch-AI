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
import 'package:provider/provider.dart';

import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';
import '../porch_accordion.dart';
import 'growth_panel.dart';
import 'journal_panel.dart';
import 'memory_panel.dart';
import 'summary_section.dart';

/// 📖 Journal & Memory accordion — groups the "Where we are" recap
/// (SummarySection), the Journal card peek (JournalPanel — the focused
/// participant's diary, per-member in groups), the Memory (RAG) panel, and
/// the Growth Rings timeline (GrowthPanel — also per focused participant)
/// under one collapsible card.
///
/// Branch gating: Memory (RAG) is 1:1 full chats only; the Journal and
/// Growth show everywhere except for lite scene guests (guests never
/// journal; their rings grow in the background and surface if promoted).
class JournalMemoryGroup extends StatefulWidget {
  final ChatService chatService;
  final bool isGroup;
  final bool isLite;

  /// The focused participant whose diary + growth the panels show
  /// (ChatParticipant.id — the same stable id cards and rings are keyed by).
  final String diaryOwnerId;
  final String diaryOwnerName;

  /// Receipts tap-to-jump (journal dialog + growth ring receipts).
  final ValueChanged<int> onJumpToMessage;

  final bool initiallyExpanded;
  final ValueChanged<bool>? onExpansionChanged;

  /// Parent-owned key on [PorchAccordion] so OPEN_SECTION=journal can
  /// expand and ensureVisible the TITLE, not the expanded body.
  final GlobalKey<PorchAccordionState>? accordionKey;

  const JournalMemoryGroup({
    super.key,
    required this.chatService,
    required this.isGroup,
    required this.isLite,
    required this.diaryOwnerId,
    required this.diaryOwnerName,
    required this.onJumpToMessage,
    required this.initiallyExpanded,
    this.onExpansionChanged,
    this.accordionKey,
  });

  @override
  State<JournalMemoryGroup> createState() => JournalMemoryGroupState();
}

class JournalMemoryGroupState extends State<JournalMemoryGroup> {
  final _ownedAccordionKey = GlobalKey<PorchAccordionState>();

  GlobalKey<PorchAccordionState> get _accordionKey =>
      widget.accordionKey ?? _ownedAccordionKey;

  void expand() => _accordionKey.currentState?.expand();

  void collapse() => _accordionKey.currentState?.collapse();

  @override
  Widget build(BuildContext context) {
    final storage = Provider.of<StorageService>(context);
    final showMemory = !widget.isGroup && !widget.isLite;
    final subtitle =
        'Journal ${storage.journalEnabled ? 'on' : 'off'}'
        '${showMemory ? ' · RAG ${storage.ragEnabled ? 'on' : 'off'}' : ''}';

    return PorchAccordion(
      key: _accordionKey,
      id: 'journal_memory',
      emoji: '📖',
      title: 'Journal & Memory',
      subtitle: subtitle,
      accent: AppColors.journalAccentOf(context),
      initiallyExpanded: widget.initiallyExpanded,
      onExpansionChanged: widget.onExpansionChanged,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SummarySection(chatService: widget.chatService),
          if (!widget.isLite) ...[
            const SizedBox(height: 12),
            JournalPanel(
              chatService: widget.chatService,
              characterId: widget.diaryOwnerId,
              characterName: widget.diaryOwnerName,
              onJumpToMessage: widget.onJumpToMessage,
            ),
          ],
          if (showMemory) ...[
            const SizedBox(height: 12),
            MemoryPanel(
              chatService: widget.chatService,
              onJumpToMessage: widget.onJumpToMessage,
            ),
          ],
          if (!widget.isLite) ...[
            const SizedBox(height: 12),
            GrowthPanel(
              chatService: widget.chatService,
              characterId: widget.diaryOwnerId,
              characterName: widget.diaryOwnerName,
              onJumpToMessage: widget.onJumpToMessage,
            ),
          ],
        ],
      ),
    );
  }
}
