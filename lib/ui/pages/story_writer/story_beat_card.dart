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
import 'package:flutter/services.dart';

import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/services/story/story.dart';
import 'package:front_porch_ai/ui/story_studio/story_studio.dart';
import 'package:front_porch_ai/ui/theme/studio_colors.dart';

/// One beat card (sketch O): quality chips, the continuity fix with Undo,
/// and the beat being written streaming in place.
class StoryBeatCard extends StatelessWidget {
  final StoryProject project;
  final int actIndex;
  final int sceneIndex;
  final List<StoryBeat> beats;
  final int beatIndex;
  final StoryPipelineService pipeline;
  final ValueChanged<String> onEditByHand;
  final VoidCallback onWrite;
  final VoidCallback onRewrite;
  final VoidCallback onRewriteWithNote;

  const StoryBeatCard({
    super.key,
    required this.project,
    required this.actIndex,
    required this.sceneIndex,
    required this.beats,
    required this.beatIndex,
    required this.pipeline,
    required this.onEditByHand,
    required this.onWrite,
    required this.onRewrite,
    required this.onRewriteWithNote,
  });

  @override
  Widget build(BuildContext context) {
    final b = beatIndex;
    final beat = beats[b];
    final prose =
        project.prose[StoryProjectShape.beatKey(actIndex, sceneIndex, b)];
    final text = prose?.final_ ?? prose?.draft ?? '';
    final written = project.beatsWritten(actIndex, sceneIndex);
    // The beat being written right now streams in place.
    final streaming =
        pipeline.isRunning &&
        text.isEmpty &&
        b == written &&
        pipeline.streamingText.isNotEmpty;
    final muted = StudioColors.mutedOf(context);
    final fix = prose?.fix;
    return StoryCard(
      key: ValueKey('story-beat-$b'),
      selected: streaming,
      children: [
        Row(
          children: [
            StoryChip('Beat ${b + 1}'),
            const SizedBox(width: 6),
            if (beat.type.isNotEmpty) StoryChip(beat.type, tone: 'honey'),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                beat.description,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: StudioType.ui(context, size: 12, color: muted),
              ),
            ),
            if (streaming)
              const StoryChip('writing…', tone: 'amber')
            else
              StoryMenuButton(
                key: ValueKey('story-beat-menu-$b'),
                entries: [
                  StoryMenuEntry(
                    'Edit text by hand',
                    enabled: text.isNotEmpty,
                    onSelect: () => onEditByHand(text),
                  ),
                  StoryMenuEntry(
                    text.isEmpty ? 'Write' : 'Rewrite',
                    enabled: !pipeline.isRunning,
                    onSelect: () => text.isEmpty ? onWrite() : onRewrite(),
                  ),
                  StoryMenuEntry(
                    'Rewrite with a note…',
                    enabled: !pipeline.isRunning && text.isNotEmpty,
                    onSelect: onRewriteWithNote,
                  ),
                  StoryMenuEntry(
                    'Copy',
                    enabled: text.isNotEmpty,
                    onSelect: () =>
                        Clipboard.setData(ClipboardData(text: text)),
                  ),
                ],
              ),
          ],
        ),
        if (text.isNotEmpty) _qualityChips(text),
        if (fix != null) _fixCard(context, fix),
        if (streaming)
          Text.rich(
            TextSpan(
              text: pipeline.streamingText,
              children: [
                TextSpan(
                  text: '▍',
                  style: TextStyle(color: StudioColors.amberOf(context)),
                ),
              ],
            ),
            style: StudioType.prose(context),
          )
        else if (text.isNotEmpty)
          SelectableText(text, style: StudioType.prose(context))
        else if (beat.anchor.isNotEmpty)
          Text(
            'Anchor: ${beat.anchor}',
            style: StudioType.ui(
              context,
              size: 12,
              color: muted,
            ).copyWith(fontStyle: FontStyle.italic),
          ),
      ],
    );
  }

  Widget _qualityChips(String prose) {
    final quality = StoryQuality.analyze(
      prose,
      bannedPhrases: [...project.bannedPhrases, ...project.autoBannedPhrases],
    );
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final chip in quality.chips)
          StoryChip(chip.label, tone: chip.tone.name),
      ],
    );
  }

  /// "Continuity: fixed" with the reason, the patched lines as
  /// strike-through / insert, and Undo.
  Widget _fixCard(BuildContext context, ContinuityFix fix) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        children: [
          const StoryChip('Continuity: fixed', tone: 'bad'),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              fix.reason,
              style: StudioType.ui(
                context,
                size: 12,
                color: StudioColors.mutedOf(context),
              ),
            ),
          ),
          StoryButton.ghost(
            'Undo fix',
            key: ValueKey('story-undo-fix-$beatIndex'),
            onPressed: pipeline.isRunning
                ? null
                : () => pipeline.undoContinuityFix(
                    project,
                    actIndex,
                    sceneIndex,
                    beatIndex,
                  ),
          ),
        ],
      ),
      for (final edit in fix.edits)
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: edit.find,
                  style: const TextStyle(
                    decoration: TextDecoration.lineThrough,
                    color: StudioColors.diffDelFg,
                    backgroundColor: StudioColors.diffDelBg,
                  ),
                ),
                const TextSpan(text: ' '),
                TextSpan(
                  text: edit.replace,
                  style: const TextStyle(
                    color: StudioColors.diffInsFg,
                    backgroundColor: StudioColors.diffInsBg,
                  ),
                ),
              ],
            ),
            style: StudioType.prose(context, size: 13.5),
          ),
        ),
    ],
  );
}
