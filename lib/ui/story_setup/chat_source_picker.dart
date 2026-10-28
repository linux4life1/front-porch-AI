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
import 'package:front_porch_ai/services/story/story.dart';
import 'package:front_porch_ai/ui/story_setup/story_setup_draft.dart';
import 'package:front_porch_ai/ui/story_studio/story_studio.dart';
import 'package:front_porch_ai/ui/theme/studio_colors.dart';
import 'package:front_porch_ai/utils/utils.dart';

/// "Choose a chat…": every chat the user has written in, 1:1 and group,
/// newest first, with a search box, as a studio dialog. Resolves to the
/// chosen chat or null; a group chat comes with its roster's cards
/// (docs/design/stories-from-group-chats.md §5).
Future<StoryChatSource?> showChatSourcePicker(BuildContext context) async {
  final pipeline = Provider.of<StoryPipelineService>(context, listen: false);
  final userName = Provider.of<UserPersonaService>(
    context,
    listen: false,
  ).persona.name;
  final groupsDir = _groupsDirOrNull(context);
  final rows = await pipeline.chatSources();
  if (!context.mounted) return null;
  final picked = await showStoryDialog<StoryChatSourceRow>(
    context,
    title: 'Start from a chat',
    width: 460,
    body: rows.isEmpty
        ? Builder(
            builder: (context) => Text(
              'No chats yet. Talk with a character first, then come back.',
              style: StudioType.ui(
                context,
                size: 12.5,
                color: StudioColors.mutedOf(context),
              ),
            ),
          )
        : _ChatSourceList(rows: rows),
    actions: (ctx) => [
      StoryButton.ghost('Cancel', onPressed: () => Navigator.pop(ctx)),
    ],
  );
  if (picked == null) return null;
  final groupId = picked.groupId;
  return StoryChatSource(
    characterId: picked.characterId,
    characterName: picked.characterName,
    sessionId: picked.sessionId,
    recap: picked.summary,
    userName: userName,
    messageCount: picked.messageCount,
    lastAt: picked.createdAt,
    groupId: groupId,
    // The list carries names only; the cast needs the cards.
    members: groupId == null
        ? const []
        : await pipeline.groupRoster(groupId, groupsDir: groupsDir),
  );
}

/// Where group avatars live, for the roster's portraits; null when no
/// storage is provided (tests of the step alone).
String? _groupsDirOrNull(BuildContext context) {
  try {
    return Provider.of<StorageService>(context, listen: false).groupsDir.path;
  } on ProviderNotFoundException {
    return null;
  }
}

class _ChatSourceList extends StatefulWidget {
  const _ChatSourceList({required this.rows});

  final List<StoryChatSourceRow> rows;

  @override
  State<_ChatSourceList> createState() => _ChatSourceListState();
}

class _ChatSourceListState extends State<_ChatSourceList> {
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final muted = StudioColors.mutedOf(context);
    final found = filterChatSources(widget.rows, _search.text);
    final shown = found.take(kChatSourcePageSize).toList();
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        StoryField(
          key: const ValueKey('story-chat-search'),
          controller: _search,
          hint: 'Search by character, group or chat name',
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 8),
        if (found.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(
              'No chat matches that search.',
              style: StudioType.ui(context, size: 12.5, color: muted),
            ),
          ),
        for (final r in shown)
          InkWell(
            key: ValueKey('story-chat-${r.sessionId}'),
            borderRadius: BorderRadius.circular(8),
            onTap: () => Navigator.pop(context, r),
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
                            if (r.isGroup) r.memberLine,
                            if (r.sessionName.isNotEmpty) r.sessionName,
                            formatRelativeTime(r.createdAt),
                            '${r.messageCount} messages',
                          ].join(' · '),
                          style: StudioType.ui(context, size: 12, color: muted),
                        ),
                      ],
                    ),
                  ),
                  if (r.isGroup) ...[
                    const StoryChip('group', tone: 'amber'),
                    const SizedBox(width: 6),
                  ],
                  if (r.isShort)
                    const Tooltip(
                      message:
                          'Fewer than $kShortChatMessages messages. '
                          'There may not be enough here for a story.',
                      child: StoryChip('short chat', tone: 'honey'),
                    ),
                ],
              ),
            ),
          ),
        if (found.length > shown.length)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              'Showing ${shown.length} of ${found.length} chats. '
              'Search to narrow them down.',
              style: StudioType.ui(context, size: 12, color: muted),
            ),
          ),
      ],
    );
  }
}
