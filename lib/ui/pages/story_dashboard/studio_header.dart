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
import 'package:front_porch_ai/services/audiobook_generator_service.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/services/story/story.dart';
import 'package:front_porch_ai/ui/pages/story_dashboard/story_studio_actions.dart';
import 'package:front_porch_ai/ui/pages/story_home_view.dart';
import 'package:front_porch_ai/ui/pages/story_setup_page.dart';
import 'package:front_porch_ai/ui/story_studio/story_studio.dart';
import 'package:front_porch_ai/ui/theme/studio_colors.dart';

/// The studio header (sketch M): ← Stories, title, where you are, the one
/// Stop while a run is on, Setup, ⋯.
class StudioHeader extends StatelessWidget {
  final StoryProject project;
  final StoryPipelineService pipeline;
  final StoryStudioActions actions;

  const StudioHeader({
    super.key,
    required this.project,
    required this.pipeline,
    required this.actions,
  });

  @override
  Widget build(BuildContext context) {
    final st = storyShelfStatus(project);
    final running = pipeline.isRunning;
    // "Act II · 41,200 / 80,000" gains the unit here; the shelf has no room.
    final status = running && project.acts.isEmpty
        ? 'Building the bible…'
        : st.status.contains(' / ')
        ? '${st.status} words'
        : st.status;
    final world = project.worldName.trim();
    final subtitle = world.isEmpty ? status : '$status · $world';
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 8, 12, 8),
      decoration: BoxDecoration(
        color: StudioColors.sideOf(context),
        border: Border(bottom: BorderSide(color: StudioColors.lineOf(context))),
      ),
      child: Row(
        children: [
          StoryButton.ghost(
            '← Stories',
            key: const ValueKey('studio-back'),
            onPressed: () => Navigator.of(context).pop(),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: InkWell(
              onTap: () => renameStory(context, project),
              borderRadius: BorderRadius.circular(6),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      project.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: StudioType.ui(
                        context,
                        size: 15,
                        weight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: StudioType.ui(
                        context,
                        size: 12.5,
                        color: StudioColors.mutedOf(context),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          if (running) ...[
            StoryChip(
              pipeline.stopRequested
                  ? 'Stopping after this step…'
                  : '● ${pipeline.currentStep}',
              tone: 'amber',
            ),
            const SizedBox(width: 8),
            StoryButton(
              'Stop',
              key: const ValueKey('story-stop'),
              onPressed: pipeline.stopRequested ? null : pipeline.requestStop,
            ),
            const SizedBox(width: 8),
          ],
          const StudioAudiobookChip(),
          StoryButton.ghost(
            'Setup',
            key: const ValueKey('studio-setup'),
            onPressed: running
                ? null
                : () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => StorySetupPage(projectId: project.dbId!),
                    ),
                  ),
          ),
          StoryMenuButton(
            key: const ValueKey('studio-menu'),
            entries: [
              StoryMenuEntry(
                'Export eBook (.epub)',
                enabled: project.wordCount > 0,
                onSelect: () => actions.exportEpub(project),
              ),
              StoryMenuEntry(
                'Export audiobook (.wav)',
                enabled: project.wordCount > 0,
                onSelect: () => actions.exportAudiobook(project),
              ),
              StoryMenuEntry(
                'Export text (.md)',
                enabled: project.wordCount > 0,
                onSelect: () => actions.exportText(project),
              ),
              StoryMenuEntry(
                'Rename',
                divider: true,
                onSelect: () => renameStory(context, project),
              ),
              StoryMenuEntry(
                'Delete story…',
                danger: true,
                enabled: !running,
                onSelect: () => actions.deleteStory(project),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// A slim status while an audiobook compiles, with Abort.
class StudioAudiobookChip extends StatelessWidget {
  const StudioAudiobookChip({super.key});

  @override
  Widget build(BuildContext context) {
    final service = context.watch<AudiobookGeneratorService>();
    if (!service.isGenerating) return const SizedBox.shrink();
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        StoryChip(
          'Exporting audiobook ${(service.progress * 100).round()}%',
          tone: 'honey',
        ),
        StoryButton.ghost('Abort', onPressed: service.stop),
        const SizedBox(width: 4),
      ],
    );
  }
}
