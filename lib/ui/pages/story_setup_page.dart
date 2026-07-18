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
// but WITHOUT ANY WARRANTY, without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
// GNU Affero General Public License for more details.
//
// You should have received a copy of the GNU Affero General Public License
// along with Front Porch AI. If not, see <https://www.gnu.org/licenses/>.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:front_porch_ai/models/story_project.dart';
import 'package:front_porch_ai/services/character_repository.dart';
import 'package:front_porch_ai/services/story_repository.dart';
import 'package:front_porch_ai/services/user_persona_service.dart';
import 'package:front_porch_ai/ui/pages/story_dashboard_page.dart';
import 'package:front_porch_ai/ui/story_setup/cast_step.dart';
import 'package:front_porch_ai/ui/story_setup/concept_step.dart';
import 'package:front_porch_ai/ui/story_setup/format_step.dart';
import 'package:front_porch_ai/ui/story_setup/setup_widgets.dart';
import 'package:front_porch_ai/ui/story_setup/story_setup_draft.dart';
import 'package:front_porch_ai/ui/story_setup/style_step.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';
import 'package:front_porch_ai/ui/widgets/ai_engine_status_card.dart';

/// New-story wizard — the standard creation-wizard shell (top-bar step dots +
/// linear progression, same pattern as `create_character_page.dart`), warm
/// porch throughout. Step one puts the AI engine front and center: stories
/// need a running, model-loaded backend, and this is where you see and fix
/// that before investing in a setup.
class StorySetupPage extends StatefulWidget {
  final String projectId;
  const StorySetupPage({super.key, required this.projectId});

  @override
  State<StorySetupPage> createState() => _StorySetupPageState();
}

class _StorySetupPageState extends State<StorySetupPage> {
  final _draft = StorySetupDraft();
  int _currentStep = 0;

  static const _stepLabels = [
    'Engine',
    'Concept',
    'Style',
    'Format',
    'Cast',
    'Review',
  ];

  @override
  void initState() {
    super.initState();
    final repo = Provider.of<StoryRepository>(context, listen: false);
    final charRepo = Provider.of<CharacterRepository>(context, listen: false);
    final project = repo.getById(widget.projectId);
    if (project != null) _draft.loadFrom(project, charRepo);
  }

