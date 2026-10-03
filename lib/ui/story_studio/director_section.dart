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
import 'package:front_porch_ai/ui/story_studio/studio_buttons.dart';
import 'package:front_porch_ai/ui/story_studio/studio_cards.dart';
import 'package:front_porch_ai/ui/story_studio/studio_theme.dart';
import 'package:front_porch_ai/ui/story_studio/studio_widgets.dart';
import 'package:front_porch_ai/ui/theme/studio_colors.dart';
import 'package:front_porch_ai/ui/widgets/widgets.dart';
import 'package:front_porch_ai/utils/utils.dart';

/// The Director (sketch Q): describe a change in plain words, get a plan,
/// tick what you want, apply it, undo it. The directive and the protect
/// switch are remembered on the project; an applied plan folds into the
/// "Last applied" line.
class DirectorSection extends StatefulWidget {
  final StoryProject project;
  final StoryPipelineService pipeline;

  const DirectorSection({
    super.key,
    required this.project,
    required this.pipeline,
  });

  @override
  State<DirectorSection> createState() => _DirectorSectionState();
}

class _DirectorSectionState extends State<DirectorSection> {
  late final TextEditingController _directive = TextEditingController(
    text: widget.project.directorDraft,
  );

  StoryProject get p => widget.project;
  StoryPipelineService get pipeline => widget.pipeline;

  @override
  void dispose() {
    if (p.directorDraft != _directive.text) {
      p.directorDraft = _directive.text;
      // Remember the box without blocking the pop.
      Provider.of<StoryRepository>(context, listen: false).saveProject(p);
    }
    _directive.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() work) async {
    try {
      await work();
    } catch (e) {
      if (mounted) showAiErrorSnackBar(context, e);
    }
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final plan = p.directorPlan;
    final applied = plan?.actions.any((a) => a.result.isNotEmpty) ?? false;
    final running = pipeline.isRunning;
    final muted = StudioColors.mutedOf(context);
    return ListView(
      key: const ValueKey('studio-director'),
      padding: const EdgeInsets.all(16),
      children: [
        StoryCard(
          children: [
            const StoryKeyLabel('What should change?'),
            StoryTextArea(
              key: const ValueKey('director-directive'),
              controller: _directive,
              hint:
                  'e.g. Teodor should be hiding that he set the wagon fire. '
                  'Plant hints before 3.3 and let Mara find out in '
                  'Sequence 5.',
              minLines: 3,
              onChanged: (v) => p.directorDraft = v,
            ),
            Row(
              children: [
                Expanded(
                  child: StoryToggleRow(
                    key: const ValueKey('director-protect'),
                    value: p.directorProtect,
                    onChanged: running
                        ? null
                        : (v) {
                            setState(() => p.directorProtect = v);
                            _run(() => pipeline.setDirectorProtection(p, v));
                          },
                    label:
                        'Protect written prose (only touch unwritten scenes)',
                  ),
                ),
                StoryButton.primary(
                  running ? 'Planning…' : 'Plan changes',
                  key: const ValueKey('director-plan'),
                  onPressed: p.acts.isEmpty || running
                      ? null
                      : () => _run(
                          () => pipeline.runDirectorPlan(
                            p,
                            _directive.text,
                            protectWrittenProse: p.directorProtect,
                          ),
                        ),
                ),
              ],
            ),
            if (p.acts.isEmpty)
              Text(
                'The Director needs a structure to work on. Build the story '
                'bible and acts first.',
                style: StudioType.ui(context, size: 12, color: muted),
              ),
          ],
        ),
        if (plan != null && !applied) ...[
          const SizedBox(height: 12),
          _planCard(plan, running),
        ],
        if (p.directorApplied != null) ...[
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Last applied: “${p.directorApplied!.directive}” · '
                  '${formatRelativeTime(p.directorApplied!.appliedAt)} · '
                  '${p.directorApplied!.changeCount} change'
                  '${p.directorApplied!.changeCount == 1 ? '' : 's'}',
                  style: StudioType.ui(context, size: 12, color: muted),
                ),
              ),
              StoryButton.ghost(
                'Undo that plan',
                key: const ValueKey('director-undo'),
                onPressed: running
                    ? null
                    : () => _run(() async {
                        final ok = await pipeline.undoDirectorPlan(p);
                        if (!ok && mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                'Nothing to undo: the snapshot for that plan '
                                'is gone.',
                              ),
                            ),
                          );
                        }
                      }),
              ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _planCard(DirectorPlan plan, bool running) {
    final muted = StudioColors.mutedOf(context);
    return StoryCard(
      children: [
        Row(
          children: [
            Expanded(
              child: StoryKeyLabel(
                'Proposed plan · ${plan.actions.length} change'
                '${plan.actions.length == 1 ? '' : 's'} · '
                '${plan.scope == 'arc' ? 'whole arc' : 'local'}',
              ),
            ),
            if (plan.review == 'consistent')
              const StoryChip('Reviewed: consistent', tone: 'teal')
            else if (plan.review.isNotEmpty)
              Flexible(
                child: StoryChip('Review: ${plan.review}', tone: 'honey'),
              ),
          ],
        ),
        if (plan.evaluation.isNotEmpty)
          Text(
            plan.evaluation,
            style: StudioType.ui(context, size: 12.5, color: muted),
          ),
        for (var i = 0; i < plan.actions.length; i++)
          _actionRow(plan, i, running),
        Row(
          children: [
            StoryButton.ghost(
              'Refine…',
              icon: Icons.tune,
              onPressed: running ? null : _refine,
            ),
            const Spacer(),
            StoryButton(
              'Discard…',
              key: const ValueKey('director-discard'),
              onPressed: running ? null : _discard,
            ),
            const SizedBox(width: 8),
            StoryButton.primary(
              'Apply ${plan.applicableCount} change'
              '${plan.applicableCount == 1 ? '' : 's'}',
              key: const ValueKey('director-apply'),
              onPressed: running || plan.applicableCount == 0
                  ? null
                  : () => _run(() => pipeline.applyDirectorPlan(p)),
            ),
          ],
        ),
      ],
    );
  }

