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

import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/story/story.dart';
import 'package:front_porch_ai/ui/pages/story_home/story_shelf_menu.dart';
import 'package:front_porch_ai/ui/story_studio/story_studio.dart';
import 'package:front_porch_ai/ui/theme/studio_colors.dart';
import 'package:front_porch_ai/utils/utils.dart';

/// A book on the shelf: cover, title, genre line, progress, where you are.
class StoryShelfCard extends StatelessWidget {
  final StoryProject project;

  const StoryShelfCard({super.key, required this.project});

  @override
  Widget build(BuildContext context) {
    final p = project;
    final st = storyShelfStatus(p);
    return StoryCard(
      key: ValueKey('story-book-${p.dbId}'),
      padding: const EdgeInsets.all(12),
      onTap: () => openStory(context, p),
      alignment: CrossAxisAlignment.stretch,
      children: [
        Stack(
          children: [
            Container(
              height: 84,
              padding: const EdgeInsets.all(8),
              alignment: Alignment.bottomLeft,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(7),
                gradient: const LinearGradient(
                  begin: Alignment(-0.6, -1),
                  end: Alignment(0.6, 1),
                  colors: [StudioColors.coverStart, StudioColors.coverEnd],
                ),
              ),
              child: Text(
                p.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: StudioType.prose(
                  context,
                  size: 14,
                  height: 1.2,
                  color: StudioColors.honeyOf(context),
                ),
              ),
            ),
            Positioned(top: 8, right: 8, child: _engineChip(p, st)),
          ],
        ),
        Row(
          children: [
            Expanded(
              child: Text(
                p.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: StudioType.ui(
                  context,
                  size: 14,
                  weight: FontWeight.w600,
                ),
              ),
            ),
            StoryShelfMenu(project: p),
          ],
        ),
        Text(
          storyGenreLine(p),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: StudioType.ui(
            context,
            size: 12,
            color: StudioColors.mutedOf(context),
          ),
        ),
        if (p.worldName.trim().isNotEmpty)
          Row(
            key: ValueKey('story-book-world-${p.dbId}'),
            children: [
              Icon(
                Icons.public,
                size: 12,
                color: StudioColors.mutedOf(context),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  p.worldName.trim(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: StudioType.ui(
                    context,
                    size: 12,
                    color: StudioColors.mutedOf(context),
                  ),
                ),
              ),
            ],
          ),
        StoryProgressBar(st.fraction, done: st.done),
        Row(
          children: [
            Expanded(
              child: Text(
                st.status,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: StudioType.ui(
                  context,
                  size: 12,
                  color: StudioColors.mutedOf(context),
                ),
              ),
            ),
            Text(
              formatRelativeTime(p.updatedAt),
              style: StudioType.ui(
                context,
                size: 12,
                color: StudioColors.mutedOf(context),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

Widget _engineChip(
  StoryProject p,
  ({String status, double fraction, bool done, bool setup}) st,
) => st.setup
    ? const StoryChip('Setup', tone: 'honey')
    : p.engineMode == StoryEngineMode.studio
    ? const StoryChip('Studio', tone: 'amber')
    : const StoryChip('Quick');

/// The phone row: avatar, title, status, engine chip, progress.
class StoryShelfRow extends StatelessWidget {
  final StoryProject project;

  const StoryShelfRow({super.key, required this.project});

  @override
  Widget build(BuildContext context) {
    final p = project;
    final st = storyShelfStatus(p);
    return StoryCard(
      key: ValueKey('story-book-${p.dbId}'),
      onTap: () => openStory(context, p),
      alignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            StoryAvatar(p.title),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    p.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: StudioType.ui(
                      context,
                      size: 14,
                      weight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    st.status,
                    style: StudioType.ui(
                      context,
                      size: 12,
                      color: StudioColors.mutedOf(context),
                    ),
                  ),
                ],
              ),
            ),
            _engineChip(p, st),
            StoryShelfMenu(project: p),
          ],
        ),
        StoryProgressBar(st.fraction, done: st.done),
      ],
    );
  }
}
