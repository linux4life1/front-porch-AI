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
import 'package:front_porch_ai/services/story/story.dart';
import 'package:front_porch_ai/ui/story_studio/story_studio.dart';
import 'package:front_porch_ai/ui/theme/studio_colors.dart';
import 'package:front_porch_ai/ui/widgets/widgets.dart';

part 'story_structure_page.tree.dart';

/// Structure (sketch N): the act / sequence / scene board. Every scene row
/// has a ⋯ menu for the things that used to be scattered. Lives inside the
/// studio; [onOpenWriter] jumps to Write for a scene.
class StoryStructurePage extends StatefulWidget {
  final String projectId;
  final bool embedded;
  final void Function(int act, int scene)? onOpenWriter;

  const StoryStructurePage({
    super.key,
    required this.projectId,
    this.embedded = false,
    this.onOpenWriter,
  });

  @override
  State<StoryStructurePage> createState() => _StoryStructurePageState();
}

class _StoryStructurePageState extends State<StoryStructurePage> {
  /// Which acts are open; the first act opens by default.
  final Set<int> _open = {0};

  void rebuildState(VoidCallback fn) => setState(fn);

  @override
  Widget build(BuildContext context) {
    return Consumer2<StoryRepository, StoryPipelineService>(
      builder: (context, repo, pipeline, _) {
        final project = repo.getById(widget.projectId);
        if (project == null) return const SizedBox.shrink();
        final body = SingleChildScrollView(
          key: const ValueKey('studio-structure'),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildToolbar(project, pipeline),
              const SizedBox(height: 12),
              if (project.acts.isEmpty)
                StoryEmptyState(
                  title: 'No structure yet',
                  detail: project.cast.isEmpty
                      ? 'Build the bible first; the acts follow from it.'
                      : 'The bible is ready. Build the acts and the first '
                            'sequence\'s scenes.',
                  action: project.cast.isEmpty ? null : 'Build acts',
                  onAction: pipeline.isRunning
                      ? null
                      : () => _buildActs(project, pipeline),
                )
              else
                _buildStructureTree(project, pipeline),
            ],
          ),
        );
        if (widget.embedded) return body;
        return StudioTheme(
          child: Scaffold(
            backgroundColor: StudioColors.bgOf(context),
            body: body,
          ),
        );
      },
    );
  }

  Widget _buildToolbar(StoryProject project, StoryPipelineService pipeline) {
    final running = pipeline.isRunning;
    final total = project.orderedScenes.length;
    final written = project.orderedScenes
        .where((r) => project.beatsWritten(r.act, r.index) > 0)
        .length;
    return Row(
      children: [
        StoryButton.primary(
          'Continue writing',
          key: const ValueKey('story-continue'),
          onPressed: running || project.acts.isEmpty
              ? null
              : () => _continueWriting(project, pipeline),
        ),
        const SizedBox(width: 10),
        StoryButton(
          'Autopilot…',
          key: const ValueKey('story-autopilot'),
          onPressed: running || project.acts.isEmpty
              ? null
              : () => _autopilot(project, pipeline),
        ),
        const Spacer(),
        if (total > 0)
          Text(
            '$written of $total scenes written',
            style: StudioType.ui(
              context,
              size: 12,
              color: StudioColors.mutedOf(context),
            ),
          ),
      ],
    );
  }

  Future<void> _guarded(Future<void> Function() work) async {
    try {
      await work();
      if (mounted) setState(() {});
    } catch (e) {
      if (mounted) showAiErrorSnackBar(context, e);
    }
  }

  Future<void> _buildActs(StoryProject p, StoryPipelineService pipeline) =>
      _guarded(() => pipeline.runActStructurer(p));

  Future<void> _continueWriting(
    StoryProject p,
    StoryPipelineService pipeline,
  ) => _guarded(() async {
    final wrote = await pipeline.writeNextScene(p);
    if (!wrote && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('The whole story is written.')),
      );
    }
  });

  Future<void> _autopilot(StoryProject p, StoryPipelineService pipeline) async {
    final total = p.orderedScenes.length;
    final written = p.orderedScenes
        .where((r) => p.beatsWritten(r.act, r.index) > 0)
        .length;
    final left = total - written;
    final ok = await showStoryConfirm(
      context,
      title: 'Write the whole story?',
      body:
          'Autopilot writes the ${total == 0 ? 'scenes' : '$left scene${left == 1 ? '' : 's'} that ${left == 1 ? 'is' : 'are'}'} left, '
          'one after another${p.reviewEnabled ? ', with reviews on' : ''}. It '
          'will not touch ${written > 0 ? 'the $written already written or ' : ''}'
          'the bible. You can stop at any time and keep what\'s done.',
      confirmLabel: 'Start',
    );
    if (!ok) return;
    await _guarded(() => pipeline.runAutopilot(p));
  }

  Future<void> _planSequence(
    StoryProject p,
    int number,
    StoryPipelineService pipeline,
  ) => _guarded(() => pipeline.planSequenceScenes(p, number));

  Future<void> _generateFullAct(
    StoryProject p,
    int act,
    StoryPipelineService pipeline,
  ) => _guarded(() => pipeline.generateFullAct(p, act));

  Future<void> _planBeats(
    StoryProject p,
    int act,
    int scene,
    StoryPipelineService pipeline,
  ) => _guarded(() => pipeline.runBeatDirector(p, act, scene));

  Future<void> _writeScene(
    StoryProject p,
    int act,
    int scene,
    StoryPipelineService pipeline,
  ) => _guarded(() => pipeline.autoWriteScene(p, act, scene));

  Future<void> _rewriteScene(
    StoryProject p,
    int act,
    int scene,
    StoryPipelineService pipeline,
  ) async {
    final sc = p.scenes[act]?[scene];
    if (sc == null) return;
    final ok = await showStoryConfirm(
      context,
      title: 'Rewrite ${p.sceneLabel(act, scene)} · ${sc.title}?',
      body: storyRewriteSceneBody(p, act, scene),
      confirmLabel: 'Rewrite',
      destructive: true,
    );
    if (!ok) return;
    await _guarded(() async {
      StoryStructure.clearSceneProse(p, act, scene);
      await Provider.of<StoryRepository>(context, listen: false).saveProject(p);
      await pipeline.regenerateSceneProse(p, act, scene);
    });
  }

  Future<void> _editScene(StoryProject p, int act, int scene) async {
    final sc = p.scenes[act]?[scene];
    if (sc == null) return;
    final title = TextEditingController(text: sc.title);
    final desc = TextEditingController(text: sc.description);
    final ok = await showStoryDialog<bool>(
      context,
      title: 'Edit ${p.sceneLabel(act, scene)}',
      width: 480,
      body: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          StoryField(controller: title, hint: 'Title'),
          const SizedBox(height: 8),
          StoryTextArea(controller: desc, hint: 'What happens', minLines: 3),
        ],
      ),
      actions: (ctx) => [
        StoryButton.ghost('Cancel', onPressed: () => Navigator.pop(ctx, false)),
        StoryButton.primary('Save', onPressed: () => Navigator.pop(ctx, true)),
      ],
    );
    if (ok != true || !mounted) return;
    sc
      ..title = title.text.trim()
      ..description = desc.text.trim();
    await Provider.of<StoryRepository>(context, listen: false).saveProject(p);
    setState(() {});
  }

  Future<void> _insertAfter(StoryProject p, int act, int scene) async {
    final title = TextEditingController();
    final desc = TextEditingController();
    final ok = await showStoryDialog<bool>(
      context,
      title: 'Insert a scene after ${p.sceneLabel(act, scene)}',
      width: 480,
      body: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          StoryField(controller: title, hint: 'Title'),
          const SizedBox(height: 8),
          StoryTextArea(controller: desc, hint: 'What happens', minLines: 3),
        ],
      ),
      actions: (ctx) => [
        StoryButton.ghost('Cancel', onPressed: () => Navigator.pop(ctx, false)),
        StoryButton.primary(
          'Insert',
          onPressed: () => Navigator.pop(ctx, true),
        ),
      ],
    );
    if (ok != true || !mounted || title.text.trim().isEmpty) return;
    final before = p.scenes[act]?[scene];
    StoryStructure.insertScene(
      p,
      act,
      scene + 1,
      StoryScene(
        number: scene + 2,
        title: title.text.trim(),
        description: desc.text.trim(),
        sequence: before?.sequence ?? 0,
      ),
    );
    await Provider.of<StoryRepository>(context, listen: false).saveProject(p);
    setState(() {});
  }

  Future<void> _deleteScene(StoryProject p, int act, int scene) async {
    final sc = p.scenes[act]?[scene];
    if (sc == null) return;
    final written = p.beatsWritten(act, scene);
    final ok = await showStoryConfirm(
      context,
      title: 'Delete ${p.sceneLabel(act, scene)} · ${sc.title}?',
      body: written > 0
          ? 'Its prose, beats and the continuity facts it recorded are '
                'removed. Later scenes renumber.'
          : 'Its beats are removed. Later scenes renumber.',
      confirmLabel: 'Delete',
      destructive: true,
    );
    if (!ok || !mounted) return;
    StoryStructure.removeScene(p, act, scene);
    await Provider.of<StoryRepository>(context, listen: false).saveProject(p);
    setState(() {});
  }

  Future<void> _editAct(StoryProject p, int act) async {
    final a = p.acts[act];
    final title = TextEditingController(text: a.title);
    final desc = TextEditingController(text: a.description);
    final ok = await showStoryDialog<bool>(
      context,
      title: 'Act ${romanAct(act + 1)}',
      width: 480,
      body: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          StoryField(controller: title, hint: 'Title'),
          const SizedBox(height: 8),
          StoryTextArea(
            controller: desc,
            hint: 'What the act does',
            minLines: 3,
          ),
        ],
      ),
      actions: (ctx) => [
        StoryButton.ghost('Cancel', onPressed: () => Navigator.pop(ctx, false)),
        StoryButton.primary('Save', onPressed: () => Navigator.pop(ctx, true)),
      ],
    );
    if (ok != true || !mounted) return;
    a
      ..title = title.text.trim()
      ..description = desc.text.trim();
    await Provider.of<StoryRepository>(context, listen: false).saveProject(p);
    setState(() {});
  }
}
