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
import 'package:front_porch_ai/ui/story_studio/studio_running_overlay.dart';
import 'package:front_porch_ai/ui/story_studio/studio_widgets.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';
import 'package:front_porch_ai/ui/widgets/widgets.dart';

/// "How long ago" for the last-applied line.
String storyTimeAgo(DateTime at) {
  final d = DateTime.now().difference(at);
  if (d.inMinutes < 1) return 'just now';
  if (d.inHours < 1) return '${d.inMinutes} min ago';
  if (d.inDays < 1) return '${d.inHours} h ago';
  return '${d.inDays} day${d.inDays == 1 ? '' : 's'} ago';
}

/// The Director: describe a change in plain words, get a plan, tick what you
/// want, apply it, undo it.
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
  final _directive = TextEditingController();
  bool _protect = true;

  @override
  void dispose() {
    _directive.dispose();
    super.dispose();
  }

  StoryProject get p => widget.project;
  StoryPipelineService get pipeline => widget.pipeline;

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
    if (pipeline.isRunning) return StudioRunningOverlay(pipeline);
    final plan = p.directorPlan;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        WarmCard(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const StoryKeyLabel('What should change?'),
              const SizedBox(height: 8),
              StoryTextArea(
                key: const ValueKey('director-directive'),
                controller: _directive,
                hint:
                    'e.g. Teodor should be hiding that he set the wagon fire. '
                    'Plant hints before 3.3 and let Mara find out in '
                    'Sequence 5.',
                minLines: 3,
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Switch(
                    value: _protect,
                    activeThumbColor: AppColors.porchAmberOf(context),
                    onChanged: (v) {
                      setState(() => _protect = v);
                      pipeline.setDirectorProtection(p, v);
                    },
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Protect written prose (only touch unwritten scenes)',
                      style: TextStyle(
                        color: AppColors.textPrimary(context),
                        fontSize: 13,
                      ),
                    ),
                  ),
                  StoryPrimaryButton(
                    'Plan changes',
                    key: const ValueKey('director-plan'),
                    onPressed: p.acts.isEmpty
                        ? null
                        : () => _run(
                            () => pipeline.runDirectorPlan(
                              p,
                              _directive.text,
                              protectWrittenProse: _protect,
                            ),
                          ),
                  ),
                ],
              ),
              if (p.acts.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    'The Director needs a structure to work on. Build the '
                    'story bible and acts first.',
                    style: TextStyle(
                      color: AppColors.textTertiary(context),
                      fontSize: 12,
                    ),
                  ),
                ),
            ],
          ),
        ),
        if (plan != null) ...[const SizedBox(height: 12), _planCard(plan)],
        if (p.directorApplied != null) ...[
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Last applied: “${p.directorApplied!.directive}” · '
                  '${storyTimeAgo(p.directorApplied!.appliedAt)}',
                  style: TextStyle(
                    color: AppColors.textTertiary(context),
                    fontSize: 12,
                  ),
                ),
              ),
              TextButton(
                onPressed: () => _run(() async {
                  final ok = await pipeline.undoDirectorPlan(p);
                  if (!ok && mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                          'Nothing to undo — the snapshot for that plan is '
                          'gone.',
                        ),
                      ),
                    );
                  }
                }),
                child: const Text('Undo that plan'),
              ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _planCard(DirectorPlan plan) {
    final applied = plan.actions.any((a) => a.result.isNotEmpty);
    return WarmCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
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
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                plan.evaluation,
                style: TextStyle(
                  color: AppColors.textSecondary(context),
                  fontSize: 12.5,
                ),
              ),
            ),
          const SizedBox(height: 8),
          for (var i = 0; i < plan.actions.length; i++)
            _actionRow(plan, i, applied),
          const SizedBox(height: 10),
          Row(
            children: [
              StoryQuietButton(
                'Refine…',
                icon: Icons.tune,
                onPressed: applied ? null : _refine,
              ),
              const Spacer(),
              StoryQuietButton(
                'Discard',
                onPressed: () => _run(() => pipeline.discardDirectorPlan(p)),
              ),
              const SizedBox(width: 8),
              StoryPrimaryButton(
                applied
                    ? 'Applied'
                    : 'Apply ${plan.applicableCount} change'
                          '${plan.applicableCount == 1 ? '' : 's'}',
                key: const ValueKey('director-apply'),
                onPressed: applied || plan.applicableCount == 0
                    ? null
                    : () => _run(() => pipeline.applyDirectorPlan(p)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _actionRow(DirectorPlan plan, int index, bool applied) {
    final a = plan.actions[index];
    final target = StoryDirector.target(p, a);
    final tone = a.type.kind == 'Prose' ? 'terra' : 'honey';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: 44,
            child: Switch(
              value: a.enabled && !a.locked,
              activeThumbColor: AppColors.porchAmberOf(context),
              onChanged: a.locked || applied
                  ? null
                  : (v) => _run(
                      () => pipeline.setDirectorActionEnabled(p, index, v),
                    ),
            ),
          ),
          const SizedBox(width: 8),
          StoryChip(a.type.kind, tone: tone),
          const SizedBox(width: 8),
          Expanded(
            child: Text.rich(
              TextSpan(
                children: [
                  if (target.isNotEmpty)
                    TextSpan(
                      text: '$target: ',
                      style: TextStyle(color: AppColors.textSecondary(context)),
                    ),
                  TextSpan(text: a.summary),
                ],
              ),
              style: TextStyle(
                color: a.locked
                    ? AppColors.textTertiary(context)
                    : AppColors.textPrimary(context),
                fontSize: 13,
              ),
            ),
          ),
          if (a.locked) ...[
            const SizedBox(width: 6),
            const StoryChip('locked — written', tone: 'bad'),
          ],
          if (a.result == 'applied') ...[
            const SizedBox(width: 6),
            const StoryChip('applied', tone: 'teal'),
          ] else if (a.result.startsWith('failed')) ...[
            const SizedBox(width: 6),
            Tooltip(
              message: a.result,
              child: const StoryChip('could not apply', tone: 'bad'),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _refine() async {
    final controller = TextEditingController();
    final ok = await showWarmDialog<bool>(
      context,
      title: 'Refine the plan',
      icon: Icons.tune,
      width: 420,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const WarmDialogText(
            'Say what to change about the plan, e.g. “keep him '
            'sympathetic” or “do it in Sequence 4 instead”.',
          ),
          const SizedBox(height: 10),
          StoryTextArea(controller: controller, minLines: 3),
        ],
      ),
      actions: [
        warmDialogCancel(context, value: false),
        warmDialogConfirm(
          context,
          label: 'Revise plan',
          onPressed: () => Navigator.of(context).pop(true),
        ),
      ],
    );
    if (ok != true || controller.text.trim().isEmpty) return;
    final plan = p.directorPlan;
    await _run(
      () => pipeline.runDirectorPlan(
        p,
        plan?.directive ?? _directive.text,
        protectWrittenProse: _protect,
        refinement: controller.text,
      ),
    );
  }
}
