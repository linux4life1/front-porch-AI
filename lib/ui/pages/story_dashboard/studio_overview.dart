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
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/pages/story_dashboard/story_studio_actions.dart';
import 'package:front_porch_ai/ui/pages/story_dashboard/studio_overview_cards.dart';
import 'package:front_porch_ai/ui/pages/story_dashboard/studio_up_next_card.dart';
import 'package:front_porch_ai/ui/story_studio/story_studio.dart';
import 'package:front_porch_ai/ui/theme/studio_colors.dart';

/// Overview (sketch M): "where am I and what next" first, then the bible
/// with inline edits, the cast strip, the chat card, the engine card and
/// the story so far.
class StudioOverview extends StatelessWidget {
  final StoryProject project;
  final StoryPipelineService pipeline;
  final StoryStudioActions actions;
  final ValueChanged<StudioSection> onOpen;

  const StudioOverview({
    super.key,
    required this.project,
    required this.pipeline,
    required this.actions,
    required this.onOpen,
  });

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.of(context).size.width >= 900;
    final right = [
      StudioCastCard(
        project: project,
        onOpen: () => onOpen(StudioSection.cast),
      ),
      if (project.useChatHistory)
        StudioChatCard(
          project: project,
          onRedistill: () => actions.redistill(project),
        ),
      StudioEngineCard(project: project),
      StudioSoFarCard(
        project: project,
        onOpen: () => onOpen(StudioSection.lore),
      ),
    ];
    final worldLine = storyWorldLine(project, worldsOrNull(context));
    return SingleChildScrollView(
      key: const ValueKey('studio-overview'),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (worldLine != null) ...[
            Row(
              key: const ValueKey('studio-overview-world'),
              children: [
                Icon(
                  Icons.public,
                  size: 14,
                  color: StudioColors.honeyOf(context),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    worldLine,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: StudioType.ui(
                      context,
                      size: 12.5,
                      color: StudioColors.mutedOf(context),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
          ],
          StudioUpNextCard(
            project: project,
            pipeline: pipeline,
            actions: actions,
            onRead: () => onOpen(StudioSection.read),
          ),
          const SizedBox(height: 12),
          if (wide)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: StudioBibleCard(
                    project: project,
                    running: pipeline.isRunning,
                    actions: actions,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    children: [
                      for (var i = 0; i < right.length; i++) ...[
                        if (i > 0) const SizedBox(height: 12),
                        right[i],
                      ],
                    ],
                  ),
                ),
              ],
            )
          else ...[
            StudioBibleCard(
              project: project,
              running: pipeline.isRunning,
              actions: actions,
            ),
            for (final c in right) ...[const SizedBox(height: 12), c],
          ],
        ],
      ),
    );
  }
}

/// The story bible with inline edits, Rewrite arc and Regenerate.
class StudioBibleCard extends StatelessWidget {
  final StoryProject project;
  final bool running;
  final StoryStudioActions actions;

  const StudioBibleCard({
    super.key,
    required this.project,
    required this.running,
    required this.actions,
  });

  @override
  Widget build(BuildContext context) {
    final muted = StudioColors.mutedOf(context);
    Widget field(String label, String value, void Function(String) set) =>
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    label,
                    style: StudioType.ui(context, weight: FontWeight.w600),
                  ),
                ),
                StoryIconButton(
                  Icons.edit_outlined,
                  tooltip: 'Edit $label',
                  onPressed: () =>
                      actions.editBibleField(project, label, value, set),
                ),
              ],
            ),
            Text(
              value.isEmpty ? 'Not written yet.' : value,
              style: label == 'Concept'
                  ? StudioType.prose(
                      context,
                      size: 13.5,
                      color: value.isEmpty ? muted : null,
                    )
                  : StudioType.ui(
                      context,
                      size: 12.5,
                      color: value.isEmpty ? muted : null,
                    ),
            ),
          ],
        );
    return StoryCard(
      children: [
        Row(
          children: [
            const Expanded(child: StoryKeyLabel('Story bible')),
            Flexible(
              child: Wrap(
                alignment: WrapAlignment.end,
                children: [
                  if (project.engineMode == StoryEngineMode.studio &&
                      project.cast.isNotEmpty)
                    StoryButton.ghost(
                      'Rewrite arc…',
                      key: const ValueKey('story-rewrite-arc'),
                      icon: Icons.timeline,
                      onPressed: running
                          ? null
                          : () => actions.rewriteArc(project),
                    ),
                  StoryButton.ghost(
                    'Regenerate…',
                    icon: Icons.refresh,
                    onPressed: running
                        ? null
                        : () => actions.regenerateBible(project),
                  ),
                ],
              ),
            ),
          ],
        ),
        field('Concept', project.concept, (v) => project.concept = v),
        field('Status quo', project.statusQuo, (v) => project.statusQuo = v),
        field(
          'Inciting incident',
          project.incitingIncident,
          (v) => project.incitingIncident = v,
        ),
        field('Themes', project.themes, (v) => project.themes = v),
        if (project.twists.trim().isNotEmpty) ...[
          Row(
            children: [
              Expanded(
                child: Text(
                  'Twists planned',
                  style: StudioType.ui(context, weight: FontWeight.w600),
                ),
              ),
              const StoryChip('hidden from the reader', tone: 'honey'),
            ],
          ),
          Text(project.twists, style: StudioType.ui(context, size: 12.5)),
        ],
        if (project.threads.isNotEmpty)
          Text(
            '${project.threads.length} narrative thread${project.threads.length == 1 ? '' : 's'} · '
            '${project.lore.length} lore entr${project.lore.length == 1 ? 'y' : 'ies'}',
            style: StudioType.ui(context, size: 12, color: muted),
          ),
      ],
    );
  }
}
