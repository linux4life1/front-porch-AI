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
import 'package:front_porch_ai/services/story/story.dart';
import 'package:front_porch_ai/ui/story_studio/story_studio.dart';
import 'package:front_porch_ai/ui/theme/studio_colors.dart';

/// The Write header: ‹ › scene walking, the scene title (tap to jump), the
/// running-step chip and the scene menu.
class StoryWriterHeader extends StatelessWidget {
  final StoryProject project;
  final StoryScene scene;
  final List<StoryBeat> beats;
  final StoryPipelineService pipeline;
  final int actIndex;
  final int sceneIndex;
  final void Function(int act, int scene)? onPickScene;
  final VoidCallback onTapTitle;
  final VoidCallback onWriteScene;
  final ValueChanged<bool> onPlanBeats;
  final VoidCallback onChangeLens;
  final VoidCallback onCopyScene;
  final VoidCallback onExportScene;
  final VoidCallback onRewriteScene;

  const StoryWriterHeader({
    super.key,
    required this.project,
    required this.scene,
    required this.beats,
    required this.pipeline,
    required this.actIndex,
    required this.sceneIndex,
    required this.onPickScene,
    required this.onTapTitle,
    required this.onWriteScene,
    required this.onPlanBeats,
    required this.onChangeLens,
    required this.onCopyScene,
    required this.onExportScene,
    required this.onRewriteScene,
  });

  @override
  Widget build(BuildContext context) {
    final refs = project.orderedScenes.toList();
    final at = refs.indexWhere(
      (r) => r.act == actIndex && r.index == sceneIndex,
    );
    final prev = at > 0 ? refs[at - 1] : null;
    final next = at >= 0 && at < refs.length - 1 ? refs[at + 1] : null;
    final written = project.beatsWritten(actIndex, sceneIndex);
    final studio = project.engineMode == StoryEngineMode.studio;
    final subtitle = [
      beats.isEmpty
          ? 'No beats yet'
          : 'Beat ${(written + 1).clamp(1, beats.length)} of ${beats.length}',
      if (studio && project.lensesEnabled)
        StoryLenses.resolve(project, scene.lens).name,
      if (scene.location.isNotEmpty) scene.location,
    ].join(' · ');
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: StudioColors.lineOf(context))),
      ),
      child: Row(
        children: [
          StoryIconButton(
            Icons.chevron_left,
            tooltip: prev == null ? 'First scene' : 'Previous scene',
            onPressed: prev == null
                ? null
                : () => onPickScene?.call(prev.act, prev.index),
          ),
          Expanded(
            child: InkWell(
              onTap: onTapTitle,
              borderRadius: BorderRadius.circular(6),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '${project.sceneLabel(actIndex, sceneIndex)} · '
                      '${scene.title.isEmpty ? 'Untitled scene' : scene.title}',
                      overflow: TextOverflow.ellipsis,
                      style: StudioType.ui(
                        context,
                        size: 15,
                        weight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      subtitle,
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
          StoryIconButton(
            Icons.chevron_right,
            tooltip: next == null ? 'Last scene' : 'Next scene',
            onPressed: next == null
                ? null
                : () => onPickScene?.call(next.act, next.index),
          ),
          const SizedBox(width: 8),
          if (pipeline.isRunning)
            StoryChip('● ${pipeline.currentStep}', tone: 'amber'),
          StoryMenuButton(
            key: const ValueKey('story-scene-menu'),
            entries: [
              StoryMenuEntry(
                'Write the whole scene',
                enabled: !pipeline.isRunning && beats.isNotEmpty,
                onSelect: onWriteScene,
              ),
              StoryMenuEntry(
                beats.isEmpty ? 'Plan beats' : 'Plan beats again…',
                enabled: !pipeline.isRunning,
                onSelect: () => onPlanBeats(beats.isNotEmpty),
              ),
              StoryMenuEntry(
                'Change lens…',
                enabled: studio && project.lensesEnabled,
                onSelect: onChangeLens,
              ),
              StoryMenuEntry(
                'Copy scene text',
                divider: true,
                enabled: written > 0,
                onSelect: onCopyScene,
              ),
              StoryMenuEntry(
                'Export scene…',
                enabled: written > 0,
                onSelect: onExportScene,
              ),
              StoryMenuEntry(
                'Rewrite scene…',
                divider: true,
                danger: true,
                enabled: !pipeline.isRunning && written > 0,
                onSelect: onRewriteScene,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
