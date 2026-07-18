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
import '../porch_accordion.dart';
import 'afk_panel.dart';
import 'chaos_panel.dart';
import 'lorebook_chat_book.dart';
import 'lorebook_panel.dart';
import 'objective_panel.dart';

/// 🎲 Story Tools accordion — author's note, objectives (1:1 full chats
/// only), chaos mode, dynamic responses (AFK, 1:1 only), and lorebook
/// triggers.
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // (Author's Note moved OUT of this group — it leads the sidebar as
          // its own card in SidebarBody, per user feedback that it was
          // buried here.)
          if (!isGroup && !isLite) ...[
            ObjectivePanel(chatService: chatService),
            const SizedBox(height: 12),
          ],
          Consumer<ChatService>(
            builder: (context, chat, _) =>
                ChaosPanel(chat: chat, onSpinRequested: onSpinRequested),
          ),
          const SizedBox(height: 12),
          // Dynamic Responses (AFK) sits directly under Chaos Mode. 1:1 only —
          // the autonomous idle cue narrates the solo character's day.
          if (!isGroup) ...[
            AfkPanel(chat: chatService),
            const SizedBox(height: 12),
          ],
          if (isGroup)
            GroupLorebookSection(chatService: chatService, draft: draft)
          else if (character != null)
            LorebookSection(
              character: character!,
              activeLore: chatService.currentlyActiveLoreEntries(),
              chatService: chatService,
              draft: draft,
            ),
          const SizedBox(height: 12),
          ChatLorebookSection(chatService: chatService),
        ],
      ),
    );
  }
}
