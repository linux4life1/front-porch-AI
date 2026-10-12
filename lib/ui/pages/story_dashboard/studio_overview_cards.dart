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
import 'package:front_porch_ai/ui/pages/story_setup_page.dart';
import 'package:front_porch_ai/ui/story_studio/story_studio.dart';
import 'package:front_porch_ai/ui/theme/studio_colors.dart';

/// Number of `[EVENT N]` markers in a distilled timeline — the chat card's
/// count. The pattern must stay byte-identical to the one the distiller
/// itself counts with (`story_pipeline_service.llm.dart`) and to the web
/// twin's `/\[EVENT \d+\]/g`; a line count (or a double-escaped copy of the
/// pattern) reports the wrong number.
int distilledEventCount(String timeline) =>
    RegExp(r'\[EVENT \d+\]').allMatches(timeline).length;

/// The cast strip: up to six avatars and every name.
class StudioCastCard extends StatelessWidget {
  final StoryProject project;
  final VoidCallback onOpen;

  const StudioCastCard({
    super.key,
    required this.project,
    required this.onOpen,
  });

  @override
  Widget build(BuildContext context) => StoryCard(
    children: [
      Row(
        children: [
          const Expanded(child: StoryKeyLabel('Cast')),
          StoryButton.ghost('Open →', onPressed: onOpen),
        ],
      ),
      if (project.cast.isEmpty)
        Text(
          'The bible invents the cast.',
          style: StudioType.ui(
            context,
            size: 12.5,
            color: StudioColors.mutedOf(context),
          ),
        )
      else
        Row(
          children: [
            for (final m in project.cast.take(6)) ...[
              StoryAvatar(m.name, imagePath: m.portrait),
              const SizedBox(width: 6),
            ],
            const SizedBox(width: 4),
            Expanded(
              child: Text(
                project.cast.map((m) => m.name).join(', '),
                maxLines: 2,
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
    ],
  );
}

/// What the chat distilled into a timeline, with Redistill.
class StudioChatCard extends StatelessWidget {
  final StoryProject project;
  final VoidCallback onRedistill;

  const StudioChatCard({
    super.key,
    required this.project,
    required this.onRedistill,
  });

  @override
  Widget build(BuildContext context) {
    final events = distilledEventCount(project.distilledTimeline);
    return StoryCard(
      children: [
        Row(
          children: [
            const Expanded(child: StoryKeyLabel('From the chat')),
            StoryButton.ghost(
              'Redistill…',
              icon: Icons.refresh,
              onPressed: onRedistill,
            ),
          ],
        ),
        Text(
          events == 0
              ? 'Not distilled yet.'
              : '$events event${events == 1 ? '' : 's'} on the timeline'
                    '${project.faithfulMode ? ' · faithful' : ' · inspired by'}',
          style: StudioType.ui(context, size: 12.5),
        ),
        if (events > 0)
          StoryButton.ghost(
            'View timeline',
            onPressed: () => showStoryDialog<void>(
              context,
              title: 'Timeline',
              width: 560,
              body: Text(
                project.distilledTimeline,
                style: StudioType.ui(context, size: 12.5),
              ),
              actions: (ctx) => [
                StoryButton.ghost('Close', onPressed: () => Navigator.pop(ctx)),
              ],
            ),
          ),
      ],
    );
  }
}

/// The engine mode, checks, lenses and the three lanes.
class StudioEngineCard extends StatelessWidget {
  final StoryProject project;

  const StudioEngineCard({super.key, required this.project});

  @override
  Widget build(BuildContext context) {
    final storage = Provider.of<StorageService>(context, listen: false);
    final llm = Provider.of<LLMProvider>(context, listen: false);
    final studio = project.engineMode == StoryEngineMode.studio;
    String short(StoryLaneChoice c) =>
        storyLaneLabel(storage, llm, c).split(' · ').last;
    return StoryCard(
      children: [
        Row(
          children: [
            const Expanded(child: StoryKeyLabel('Engine')),
            StoryButton.ghost(
              'Change',
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => StorySetupPage(projectId: project.dbId!),
                ),
              ),
            ),
          ],
        ),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            studio
                ? const StoryChip('Studio', tone: 'amber')
                : const StoryChip('Quick'),
            if (studio)
              StoryChip(
                project.reviewEnabled ? 'Checks on' : 'Checks off',
                tone: project.reviewEnabled ? 'teal' : '',
              ),
            if (studio)
              StoryChip(project.lensesEnabled ? 'Lenses on' : 'Lenses off'),
          ],
        ),
        Text(
          'Planning ${short(project.planningLane)} · Prose '
          '${short(project.proseLane)} · Review ${short(project.reviewLane)}',
          style: StudioType.ui(
            context,
            size: 12,
            color: StudioColors.mutedOf(context),
          ),
        ),
      ],
    );
  }
}

/// The latest sequence summary.
class StudioSoFarCard extends StatelessWidget {
  final StoryProject project;
  final VoidCallback onOpen;

  const StudioSoFarCard({
    super.key,
    required this.project,
    required this.onOpen,
  });

  @override
  Widget build(BuildContext context) {
    final latest = project.sequences
        .where((s) => s.summary.trim().isNotEmpty)
        .lastOrNull;
    return StoryCard(
      children: [
        Row(
          children: [
            const Expanded(child: StoryKeyLabel('Story so far')),
            StoryButton.ghost('Open →', onPressed: onOpen),
          ],
        ),
        Text(
          latest?.summary ?? 'Nothing written yet.',
          maxLines: 4,
          overflow: TextOverflow.ellipsis,
          style: StudioType.ui(
            context,
            size: 12.5,
            color: latest == null ? StudioColors.mutedOf(context) : null,
          ),
        ),
      ],
    );
  }
}
