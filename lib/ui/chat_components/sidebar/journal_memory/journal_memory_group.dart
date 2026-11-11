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

import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';
import '../porch_accordion.dart';
import '../sidebar_reorder.dart';
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
/// Branch gating: Memory (RAG), the Journal and Growth show everywhere except
/// for lite scene guests (guests never journal or recall; their rings grow in
/// the background and surface if promoted). In a group every leaf speaks for
/// the focused member.
class JournalMemoryGroup extends StatefulWidget {
  final ChatService chatService;
  final bool isGroup;
  final bool isLite;

  /// The focused participant whose diary + growth the panels show
  /// (ChatParticipant.id — the same stable id cards and rings are keyed by).
  final String diaryOwnerId;
  final String diaryOwnerName;

  /// The focused participant's card, whose memory the Memory leaf shows.
  final CharacterCard? diaryOwnerCard;

  /// Receipts tap-to-jump (journal dialog + growth ring receipts).
  final ValueChanged<int> onJumpToMessage;

  final bool initiallyExpanded;
  final ValueChanged<bool>? onExpansionChanged;

  /// Parent-owned key on [PorchAccordion] so OPEN_SECTION=journal can
  /// expand and ensureVisible the TITLE, not the expanded body.
  final GlobalKey<PorchAccordionState>? accordionKey;

  /// The reorder grip when this accordion sits in the reorderable body.
  final Widget? dragHandle;

  const JournalMemoryGroup({
    super.key,
    required this.chatService,
    required this.isGroup,
    required this.isLite,
    required this.diaryOwnerId,
    required this.diaryOwnerName,
    this.diaryOwnerCard,
    required this.onJumpToMessage,
    required this.initiallyExpanded,
    this.onExpansionChanged,
    this.accordionKey,
    this.dragHandle,
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
    final showMemory = !widget.isLite;
    final ragOn =
        storage.memorySettings.ragEnabled &&
        (!widget.isGroup || widget.chatService.groupRagEnabled);
    final subtitle =
        'Journal ${storage.memorySettings.journalEnabled ? 'on' : 'off'}'
        '${showMemory ? ' · RAG ${ragOn ? 'on' : 'off'}' : ''}';

    final ui = storage.uiSettings;
    // The leaf ids this accordion can show right now; the stored order
    // filters to them and appends any it does not know per the default.
    final visible = <String>[
      'summary',
      if (!widget.isLite) 'journal',
      if (showMemory) 'memory',
      if (!widget.isLite) 'growth',
    ];
    final ordered = ui.sidebarLeafOrderFor('journal_memory', visible);
    final pump = ReorderScrollPump.maybeOf(context);

    return PorchAccordion(
      key: _accordionKey,
      id: 'journal_memory',
      emoji: '📖',
      title: 'Journal & Memory',
      subtitle: subtitle,
      accent: AppColors.journalAccentOf(context),
      initiallyExpanded: widget.initiallyExpanded,
      onExpansionChanged: widget.onExpansionChanged,
      dragHandle: widget.dragHandle,
      child: ReorderableListView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        buildDefaultDragHandles: false,
        // The lifted leaf must not eat the wheel hit test (see sidebar_body
        // for why); signals fall through to the armed pump listeners below.
        proxyDecorator: (child, index, animation) => IgnorePointer(
          child: Material(
            elevation: 2,
            shadowColor: Colors.transparent,
            child: child,
          ),
        ),
        itemCount: ordered.length,
        // The body pumps its wheel scroll for leaf drags too.
        onReorderStart: (_) => pump?.reportDrag(true),
        onReorderEnd: (_) => pump?.reportDrag(false),
        onReorderItem: (from, to) => ui.setSidebarLeafOrder(
          'journal_memory',
          _reorderIds(ordered, from, to),
        ),
        itemBuilder: (context, i) => WheelPump(
          // A leaf in hand pumps the body's scroll (see [WheelPump]); the
          // item key lives here, where the list can see it.
          key: ValueKey('sidebar-leaf-${ordered[i]}'),
          pump: pump,
          child: Padding(
            // The old Column's 12px gap between leaves, not after the last.
            padding: EdgeInsets.only(bottom: i == ordered.length - 1 ? 0 : 12),
            child: _leaf(context, ordered[i], i),
          ),
        ),
      ),
    );
  }

  /// The leaf widget for [id], with its reorder grip at [index].
  Widget _leaf(BuildContext context, String id, int index) {
    final grip = SidebarReorderHandle(index: index);
    switch (id) {
      case 'summary':
        return SummarySection(
          chatService: widget.chatService,
          dragHandle: grip,
        );
      case 'journal':
        return JournalPanel(
          chatService: widget.chatService,
          characterId: widget.diaryOwnerId,
          characterName: widget.diaryOwnerName,
          onJumpToMessage: widget.onJumpToMessage,
          dragHandle: grip,
        );
      case 'memory':
        return MemoryPanel(
          chatService: widget.chatService,
          member: widget.diaryOwnerCard,
          onJumpToMessage: widget.onJumpToMessage,
          dragHandle: grip,
        );
      case 'growth':
        return GrowthPanel(
          chatService: widget.chatService,
          characterId: widget.diaryOwnerId,
          characterName: widget.diaryOwnerName,
          onJumpToMessage: widget.onJumpToMessage,
          dragHandle: grip,
        );
    }
    return const SizedBox.shrink();
  }

  /// The ids reordered by a drag: onReorderItem delivers newIndex already
  /// adjusted for the removal at oldIndex (no manual decrement).
  List<String> _reorderIds(List<String> ids, int oldIndex, int newIndex) {
    if (oldIndex == newIndex) return ids;
    final out = List.of(ids);
    final item = out.removeAt(oldIndex);
    out.insert(newIndex, item);
    return out;
  }
}