  Widget _actionRow(DirectorPlan plan, int index, bool running) {
    final a = plan.actions[index];
    final target = StoryDirector.target(p, a);
    final tone = a.type.kind == 'Prose' ? 'terra' : 'honey';
    return Row(
      children: [
        SizedBox(
          height: 24,
          child: FittedBox(
            child: Switch(
              value: a.enabled && !a.locked,
              onChanged: a.locked || running
                  ? null
                  : (v) => _run(
                      () => pipeline.setDirectorActionEnabled(p, index, v),
                    ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        StoryChip(a.type.kind, tone: tone),
        const SizedBox(width: 8),
        Expanded(
          child: Text.rich(
            TextSpan(
              children: [
                if (target.isNotEmpty)
                  TextSpan(
                    text: '$target: ',
                    style: TextStyle(color: StudioColors.mutedOf(context)),
                  ),
                TextSpan(text: a.summary),
              ],
            ),
            style: StudioType.ui(
              context,
              color: a.locked
                  ? StudioColors.faintOf(context)
                  : StudioColors.inkOf(context),
            ),
          ),
        ),
        if (a.locked) ...[
          const SizedBox(width: 6),
          const StoryChip('locked — written', tone: 'bad'),
        ],
        if (a.result.startsWith('failed')) ...[
          const SizedBox(width: 6),
          Tooltip(
            message: a.result,
            child: const StoryChip('could not apply', tone: 'bad'),
          ),
        ],
      ],
    );
  }

  Future<void> _discard() async {
    final ok = await showStoryConfirm(
      context,
      title: 'Discard this plan?',
      body: 'The proposed changes are dropped. Nothing in the story changes.',
      confirmLabel: 'Discard',
      destructive: true,
    );
    if (!ok) return;
    await _run(() => pipeline.discardDirectorPlan(p));
  }

  Future<void> _refine() async {
    final controller = TextEditingController();
    final ok = await showStoryDialog<bool>(
      context,
      title: 'Refine the plan',
      width: 420,
      body: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Say what to change about the plan, e.g. “keep him sympathetic” '
            'or “do it in Sequence 4 instead”.',
            style: StudioType.ui(
              context,
              size: 12.5,
              color: StudioColors.mutedOf(context),
            ),
          ),
          const SizedBox(height: 10),
          StoryTextArea(controller: controller, minLines: 3),
        ],
      ),
      actions: (ctx) => [
        StoryButton.ghost('Cancel', onPressed: () => Navigator.pop(ctx, false)),
        StoryButton.primary(
          'Revise plan',
          onPressed: () => Navigator.pop(ctx, true),
        ),
      ],
    );
    if (ok != true || controller.text.trim().isEmpty) return;
    final plan = p.directorPlan;
    await _run(
      () => pipeline.runDirectorPlan(
        p,
        plan?.directive ?? _directive.text,
        protectWrittenProse: p.directorProtect,
        refinement: controller.text,
      ),
    );
  }
}
