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
import 'package:front_porch_ai/ui/story_studio/story_studio.dart';
import 'package:front_porch_ai/ui/theme/studio_colors.dart';

/// The Write bottom bar: rewrite the last written beat with a note, change
/// lens, and write the next beat.
class StoryWriterBottomBar extends StatelessWidget {
  final StoryProject project;
  final List<StoryBeat> beats;
  final StoryPipelineService pipeline;
  final int actIndex;
  final int sceneIndex;
  final ValueChanged<int> onRewriteWithNote;
  final VoidCallback onChangeLens;
  final ValueChanged<int> onWriteBeat;

  const StoryWriterBottomBar({
    super.key,
    required this.project,
    required this.beats,
    required this.pipeline,
    required this.actIndex,
    required this.sceneIndex,
    required this.onRewriteWithNote,
    required this.onChangeLens,
    required this.onWriteBeat,
  });

  @override
  Widget build(BuildContext context) {
    final written = project.beatsWritten(actIndex, sceneIndex);
    final studio = project.engineMode == StoryEngineMode.studio;
    final busy = pipeline.isRunning || beats.isEmpty;
    final done = written >= beats.length && beats.isNotEmpty;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      decoration: BoxDecoration(
        color: StudioColors.bgOf(context),
        border: Border(top: BorderSide(color: StudioColors.lineOf(context))),
      ),
      child: Row(
        children: [
          StoryButton(
            'Rewrite beat ${written.clamp(1, beats.isEmpty ? 1 : beats.length)} with a note…',
            key: const ValueKey('story-rewrite-beat'),
            onPressed: busy || written == 0
                ? null
                : () => onRewriteWithNote(written - 1),
          ),
          const SizedBox(width: 10),
          if (studio && project.lensesEnabled)
            StoryButton(
              'Change lens',
              key: const ValueKey('story-change-lens'),
              onPressed: onChangeLens,
            ),
          const Spacer(),
          StoryButton.primary(
            done ? 'Scene written' : 'Write next beat',
            key: const ValueKey('story-write-next'),
            onPressed: busy || done ? null : () => onWriteBeat(written),
          ),
        ],
      ),
    );
  }
}
