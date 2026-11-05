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

// The two sidebar pieces that are pure leaf widgets — the group's focused
// member card and the lite-guest banner — split out of sidebar_body.dart to
// keep that file under the 500-line ratchet. Behaviour is verbatim.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/dialogs/dialogs.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';
import 'package:front_porch_ai/ui/widgets/widgets.dart';
import '../mood/mood_look.dart';
import 'sidebar_tokens.dart';

/// The focused member's rich card (moved verbatim from chat_page's group
/// branch — remove/objectives/avatar behavior unchanged).
Widget buildFocusedMemberCard({
  required BuildContext context,
  required ChatParticipant focused,
  required ChatService chat,
  required MoodLook moodLook,
  required File? Function(String path) resolveCharImage,
}) {
  final character = focused.card;
  final cast = chat.cast;
  final idx = cast.indexWhere((p) => p.id == focused.id);
  // Two or more members, or three while directing (one left would end
  // Director Mode); removing the second-to-last otherwise collapses the
  // group back to a 1:1.
  final canRemove = chat.canRemoveCastMember && !chat.isGenerating;
  return GroupMemberCard(
    character: character,
    chatService: chat,
    moodLook: moodLook,
    avatarColor: groupCharacterColor(idx < 0 ? 0 : idx),
    isNextSpeaker: chat.nextCharacter?.name == character.name,
    isExpanded: true,
    onTap: chat.isGenerating ? () {} : () => chat.setNextCharacter(character),
    avatarFile: character.imagePath != null && character.imagePath!.isNotEmpty
        ? resolveCharImage(character.imagePath!)
        : null,
    ringCount: chat.growthRingCountFor(character),
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

/// Status-only banner for a focused lite guest. Promote lives on the
/// cast avatar strip — do not add a second control here.
class LiteNpcBanner extends StatelessWidget {
  const LiteNpcBanner({super.key, this.dragHandle});

  /// The reorder grip when this banner sits in the reorderable body.
  final Widget? dragHandle;

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
          if (dragHandle != null)
            // Opaque so a grip tap never reaches the banner.
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {},
              child: dragHandle!,
            ),
          const SizedBox(width: 8),
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
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
            decoration: BoxDecoration(
              color: AppColors.porchAmberOf(context).withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              'GUEST',
              style: TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.bold,
                color: AppColors.porchAmberOf(context),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
