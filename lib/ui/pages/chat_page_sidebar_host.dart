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

part of 'chat_page.dart';

/// App bar chrome, including the sidebar toggle.
extension _ChatPageSidebarHost on _ChatPageState {
  /// Single AppBar for every chat. Driven by the unified [ChatService.cast]:
  /// a cast of one renders the classic single-character header (avatar + name +
  /// description); a cast of two or more renders stacked avatars (with emotion
  /// rings when group realism is active) + a "N characters" subtitle. This is
  /// the same header whether the extra speakers are full group members or Scene
  /// Guests, so a 1:1 that gains a guest visually becomes a multi-speaker chat.
  PreferredSizeWidget _buildAppBar(
    BuildContext context,
    ChatService chatService,
  ) {
    final cast = chatService.cast;
    final group = chatService.activeGroup;
    final isMulti = cast.length > 1;

    final Widget avatars;
    if (!isMulti) {
      final card = cast.isNotEmpty ? cast.first.card : null;
      final cover = card == null ? null : _coverFor(chatService, card);
      avatars = CircleAvatar(
        backgroundImage: cover != null ? FileImage(cover) : null,
        onBackgroundImageError: cover != null ? (_, _) {} : null,
        child: cover == null ? const Icon(Icons.person) : null,
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
                            final cover = _coverFor(chatService, card);
                            return CircleAvatar(
                              radius: 16,
                              backgroundColor:
                                  _ChatPageState._groupCharacterColor(i),
                              backgroundImage: cover != null
                                  ? FileImage(cover)
                                  : null,
                              child: cover == null
                                  ? Text(
                                      card.name.isNotEmpty ? card.name[0] : '?',
                                      style: const TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    )
                                  : null,
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
            _sidebarWidth > 0 ? Icons.last_page : Icons.first_page,
            color: AppColors.iconSecondary(context),
          ),
          tooltip: 'Toggle Sidebar',
          onPressed: () => rebuildState(
            () => _sidebarWidth = _sidebarWidth > 0
                ? 0
                : SidebarTokens.widthFromEnvironment(),
          ),
        ),
        const SizedBox(width: 8),
      ],
    );
  }
}
