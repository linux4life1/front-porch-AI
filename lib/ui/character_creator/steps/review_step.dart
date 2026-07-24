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

import 'package:front_porch_ai/services/character_repository.dart';
import 'package:front_porch_ai/services/storage_service.dart';
import 'package:front_porch_ai/ui/avatar_creation/avatar_generation_panel.dart';
import 'package:front_porch_ai/ui/character_creator/creator_state.dart';
import 'package:front_porch_ai/ui/character_creator/creator_state_engine.dart';
import 'package:front_porch_ai/ui/character_creator/widgets/review_lorebook_section.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';
import 'package:front_porch_ai/ui/widgets/app_text_field.dart';

/// Review & edit step: the shared Portrait & Avatars panel in the left rail
/// (phase #12 — it replaced the bespoke avatar generation controls) + editable
/// card fields + lorebook cherry-pick. The wizard shell owns Save & Finish /
/// reset / nav. The panel saves the card FIRST when the user generates or
/// uploads (Save & Finish then updates the same card in place), so a failed
/// engine can never cost the generated writing.
class ReviewStep extends StatelessWidget {
  final CreatorState state;

  const ReviewStep({super.key, required this.state});

  Color _accent(BuildContext context) => AppColors.porchAmberOf(context);

  @override
  Widget build(BuildContext context) {
    if (state.generatedCard == null) {
      return Center(
        key: const ValueKey('review-error'),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.error_outline,
              size: 64,
              color: AppColors.resolve(
                context,
                Colors.redAccent,
                Colors.red.shade700,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Generation failed. The LLM did not produce valid output.',
              style: TextStyle(
                color: AppColors.textSecondary(context),
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: () {
                state.generationPreview = '';
                state.currentStep = 2;
              },
              icon: const Icon(Icons.arrow_back),
              label: const Text('Try Again'),
              style: ElevatedButton.styleFrom(
                backgroundColor: _accent(context),
              ),
            ),
          ],
        ),
      );
    }

    final card = state.generatedCard!;
    return SingleChildScrollView(
      key: const ValueKey('review'),
      padding: const EdgeInsets.all(32),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Left rail — the SHARED Portrait & Avatars panel + name + tags.
          SizedBox(
            width: 360,
            child: Column(
              children: [
                AvatarGenerationPanel(
                  ensureCardSaved: () async {
                    // Persist the card before any image lands; a later
                    // Save & Finish updates this same card in place.
                    if (!context.mounted) return null;
                    final ok = await state.saveCharacter(
                      repo: Provider.of<CharacterRepository>(
                        context,
                        listen: false,
                      ),
                      storage: Provider.of<StorageService>(
                        context,
                        listen: false,
                      ),
                    );
                    return ok ? state.generatedCard : null;
                  },
                  initialPrompt: state.buildPortraitPromptSeed(),
                ),
                const SizedBox(height: 16),
                Text(
                  card.name,
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary(context),
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                if (card.tags.isNotEmpty)
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    alignment: WrapAlignment.center,
                    children: card.tags
                        .map(
                          (tag) => Chip(
                            label: Text(
                              tag,
                              style: TextStyle(
                                fontSize: 11,
                                color: AppColors.textSecondary(context),
                              ),
                            ),
                            backgroundColor:
                                AppColors.surfaceContainerOf(context),
                            side: BorderSide.none,
                            visualDensity: VisualDensity.compact,
                          ),
                        )
                        .toList(),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 32),
          // Right column — editable fields + lorebook cherry-pick.
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Review & Edit',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary(context),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'The AI generated the following character card. Review and '
                  'edit before saving.',
                  style: TextStyle(
                    color: AppColors.textTertiary(context),
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 24),
                _editableField(
                  context,
                  'Description',
                  state.descController,
                  maxLines: 6,
                ),
                _editableField(
                  context,
                  'Personality',
                  state.personalityController,
                  maxLines: 4,
                ),
                _editableField(
                  context,
                  'Scenario',
                  state.scenarioController,
                  maxLines: 3,
                ),
                _editableField(
                  context,
                  'First Message',
                  state.firstMessageController,
                  maxLines: 6,
                ),
                _editableField(
                  context,
                  'Example Dialogue',
                  state.exampleDialogueController,
                  maxLines: 6,
                ),
                _editableField(
                  context,
                  'System Prompt',
                  state.systemPromptController,
                  maxLines: 4,
                ),
                ReviewLorebookSection(state: state),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _editableField(
    BuildContext context,
    String label,
    TextEditingController controller, {
    int maxLines = 3,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              color: _accent(context),
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          AppTextField(
            controller: controller,
            maxLines: maxLines,
            style: TextStyle(
              color: AppColors.textPrimary(context),
              fontSize: 13,
              height: 1.5,
            ),
            decoration: InputDecoration(
              filled: true,
              fillColor: AppColors.surfaceContainerOf(context),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(
                  color: AppColors.borderOf(context).withValues(alpha: 0.2),
                ),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(
                  color: AppColors.borderOf(context).withValues(alpha: 0.2),
                ),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: _accent(context)),
              ),
              contentPadding: const EdgeInsets.all(14),
            ),
          ),
        ],
      ),
    );
  }
}
