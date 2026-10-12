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
//
// The ChatPage app bar, including the sidebar toggle.

import 'dart:io';

import 'package:flutter/material.dart';

import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/utils/utils.dart';
import 'package:front_porch_ai/ui/widgets/widgets.dart';
import 'package:front_porch_ai/ui/chat_components/chat_components.dart';
import 'package:front_porch_ai/ui/theme/theme.dart';

/// Single AppBar for every chat. Driven by the unified [ChatService.cast]:
/// a cast of one renders the classic single-character header (avatar + name +
/// description); a cast of two or more renders stacked avatars (with emotion
/// rings when group realism is active) + a "N characters" subtitle. This is
/// the same header whether the extra speakers are full group members or Scene
/// Guests, so a 1:1 that gains a guest visually becomes a multi-speaker chat.
class ChatPageAppBar extends StatelessWidget implements PreferredSizeWidget {
  const ChatPageAppBar({
    super.key,
    required this.chatService,
    required this.coverFor,
    required this.sidebarOpen,
    required this.onToggleSidebar,
  });

  final ChatService chatService;
  final File? Function(ChatService chat, CharacterCard card) coverFor;
  final bool sidebarOpen;
  final VoidCallback onToggleSidebar;

  /// What the inner [AppBar] asks for (no toolbarHeight, no bottom).
  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    final cast = chatService.cast;
    final group = chatService.activeGroup;
    final isMulti = cast.length > 1;

    final Widget avatars;
    if (!isMulti) {
      final card = cast.isNotEmpty ? cast.first.card : null;
      final cover = card == null ? null : coverFor(chatService, card);
      // No portrait, or only the flat placeholder: the person icon.
      avatars = RealPortrait(
        file: cover,
        portrait: (_, file) => CircleAvatar(
          backgroundImage: FileImage(file),
          onBackgroundImageError: (_, _) {},
        ),
        noPortrait: (_) => CircleAvatar(
          backgroundColor: AppColors.surfaceContainerOf(context),
          child: Icon(Icons.person, color: AppColors.iconSecondary(context)),
        ),
      );
    } else {
      final shown = cast.length.clamp(0, 4);
      avatars = SizedBox(
        width: 24.0 + (shown - 1) * 16,
        height: 32,
        child: Stack(
          children: [
            for (int i = 0; i < shown; i++)
              Positioned(
                left: i * 16.0,
                child: Builder(
                  builder: (_) {
                    final card = cast[i].card;
                    final emo = chatService.isGroupRealismActive
                        ? chatService.getEmotionForGroupCharacter(card)
                        : null;
                    final fix = chatService.isGroupRealismActive
                        ? chatService.getFixationForGroupCharacter(card)
                        : null;
                    final tooltip = emo == null
                        ? card.name
                        : (fix != null && fix.isNotEmpty
                              ? '${card.name} • $emo\nFixated: $fix'
                              : '${card.name} • $emo');
                    return Tooltip(
                      message: tooltip,
                      child: Container(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: chatService.isGroupRealismActive
                              ? Border.all(
                                  color: EmotionLabels.ringColor(emo),
                                  width: 2.0,
                                )
                              : null,
                        ),
                        child: Builder(
                          builder: (_) {
                            final color = groupCharacterColor(i);
                            // No portrait, or only the flat placeholder: the
                            // member's initial.
                            return RealPortrait(
                              file: coverFor(chatService, card),
                              portrait: (_, file) => CircleAvatar(
                                radius: 16,
                                backgroundColor: color,
                                backgroundImage: FileImage(file),
                              ),
                              noPortrait: (_) => CircleAvatar(
                                radius: 16,
                                backgroundColor: color,
                                child: Text(
                                  card.name.isNotEmpty ? card.name[0] : '?',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
      );
    }

    final title = group?.name ?? (cast.isNotEmpty ? cast.first.name : '');
    final String? subtitle;
    if (isMulti) {
      subtitle = group != null
          ? '${cast.length} characters • ${group.turnOrder.name}'
          : '${cast.length} characters';
    } else {
      final desc = cast.isNotEmpty ? cast.first.card.description : '';
      subtitle = desc.isEmpty
          ? null
          : (desc.length > 30 ? '${desc.substring(0, 30)}...' : desc);
    }

    return AppBar(
      backgroundColor: AppColors.surfaceOf(context),
      elevation: 0,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back),
        onPressed: () => Navigator.of(context).pop(),
      ),
      title: Row(
        children: [
          avatars,
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary(context),
                ),
              ),
              if (subtitle != null)
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColors.textTertiary(context),
                  ),
                ),
            ],
          ),
        ],
      ),
      actions: [
        IconButton(
          icon: Icon(
            sidebarOpen ? Icons.last_page : Icons.first_page,
            color: AppColors.iconSecondary(context),
          ),
          tooltip: 'Toggle Sidebar',
          onPressed: onToggleSidebar,
        ),
        const SizedBox(width: 8),
      ],
    );
  }
}
