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

part of 'story_dashboard_page.dart';

/// The Overview's "Up next" card: where the story stands and the one thing
/// to do next. Split from the overview part.
extension _StoryDashboardUpNext on _StoryDashboardPageState {
  Widget _upNextCard(StoryProject project, StoryPipelineService pipeline) {
    final running = pipeline.isRunning;
    final next = _nextScene(project);
    final seq = next == null
        ? null
        : project.sequences
              .where((s) => s.number == next.scene.sequence)
              .firstOrNull;
    final String title;
    final String detail;
    final Widget primary;
    // While the bible is building, the interviews fill the cast long before
    // the arc and its review land — the card must not flip to "Bible ready"
    // in the middle of that.
    if (project.acts.isEmpty && (project.cast.isEmpty || running)) {
      title = running ? 'Building the story bible…' : 'The bible is not built';
      detail = running
          ? pipeline.statusMessage
          : 'Cast, themes, threads and lore come from your idea.';
      primary = StoryButton.primary(
        'Build the bible',
        onPressed: running ? null : _runStoryArchitect,
      );
    } else if (project.acts.isEmpty) {
      title = 'Bible ready';
      detail = 'Next: the acts and the first sequence\'s scenes.';
      primary = StoryButton.primary(
        'Build acts',
        key: const ValueKey('story-build-acts'),
        onPressed: running ? null : () => _buildActs(project),
      );
    } else if (next == null && project.hasUnoutlined) {
      title = project.orderedScenes.isEmpty
          ? 'Acts ready'
          : 'Next part not outlined yet';
      // The acts land before the sequences are planned; while that runs the
      // card carries the engine's status line instead of an offer.
      detail = running
          ? pipeline.statusMessage
          : 'Continue writing outlines what comes next and writes its first '
                'scene.';
      primary = StoryButton.primary(
        'Continue writing',
        key: const ValueKey('story-continue'),
        onPressed: running ? null : () => _continueWriting(project),
      );
    } else if (next == null) {
      title = 'The whole story is written';
      detail =
          '${thousands(project.wordCount)} words. Read it, or ask the '
          'Director for changes.';
      primary = StoryButton.primary(
        'Read',
        onPressed: () => _open(StudioSection.read),
      );
    } else {
      final beats =
          project.beats[StoryProjectShape.sceneKey(next.act, next.index)] ??
          const [];
      final written = project.beatsWritten(next.act, next.index);
      title =
          '${project.sceneLabel(next.act, next.index)} · ${next.scene.title}';
      detail = [
        beats.isEmpty
            ? 'beats not planned yet'
            : written > 0
            ? 'beat ${written + 1} of ${beats.length}'
            : '${beats.length} beats planned',
        if (project.lensesEnabled && next.scene.lens.isNotEmpty)
          StoryLenses.forProject(project)
                  .where(
                    (l) => l.id == StoryLenses.normalizeId(next.scene.lens),
                  )
                  .firstOrNull
                  ?.name ??
              '',
        if (next.scene.castNames.isNotEmpty) next.scene.castNames.join(', '),
      ].where((s) => s.isNotEmpty).join(' · ');
      primary = StoryButton.primary(
        'Continue writing',
        key: const ValueKey('story-continue'),
        onPressed: running ? null : () => _continueWriting(project),
      );
    }
    return StoryCard(
      selected: true,
      children: [
        Row(
          children: [
            const Expanded(child: StoryKeyLabel('Up next')),
            if (seq != null)
              StoryChip(
                'Sequence ${seq.number} of ${project.sequences.length}',
              ),
          ],
        ),
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: StudioType.ui(context, weight: FontWeight.w700),
                  ),
                  Text(
                    detail,
                    style: StudioType.ui(
                      context,
                      size: 12,
                      color: StudioColors.mutedOf(context),
                    ),
                  ),
                ],
              ),
            ),
            if (project.acts.isNotEmpty || project.cast.isNotEmpty) ...[
              StoryButton(
                'Autopilot…',
                key: const ValueKey('story-autopilot'),
                onPressed:
                    running ||
                        next == null &&
                            project.acts.isNotEmpty &&
                            !project.hasUnoutlined
                    ? null
                    : () => _autopilot(project),
              ),
              const SizedBox(width: 10),
            ],
            primary,
          ],
        ),
      ],
    );
  }

  /// The next scene with unwritten beats (or none planned), in story order.
  ({int act, int index, StoryScene scene})? _nextScene(StoryProject project) {
    for (final ref in project.orderedScenes) {
      final count =
          project
              .beats[StoryProjectShape.sceneKey(ref.act, ref.index)]
              ?.length ??
          0;
      if (count == 0 || project.beatsWritten(ref.act, ref.index) < count) {
        return (act: ref.act, index: ref.index, scene: ref.scene);
      }
    }
    return null;
  }
}
