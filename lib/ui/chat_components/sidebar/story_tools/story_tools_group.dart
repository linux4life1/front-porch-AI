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
import 'package:flutter/material.dart';

import 'package:provider/provider.dart';

import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';

import '../../widgets/chat_turn_builder.dart';
import '../porch_accordion.dart';
import '../sidebar_reorder.dart';
import 'afk_panel.dart';
import 'chaos_panel.dart';
import 'chat_places_panel.dart';
import 'lorebook_chat_book.dart';
import 'lorebook_panel.dart';

/// 🎲 Story Tools accordion — chaos mode, dynamic responses (AFK, 1:1 only),
/// places, and lorebook triggers.
///
/// Objectives live in their own SidebarBody accordion (collapsed by default)
/// so they don't bury chaos / places / lore.
///
/// [character] is the active 1:1 card the LorebookSection needs (unused in
/// group mode).
class StoryToolsGroup extends StatelessWidget {
  final ChatService chatService;
  final bool isGroup;
  final bool isLite;
  final bool initiallyExpanded;
  final ValueChanged<bool>? onExpansionChanged;
  final VoidCallback onSpinRequested;
  final CharacterCard? character;

  /// The composer draft (chat_page's input controller) — powers the
  /// lorebook "would trigger next" preview.
  final ValueListenable<TextEditingValue>? draft;

  /// The reorder grip when this accordion sits in the reorderable body.
  final Widget? dragHandle;

  const StoryToolsGroup({
    super.key,
    required this.chatService,
    required this.isGroup,
    required this.isLite,
    required this.initiallyExpanded,
    this.onExpansionChanged,
    required this.onSpinRequested,
    this.character,
    this.draft,
    this.dragHandle,
  });

  @override
  Widget build(BuildContext context) {
    return PorchAccordion(
      id: 'story_tools',
      emoji: '🎲',
      title: 'Story Tools',
      accent: AppColors.porchHoneyOf(context),
      initiallyExpanded: initiallyExpanded,
      onExpansionChanged: onExpansionChanged,
      dragHandle: dragHandle,
      child: ChatTurnBuilder(
        builder: (context, chat) {
          final ui = Provider.of<StorageService>(context).uiSettings;
          final showLorebook = isGroup || character != null;
          // The leaf ids this accordion can show right now; the stored order
          // filters to them and appends any it does not know per the default.
          final visible = <String>[
            'chaos',
            if (!isGroup) 'afk',
            'places',
            if (showLorebook) 'lorebook',
            'chat_lorebook',
          ];
          final ordered = ui.sidebarLeafOrderFor('story_tools', visible);
          final pump = ReorderScrollPump.maybeOf(context);
          return ReorderableListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            buildDefaultDragHandles: false,
            // The lifted leaf must not eat the wheel hit test (see
            // sidebar_body for why); signals fall through to the armed pump
            // listeners below.
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
              'story_tools',
              _reorderIds(ordered, from, to),
            ),
            itemBuilder: (context, i) => WheelPump(
              // A leaf in hand pumps the body's scroll (see [WheelPump]);
              // the item key lives here, where the list can see it.
              key: ValueKey('sidebar-leaf-${ordered[i]}'),
              pump: pump,
              child: Padding(
                // The old Column's 12px gap between leaves, not after the last.
                padding: EdgeInsets.only(
                  bottom: i == ordered.length - 1 ? 0 : 12,
                ),
                child: _leaf(context, chat, ordered[i], i),
              ),
            ),
          );
        },
      ),
    );
  }

  /// The leaf widget for [id], with its reorder grip at [index].
  Widget _leaf(BuildContext context, ChatService chat, String id, int index) {
    final grip = SidebarReorderHandle(index: index);
    switch (id) {
      case 'chaos':
        return ChaosPanel(
          chat: chat,
          onSpinRequested: onSpinRequested,
          dragHandle: grip,
        );
      case 'afk':
        return AfkPanel(chat: chatService, dragHandle: grip);
      case 'places':
        return ChatPlacesPanel(chatService: chatService, dragHandle: grip);
      case 'lorebook':
        return isGroup
            ? GroupLorebookSection(
                chatService: chatService,
                draft: draft,
                dragHandle: grip,
              )
            : LorebookSection(
                character: character!,
                activeLore: chatService.currentlyActiveLoreEntries(),
                chatService: chatService,
                draft: draft,
                dragHandle: grip,
              );
      case 'chat_lorebook':
        return ChatLorebookSection(chatService: chatService, dragHandle: grip);
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
