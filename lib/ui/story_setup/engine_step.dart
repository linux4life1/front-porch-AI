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
import 'package:path/path.dart' as path;
import 'package:provider/provider.dart';

import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/services/story/story.dart';
import 'package:front_porch_ai/ui/story_setup/setup_widgets.dart';
import 'package:front_porch_ai/ui/story_setup/story_setup_draft.dart';
import 'package:front_porch_ai/ui/story_studio/studio_widgets.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';
import 'package:front_porch_ai/ui/widgets/widgets.dart';

part 'engine_step.lanes.dart';

/// "Main model · Qwen3 32B" / "Worker model · Gemma" — what each lane
/// would run on right now. The worker label is null when no worker is set.
({String main, String? worker}) storyLaneLabels(BuildContext context) {
  final storage = Provider.of<StorageService>(context, listen: false);
  final llm = Provider.of<LLMProvider>(context, listen: false);
  String name(String remote, String? local) {
    if (remote.isNotEmpty) return remote;
    if (local != null && local.isNotEmpty) {
      return path.basenameWithoutExtension(local);
    }
    return 'no model picked';
  }

  final settings = storage.backendSettings;
  final main = settings.backendType == 'kobold'
      ? name('', settings.lastUsedModelPath)
      : name(settings.remoteModelName, null);
  final worker = !llm.workerConfigured
      ? null
      : storage.workerBackendType == 'kobold'
      ? name('', storage.workerKoboldModelPath ?? settings.lastUsedModelPath)
      : name(storage.workerRemoteModelName, null);
  return (
    main: 'Main model · $main',
    worker: worker == null ? null : 'Worker model · $worker',
  );
}

/// Wizard step: how the story is written — engine mode, length, format,
/// which model does which job, review and lens switches, and the AI engine
/// itself.
class EngineStep extends StatelessWidget {
  final StorySetupDraft draft;
  final VoidCallback onChanged;

