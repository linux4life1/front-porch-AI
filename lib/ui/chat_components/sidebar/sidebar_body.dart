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

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:front_porch_ai/models/chat_participant.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/dialogs/group_objectives_dialog.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';
import 'package:front_porch_ai/ui/widgets/group_member_card.dart';
import 'character_state/character_state_group.dart';
import 'journal_memory/journal_memory_group.dart';
import 'porch_accordion.dart';
import 'sidebar_tokens.dart';
import 'story_tools/author_note_section.dart';
import 'story_tools/story_tools_group.dart';
import 'tool_calling_pill.dart';

/// The scrolling body of the warm-porch chat sidebar: the lite-NPC banner
/// plus the three accordion groups (🎭 Character State · 📖 Journal & Memory
/// · 🎲 Story Tools). ALL 1:1 / group / lite-NPC branching lives here —
/// replacing the old three-branch ListView in chat_page.
///
/// Composition-only: page-level concerns (chance-time overlay, avatar file
/// resolution) arrive as callbacks; accordion expansion is persisted via
/// StorageService.uiSettings.
class SidebarBody extends StatelessWidget {
  final ChatService chatService;
  final ChatParticipant focused;
  final VoidCallback onSpinRequested;

  /// Receipts tap-to-jump (journal + growth rings): scroll the chat to this
  /// message position (chat_page owns the scroll controller and the seek).
  final ValueChanged<int> onJumpToMessage;

  final File? Function(String path) resolveCharImage;

  /// Composer draft for the lorebook "would trigger next" preview.
  final ValueListenable<TextEditingValue>? draft;

  const SidebarBody({
    super.key,
    required this.chatService,
    required this.focused,
    required this.onSpinRequested,
    required this.onJumpToMessage,
    required this.resolveCharImage,
    this.draft,
  });

  @override
  Widget build(BuildContext context) {
    return Consumer<ChatService>(
      builder: (context, chat, _) {
        // Listening: evolution/journal/one-shot toggles live on storage and
        // must repaint the panels (each old section listened individually).
        final storage = Provider.of<StorageService>(context);
        final ui = storage.uiSettings;
        final character = focused.card;
        final isGroup = chat.isGroupMode;
        final isLite = !isGroup && !focused.realismEnabled;

        return ListView(
          padding: const EdgeInsets.all(12),
          children: [
            // Tool-calling capability of the current model, always visible —
            // users shouldn't have to guess why evals silently run in text
            // mode (and it retests itself on model/backend switches).
            ToolCallingPill(chatService: chat),
            if (isLite) const _LiteNpcBanner(),
            // Author's Note leads the sidebar as its own card (it was the
            // always-first section in the old design; burying it inside
            // Story Tools made it hard to find — user feedback).
            PorchAccordion(
              id: 'author_note',
              emoji: '📝',
              title: "Author's Note",
              subtitle: chat.authorNote.trim().isEmpty
                  ? null
                  : 'active · strength ${chat.authorNoteStrength}',
              accent: AppColors.porchAmberOf(context),
              initiallyExpanded: ui.sidebarGroupExpanded(
                'author_note',
                fallback: true,
              ),
              onExpansionChanged: (v) =>
                  ui.setSidebarGroupExpanded('author_note', v),
              child: AuthorNoteSection(chatService: chat),
            ),
            if (!isLite)
              CharacterStateGroup(
                chat: chat,
                isGroup: isGroup,
                groupMemberCard: isGroup
                    ? _buildFocusedMemberCard(context, chat)
                    : null,
                initiallyExpanded: ui.sidebarGroupExpanded(
                  'character_state',
                  fallback: true,
                ),
                onExpansionChanged: (v) =>
                    ui.setSidebarGroupExpanded('character_state', v),
              ),
            JournalMemoryGroup(
              chatService: chat,
              isGroup: isGroup,
              isLite: isLite,
              // The diary follows the focused participant (per-member in
              // groups; ChatParticipant.id is the cards' stable key).
              diaryOwnerId: focused.id,
              diaryOwnerName: focused.name,
              onJumpToMessage: onJumpToMessage,
              initiallyExpanded: ui.sidebarGroupExpanded(
                'journal_memory',
                fallback: false,
              ),
              onExpansionChanged: (v) =>
                  ui.setSidebarGroupExpanded('journal_memory', v),
            ),
            StoryToolsGroup(
              draft: draft,
              chatService: chat,
              isGroup: isGroup,
              isLite: isLite,
              character: character,
              onSpinRequested: onSpinRequested,
              initiallyExpanded: ui.sidebarGroupExpanded(
                'story_tools',
                fallback: false,
              ),
              onExpansionChanged: (v) =>
                  ui.setSidebarGroupExpanded('story_tools', v),
            ),
          ],
        );
      },
    );
  }

  /// The focused member's rich card (moved verbatim from chat_page's group
  /// branch — remove/objectives/avatar behavior unchanged).
  Widget _buildFocusedMemberCard(BuildContext context, ChatService chat) {
    final character = focused.card;
    final cast = chat.cast;
    final idx = cast.indexWhere((p) => p.id == focused.id);
    final canRemove = chat.groupCharacters.length > 1 && !chat.isGenerating;
    return GroupMemberCard(
      character: character,
      chatService: chat,
      avatarColor: groupCharacterColor(idx < 0 ? 0 : idx),
      isNextSpeaker: chat.nextCharacter?.name == character.name,
      isExpanded: true,
      onTap: chat.isGenerating
          ? () {}
          : () => chat.setNextCharacter(character),
      avatarFile: character.imagePath != null
          ? resolveCharImage(character.imagePath!)
          : null,
      ringCount: chat.growthRingCountFor(character),
      // > 1 (not > 2): removing the second-to-last member is allowed and
      // auto-collapses the group back to a 1:1.
      canRemove: canRemove,
      onRemove: canRemove
          ? () async {
              final groupRepo = Provider.of<GroupChatRepository>(
                context,
                listen: false,
              );
              await chat.removeCharacterFromGroup(character, groupRepo);
            }
          : null,
      onOpenObjectives: () {
        showDialog(
          context: context,
          builder: (_) => GroupObjectivesDialog(
            chatService: chat,
            groupCharacters: chat.groupCharacters,
            initialCharacter: character,
          ),
        );
      },
    );
  }
}

/// "Lite NPC" banner for realism-off scene guests (moved from chat_page).
class _LiteNpcBanner extends StatelessWidget {
  const _LiteNpcBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      margin: const EdgeInsets.only(bottom: SidebarTokens.sectionGap),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerOf(context),
        borderRadius: BorderRadius.circular(SidebarTokens.wellRadius),
        border: Border.all(
          color: AppColors.borderOf(context).withValues(alpha: 0.4),
        ),
      ),
      child: Row(
        children: [
          Icon(
            Icons.visibility_off,
            size: 16,
            color: AppColors.iconSecondary(context),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Lite NPC — no realism or needs tracking for this guest.',
              style: TextStyle(
                fontSize: 11,
                color: AppColors.textSecondary(context),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
