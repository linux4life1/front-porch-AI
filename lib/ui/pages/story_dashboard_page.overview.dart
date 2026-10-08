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

/// Number of `[EVENT N]` markers in a distilled timeline — the chat card's
/// count. The pattern must stay byte-identical to the one the distiller
/// itself counts with (`story_pipeline_service.llm.dart`) and to the web
/// twin's `/\[EVENT \d+\]/g`; a line count (or a double-escaped copy of the
/// pattern) reports the wrong number.
int distilledEventCount(String timeline) =>
    RegExp(r'\[EVENT \d+\]').allMatches(timeline).length;

/// Overview (sketch M): "where am I and what next" first, then the bible
/// with inline edits, the cast strip, the chat card, the engine card and
/// the story so far.
extension _StoryDashboardOverview on _StoryDashboardPageState {
  Widget _buildOverview(StoryProject project, StoryPipelineService pipeline) {
    final wide = MediaQuery.of(context).size.width >= 900;
    final right = [
      _castCard(project),
      if (project.useChatHistory) _chatCard(project),
      _engineCard(project),
      _soFarCard(project),
    ];
    return SingleChildScrollView(
      key: const ValueKey('studio-overview'),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _upNextCard(project, pipeline),
          const SizedBox(height: 12),
          if (wide)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: _bibleCard(project, pipeline)),
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
            _bibleCard(project, pipeline),
            for (final c in right) ...[const SizedBox(height: 12), c],
          ],
        ],
      ),
    );
  }

  Widget _bibleCard(StoryProject project, StoryPipelineService pipeline) {
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
                  onPressed: () => _editBibleField(project, label, value, set),
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
                      onPressed: pipeline.isRunning
                          ? null
                          : () => _rewriteArc(project),
                    ),
                  StoryButton.ghost(
                    'Regenerate…',
                    icon: Icons.refresh,
                    onPressed: pipeline.isRunning
                        ? null
                        : () => _regenerateBible(project),
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

  Future<void> _editBibleField(
    StoryProject project,
    String label,
    String value,
    void Function(String) set,
  ) async {
    final ctl = TextEditingController(text: value);
    final ok = await showStoryDialog<bool>(
      context,
      title: label,
      width: 520,
      body: StoryTextArea(controller: ctl, minLines: 4, prose: true),
      actions: (ctx) => [
        StoryButton.ghost('Cancel', onPressed: () => Navigator.pop(ctx, false)),
        StoryButton.primary('Save', onPressed: () => Navigator.pop(ctx, true)),
      ],
    );
    if (ok != true || !mounted) return;
    set(ctl.text.trim());
    await Provider.of<StoryRepository>(
      context,
      listen: false,
    ).saveProject(project);
    rebuildState(() {});
  }

  Widget _castCard(StoryProject project) => StoryCard(
    children: [
      Row(
        children: [
          const Expanded(child: StoryKeyLabel('Cast')),
          StoryButton.ghost(
            'Open →',
            onPressed: () => _open(StudioSection.cast),
          ),
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

  Widget _chatCard(StoryProject project) {
    final events = distilledEventCount(project.distilledTimeline);
    return StoryCard(
      children: [
        Row(
          children: [
            const Expanded(child: StoryKeyLabel('From the chat')),
            StoryButton.ghost(
              'Redistill…',
              icon: Icons.refresh,
              onPressed: () => _redistill(project),
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

  Widget _engineCard(StoryProject project) {
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

  Widget _soFarCard(StoryProject project) {
    final latest = project.sequences
        .where((s) => s.summary.trim().isNotEmpty)
        .lastOrNull;
    return StoryCard(
      children: [
        Row(
          children: [
            const Expanded(child: StoryKeyLabel('Story so far')),
            StoryButton.ghost(
              'Open →',
              onPressed: () => _open(StudioSection.lore),
            ),
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