  @override
  void dispose() {
    _draft.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.backgroundOf(context),
      appBar: AppBar(
        title: Row(
          children: [
            Icon(
              Icons.auto_stories,
              color: AppColors.porchHoneyOf(context),
              size: 22,
            ),
            const SizedBox(width: 8),
            const Text('New Porch Story'),
            const Spacer(),
            _buildStepIndicator(),
          ],
        ),
        backgroundColor: AppColors.cardOf(context),
        foregroundColor: AppColors.textPrimary(context),
        elevation: 0,
      ),
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 300),
        child: _buildStepBody(),
      ),
    );
  }

  // ── Step indicator (create_character_page pattern) ────────────────────────

  Widget _buildStepIndicator() {
    final children = <Widget>[];
    for (var i = 0; i < _stepLabels.length; i++) {
      if (i > 0) {
        children.add(
          Container(
            width: 24,
            height: 2,
            margin: const EdgeInsets.only(bottom: 14),
            color: AppColors.borderOf(context).withValues(alpha: 0.35),
          ),
        );
      }
      children.add(_stepDot(i, _stepLabels[i]));
    }
    return Row(mainAxisSize: MainAxisSize.min, children: children);
  }

  Widget _stepDot(int step, String label) {
    final isActive = _currentStep >= step;
    final isCurrent = _currentStep == step;
    final accent = AppColors.porchHoneyOf(context);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 24,
          height: 24,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: isActive ? accent : AppColors.surfaceContainerOf(context),
            border: isCurrent
                ? Border.all(color: AppColors.textPrimary(context), width: 2)
                : Border.all(
                    color: AppColors.borderOf(context).withValues(alpha: 0.3),
                  ),
          ),
          child: Center(
            child: isActive && !isCurrent
                ? Icon(
                    Icons.check,
                    size: 14,
                    color: AppColors.resolve(
                      context,
                      AppColors.onChaosAccent,
                      AppColors.userText,
                    ),
                  )
                : Text(
                    '${step + 1}',
                    style: TextStyle(
                      fontSize: 11,
                      color: isActive
                          ? AppColors.resolve(
                              context,
                              AppColors.onChaosAccent,
                              AppColors.userText,
                            )
                          : AppColors.textTertiary(context),
                    ),
                  ),
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: TextStyle(
            fontSize: 10,
            color: isActive
                ? AppColors.textSecondary(context)
                : AppColors.textTertiary(context),
          ),
        ),
      ],
    );
  }

  // ── Step bodies ────────────────────────────────────────────────────────────

  Widget _buildStepBody() {
    final Widget content;
    switch (_currentStep) {
      case 0:
        content = _buildEngineStep();
      case 1:
        content = ConceptStep(
          draft: _draft,
          onChanged: () => setState(() {}),
        );
      case 2:
        content = StyleStep(draft: _draft, onChanged: () => setState(() {}));
      case 3:
        content = FormatStep(draft: _draft, onChanged: () => setState(() {}));
      case 4:
        content = CastStep(draft: _draft, onChanged: () => setState(() {}));
      default:
        content = _buildReviewStep();
    }

    return Center(
      key: ValueKey('story-setup-step-$_currentStep'),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(28),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [content, _buildNavButtons()],
          ),
        ),
      ),
    );
  }

  Widget _buildEngineStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SetupSectionHeader(
          'AI Engine',
          Icons.memory,
          subtitle:
              'Stories are written by the same AI backend as chat. It must be '
              'running with a model loaded before anything can generate — '
              'story writing works best with strong models (a remote API or '
              'a large local model).',
        ),
        const SizedBox(height: 12),
        const AiEngineStatusCard(),
        const SizedBox(height: 28),
        const SetupSectionHeader(
          'Prompt Style',
          Icons.tune,
          subtitle:
              'How the story prompts are written for your model. This does '
              'NOT pick the model — that\'s the engine card above.',
        ),
        const SizedBox(height: 10),
        ...PromptTier.values.map(
          (tier) => SetupRadioTile(
            storyTierName(tier),
            storyTierDescription(tier),
            selected: _draft.tier == tier,
            onTap: () => setState(() => _draft.tier = tier),
          ),
        ),
      ],
    );
  }

  Widget _buildReviewStep() {
    final genres = _draft.selectedGenres.isEmpty
        ? '—'
        : _draft.selectedGenres.join(', ');
    final moods = _draft.selectedMoods.isEmpty
        ? '—'
        : _draft.selectedMoods.join(', ');
    final title = _draft.titleController.text.trim().isEmpty
        ? 'Untitled Story'
        : _draft.titleController.text.trim();

    Widget row(String label, String value) => Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 130,
            child: Text(
              label,
              style: TextStyle(
                color: AppColors.textTertiary(context),
                fontSize: 12,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                color: AppColors.textPrimary(context),
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SetupSectionHeader(
          'Ready to build your story bible',
          Icons.auto_awesome,
          subtitle:
              'The Story Architect turns your concept into a full bible — '
              'cast, world, themes, and hooks — which you can review and '
              'edit before any prose is written.',
        ),
        const SizedBox(height: 16),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.cardOf(context),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: AppColors.borderOf(context).withValues(alpha: 0.5),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              row('Title', title),
              row(
                'Concept',
                _draft.conceptController.text.trim().isEmpty
                    ? '— (required)'
                    : _draft.conceptController.text.trim(),
              ),
              row('Point of view', _draft.pov),
              row('Genres', genres),
              row('Moods', moods),
              row(
                'Style',
                _draft.writingStyle.isEmpty ? 'Default' : _draft.writingStyle,
              ),
              row(
                'Shape',
                '${_draft.proseLength} · ${_draft.narrativePace} · '
                    '${_draft.dialogueDensity} · ${_draft.actCount} acts · '
                    '${_draft.maturityRating}',
              ),
              row('Prompt style', storyTierName(_draft.tier)),
              row(
                'Cast',
                _draft.useChatHistory
                    ? '${_draft.selectedCharacterIds.length} character(s)'
                          '${_draft.includeUserPersona ? ' + you' : ''}, '
                          'chat history woven in'
                    : 'Fresh cast, invented by the Architect',
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        const AiEngineStatusCard(),
      ],
    );
  }

  // ── Navigation ─────────────────────────────────────────────────────────────

  Widget _buildNavButtons() {
    final isLast = _currentStep == _stepLabels.length - 1;
    final accent = AppColors.porchHoneyOf(context);

    return Padding(
      padding: const EdgeInsets.only(top: 32),
      child: Center(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_currentStep > 0) ...[
              SizedBox(
                height: 52,
                child: OutlinedButton.icon(
                  onPressed: () => setState(() => _currentStep -= 1),
                  icon: const Icon(Icons.arrow_back, size: 18),
                  label: const Text('Back', style: TextStyle(fontSize: 14)),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.textSecondary(context),
                    side: BorderSide(color: AppColors.borderOf(context)),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 16),
            ],
            SizedBox(
              width: 280,
              height: 52,
              child: ElevatedButton.icon(
                onPressed: _onNextPressed,
                icon: Icon(
                  isLast ? Icons.auto_awesome : Icons.arrow_forward,
                  size: 20,
                ),
                label: Text(
                  isLast
                      ? 'Generate Story Bible'
                      : 'Next: ${_stepLabels[_currentStep + 1]}',
                  style: const TextStyle(fontSize: 16),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: accent,
                  foregroundColor: AppColors.resolve(context, AppColors.onChaosAccent, AppColors.userText),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _onNextPressed() {
    // The concept is the one hard requirement — everything else has defaults.
    if (_currentStep == 1 &&
        _draft.conceptController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Describe your story concept first'),
          backgroundColor: AppColors.negativeAccentOf(context),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    if (_currentStep < _stepLabels.length - 1) {
      setState(() => _currentStep += 1);
      return;
    }
    _startGeneration();
  }

  Future<void> _startGeneration() async {
    if (_draft.conceptController.text.trim().isEmpty) {
      setState(() => _currentStep = 1);
      return;
    }
    final repo = Provider.of<StoryRepository>(context, listen: false);
    final charRepo = Provider.of<CharacterRepository>(context, listen: false);
    final personaService = Provider.of<UserPersonaService>(
      context,
      listen: false,
    );
    final project = repo.getById(widget.projectId);
    if (project == null) return;

    _draft.applyTo(project, charRepo, personaService);
    await repo.saveProject(project);

    if (mounted) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => StoryDashboardPage(
            projectId: widget.projectId,
            autoRunStoryArchitect: true,
          ),
        ),
      );
    }
  }
}
