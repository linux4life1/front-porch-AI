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
import 'package:front_porch_ai/ui/theme/app_colors.dart';
import 'package:front_porch_ai/ui/widgets/greeting_seed_form.dart';

import 'create_character_draft.dart';
import 'creator_form_fields.dart';
import 'creator_review_summary.dart';

/// Step 5: Review & Create. The card is SAVED when [onCreate] succeeds.
class CreatorReviewStep extends StatelessWidget {
  const CreatorReviewStep({
    super.key,
    required this.draft,
    required this.onChanged,
    required this.onCreate,
    required this.onBackToEdit,
  });

  final CreateCharacterDraft draft;
  final VoidCallback onChanged;
  final VoidCallback onCreate;
  final VoidCallback onBackToEdit;

  @override
  Widget build(BuildContext context) {
    final d = draft;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(32),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CreatorReviewSummary(
            draft: d,
            onCreate: onCreate,
            onBackToEdit: onBackToEdit,
          ),
          const SizedBox(width: 32),

          // Right column — editable fields review
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
                  'Review your character card. All fields are still editable before saving.',
                  style: TextStyle(
                    color: AppColors.textTertiary(context),
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 24),
                CreatorReviewField(
                  'Description',
                  d.descriptionController,
                  maxLines: 4,
                ),
                CreatorReviewField(
                  'Personality',
                  d.personalityController,
                  maxLines: 3,
                ),
                CreatorReviewField(
                  'Scenario',
                  d.scenarioController,
                  maxLines: 3,
                ),
                CreatorReviewField(
                  'First Message',
                  d.firstMessageController,
                  maxLines: 5,
                ),
                if (d.exampleDialogueController.text.isNotEmpty)
                  CreatorReviewField(
                    'Example Dialogue',
                    d.exampleDialogueController,
                    maxLines: 4,
                  ),
                if (d.systemPromptController.text.isNotEmpty)
                  CreatorReviewField(
                    'System Prompt',
                    d.systemPromptController,
                    maxLines: 3,
                  ),
                if (d.postHistoryController.text.isNotEmpty)
                  CreatorReviewField(
                    'Post-History Instructions',
                    d.postHistoryController,
                    maxLines: 3,
                  ),

                // Alt greetings
                ...d.altGreetingControllers.asMap().entries.map((entry) {
                  final idx = entry.key;
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      CreatorReviewField(
                        'Alt Greeting ${idx + 1}',
                        entry.value,
                        maxLines: 3,
                      ),
                      GreetingSeedForm(
                        seed: d.altGreetingSeedAt(idx),
                        showNeeds: true,
                        showInventory: true,
                        onChanged: (next) {
                          d.setAltGreetingSeed(idx, next);
                          onChanged();
                        },
                      ),
                    ],
                  );
                }),

                // Lorebook
                if (d.lorebookEntries.isNotEmpty) ...[
                  Divider(color: AppColors.borderOf(context), height: 32),
                  Row(
                    children: [
                      Icon(
                        Icons.menu_book,
                        color: AppColors.formAccentOf(context),
                        size: 18,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Lorebook Entries',
                        style: TextStyle(
                          color: AppColors.formAccentOf(context),
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        '${d.lorebookEntries.length} entries',
                        style: TextStyle(
                          color: AppColors.textTertiary(context),
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  ...d.lorebookEntries.map(
                    (entry) => Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.cardOf(context),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: AppColors.formAccentOf(
                            context,
                          ).withValues(alpha: 0.2),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            entry.displayName,
                            style: TextStyle(
                              color: AppColors.textPrimary(context),
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          if (entry.key.isNotEmpty) ...[
                            const SizedBox(height: 2),
                            Text(
                              'Keys: ${entry.key}',
                              style: TextStyle(
                                color: AppColors.formAccentOf(context),
                                fontSize: 11,
                              ),
                            ),
                          ],
                          if (entry.content.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Text(
                              entry.content,
                              style: TextStyle(
                                color: AppColors.textSecondary(context),
                                fontSize: 12,
                                height: 1.4,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