  const EngineStep({super.key, required this.draft, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final labels = storyLaneLabels(context);
    final pacing = StoryPacing.forTarget(draft.targetWords);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SetupSectionHeader('How should it write?', Icons.auto_awesome),
        const SizedBox(height: 10),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _modeCard(
                context,
                mode: StoryEngineMode.quick,
                title: 'Quick',
                chip: 'fewer calls',
                body:
                    'Plans and writes in one pass. No reviewers. Best for '
                    'small local models or a first draft.',
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _modeCard(
                context,
                mode: StoryEngineMode.studio,
                title: 'Studio',
                chip: 'recommended',
                chipAccent: true,
                body:
                    'Interviews the cast, checks every step, tracks '
                    'continuity and relationships. Slower, much steadier.',
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _panel(
                context,
                label: 'Target length',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _segmented(
                      context,
                      options: const {
                        'Short': 'Novella · 30k',
                        'Standard': 'Novel · 80k',
                        'Epic': 'Epic · 120k',
                      },
                      selected: draft.proseLength,
                      onSelect: (v) {
                        draft.proseLength = v;
                        onChanged();
                      },
                    ),
                    const SizedBox(height: 8),
                    Text(
                      draft.engineMode == StoryEngineMode.studio
                          ? pacing.summary
                          : 'About ${draft.targetWords ~/ 1000}k words',
                      style: TextStyle(
                        color: AppColors.textTertiary(context),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _panel(
                context,
                label: 'Format',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _segmented(
                      context,
                      options: const {
                        'novel': 'Novel',
                        'audioDrama': 'Audio drama',
                      },
                      selected: draft.storyFormat.name,
                      onSelect: (v) {
                        draft.storyFormat = v == 'audioDrama'
                            ? StoryFormat.audioDrama
                            : StoryFormat.novel;
                        onChanged();
                      },
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Audio drama writes a voiced script for your cast '
                      'voices.',
                      style: TextStyle(
                        color: AppColors.textTertiary(context),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        _panel(
          context,
          label: 'Who does which job',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: _laneField(
                      context,
                      'Planning',
                      draft.planningLane,
                      labels,
                      (v) => draft.planningLane = v,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _laneField(
                      context,
                      'Prose',
                      draft.proseLane,
                      labels,
                      (v) => draft.proseLane = v,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _laneField(
                      context,
                      'Review',
                      draft.reviewLane,
                      labels,
                      (v) => draft.reviewLane = v,
                    ),
                  ),
                ],
              ),
              if (labels.worker == null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    'No worker model is set up, so every job runs on the '
                    'main model. Add one under Settings → AI Engine to '
                    'send reviews to a smaller, faster model.',
                    style: TextStyle(
                      color: AppColors.textTertiary(context),
                      fontSize: 12,
                    ),
                  ),
                ),
              const SizedBox(height: 12),
              _toggleRow(
                context,
                title: 'Check each step before moving on',
                trailing: 'Off is faster',
                value: draft.reviewEnabled,
                onChanged: (v) {
                  draft.reviewEnabled = v;
                  onChanged();
                },
              ),
              _toggleRow(
                context,
                title: 'Narrative lenses (a writing mode per scene)',
                value: draft.lensesEnabled,
                onChanged: (v) {
                  draft.lensesEnabled = v;
                  onChanged();
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: 28),
        const SetupSectionHeader(
          'AI Engine',
          Icons.memory,
          subtitle:
              'Stories are written by the same AI backend as chat. It must be '
              'running with a model loaded before anything can generate.',
        ),
        const SizedBox(height: 12),
        const AiEngineStatusCard(),
        const SizedBox(height: 20),
        const SetupSectionHeader(
          'Prompt Style',
          Icons.tune,
          subtitle:
              'How the prompts are written for your model. This does NOT '
              'pick the model — that\'s the engine card above.',
        ),
        const SizedBox(height: 10),
        ...PromptTier.values.map(
          (tier) => SetupRadioTile(
            storyTierName(tier),
            storyTierDescription(tier),
            selected: draft.tier == tier,
            onTap: () {
              draft.tier = tier;
              onChanged();
            },
          ),
        ),
      ],
    );
  }

  Widget _modeCard(
    BuildContext context, {
    required StoryEngineMode mode,
    required String title,
    required String chip,
    required String body,
    bool chipAccent = false,
  }) {
    final selected = draft.engineMode == mode;
    final accent = AppColors.porchAmberOf(context);
    return InkWell(
      key: ValueKey('story-engine-${mode.name}'),
      borderRadius: BorderRadius.circular(12),
      onTap: () {
        draft.engineMode = mode;
        onChanged();
      },
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: selected
              ? accent.withValues(alpha: 0.08)
              : AppColors.cardOf(context),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected
                ? accent
                : AppColors.borderOf(context).withValues(alpha: 0.5),
            width: selected ? 2 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: AppColors.textPrimary(context),
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(width: 8),
                StoryChip(chip, tone: chipAccent ? 'amber' : ''),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              body,
              style: TextStyle(
                color: AppColors.textSecondary(context),
                fontSize: 12.5,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _panel(
    BuildContext context, {
    required String label,
    required Widget child,
  }) => WarmCard(
    padding: const EdgeInsets.all(14),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label.toUpperCase(),
          style: TextStyle(
            color: AppColors.textTertiary(context),
            fontSize: 11,
            letterSpacing: 0.8,
          ),
        ),
        const SizedBox(height: 10),
        child,
      ],
    ),
  );

  Widget _segmented(
    BuildContext context, {
    required Map<String, String> options,
    required String selected,
    required ValueChanged<String> onSelect,
  }) {
    final accent = AppColors.porchAmberOf(context);
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.borderOf(context)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final e in options.entries)
            InkWell(
              onTap: () => onSelect(e.key),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 7,
                ),
                color: selected == e.key ? accent : Colors.transparent,
                child: Text(
                  e.value,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: selected == e.key
                        ? FontWeight.w600
                        : FontWeight.w400,
                    color: selected == e.key
                        ? AppColors.onChaosAccent
                        : AppColors.textSecondary(context),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
