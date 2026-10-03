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

import 'package:front_porch_ai/database/database.dart' hide World;
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/story_setup/story_setup_draft.dart';
import 'package:front_porch_ai/ui/story_studio/story_studio.dart';
import 'package:front_porch_ai/ui/theme/studio_colors.dart';
import 'package:front_porch_ai/utils/utils.dart';

/// "Choose a chat…": every 1:1 chat, newest first, as a studio dialog.
/// Resolves to the chosen chat or null.
Future<StoryChatSource?> showChatSourcePicker(BuildContext context) async {
  final db = Provider.of<AppDatabase>(context, listen: false);
  final chars = Provider.of<CharacterRepository>(context, listen: false);
  final userName = Provider.of<UserPersonaService>(
    context,
    listen: false,
  ).persona.name;
  final rows = <_ChatRow>[];
  for (final c in chars.characters) {
    final id = c.dbId;
    if (id == null) continue;
    for (final s in await db.getSessionsForCharacter(id)) {
      rows.add(
        _ChatRow(c.name, id, s.id, s.name ?? '', s.summary ?? '', s.createdAt),
      );
    }
  }
  rows.sort((a, b) => b.createdAt.compareTo(a.createdAt));
  if (!context.mounted) return null;
  return showStoryDialog<StoryChatSource>(
    context,
    title: 'Start from a chat',
    width: 460,
    body: rows.isEmpty
        ? Text(
            'No chats yet. Talk with a character first, then come back.',
            style: StudioType.ui(
              context,
              size: 12.5,
              color: StudioColors.mutedOf(context),
            ),
          )
        : Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final r in rows.take(30))
                InkWell(
                  key: ValueKey('story-chat-${r.sessionId}'),
                  borderRadius: BorderRadius.circular(8),
                  onTap: () => Navigator.pop(
                    context,
                    StoryChatSource(
                      characterId: r.characterId,
                      characterName: r.characterName,
                      sessionId: r.sessionId,
                      recap: r.summary,
                      userName: userName,
                      lastAt: r.createdAt,
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(
                      children: [
                        StoryAvatar(r.characterName),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                r.characterName,
                                style: StudioType.ui(
                                  context,
                                  weight: FontWeight.w600,
                                ),
                              ),
                              Text(
                                [
                                  if (r.sessionName.isNotEmpty) r.sessionName,
                                  formatRelativeTime(r.createdAt),
                                ].join(' · '),
                                style: StudioType.ui(
                                  context,
                                  size: 12,
                                  color: StudioColors.mutedOf(context),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
    actions: (ctx) => [
      StoryButton.ghost('Cancel', onPressed: () => Navigator.pop(ctx)),
    ],
  );
}

class _ChatRow {
  final String characterName;
  final String characterId;
  final String sessionId;
  final String sessionName;
  final String summary;
  final DateTime createdAt;
  _ChatRow(
    this.characterName,
    this.characterId,
    this.sessionId,
    this.sessionName,
    this.summary,
    this.createdAt,
  );
}
