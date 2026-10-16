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

import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/avatar_creation/avatar_generation_panel.dart';
import 'package:front_porch_ai/ui/character_creator/character_creator.dart';
import 'package:front_porch_ai/ui/character_creator/widgets/widgets.dart';
import 'package:front_porch_ai/ui/widgets/greeting_seed_form.dart';
import 'package:front_porch_ai/ui/theme/studio_colors.dart';

/// Review & edit step: the shared Portrait & Avatars panel in the left rail
/// (phase #12 — it replaced the bespoke avatar generation controls) + editable
/// card fields + lorebook cherry-pick. The wizard shell owns Save & Finish /
/// reset / nav. The panel saves the card FIRST when the user generates or
/// uploads (Save & Finish then updates the same card in place), so a failed
/// engine can never cost the generated writing.
class ReviewStep extends StatelessWidget {
  final CreatorState state;

  const ReviewStep({super.key, required this.state});

  Color _accent(BuildContext context) => StudioColors.amberOf(context);

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
              color: StudioColors.badOf(context),
            ),
            const SizedBox(height: 16),
            Text(
              'Generation failed. The LLM did not produce valid output.',
              style: TextStyle(
                color: StudioColors.proseOf(context),
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
                foregroundColor: StudioColors.amberInkOf(context),
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
                  existingPortraitPath: state.portraitSourcePath,
                ),
                const SizedBox(height: 16),
                Text(
                  card.name,
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: StudioColors.inkOf(context),
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
                                color: StudioColors.proseOf(context),
                              ),
                            ),
                            backgroundColor: StudioColors.raiseOf(context),
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
                  'Review',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                    color: StudioColors.inkOf(context),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Everything the creator wrote, in one place. The profile and '
                  'greetings are above. Example dialogue and the lorebook take '
                  'the same line of direction as the rest.',
                  style: TextStyle(
                    color: StudioColors.mutedOf(context),
                    fontSize: 14,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 16),
                // One spec card per section, 16px apart.
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  spacing: 16,
                  children: [
                    CreatorTextCard(
                      title: 'Description',
                      subtitle: 'Who they are, as the card will carry it',
                      controller: state.descController,
                      maxLines: 6,
                    ),
                    CreatorTextCard(
                      title: 'Personality',
                      subtitle: 'How they act and speak',
                      controller: state.personalityController,
                      maxLines: 4,
                    ),
                    CreatorTextCard(
                      title: 'Scenario',
                      subtitle: 'Where the first chat starts',
                      controller: state.scenarioController,
                    ),
                    CreatorTextCard(
                      title: 'First Message',
                      subtitle: 'Opens every new chat',
                      controller: state.firstMessageController,
                      maxLines: 6,
                    ),
                    for (final (idx, alt)
                        in state.altGreetingControllers.indexed)
                      CreatorTextCard(
                        title: 'Alternate greeting ${idx + 1}',
                        controller: alt,
                        maxLines: 4,
                        below: [
                          GreetingSeedForm(
                            seed: idx < state.greetingSeeds.length
                                ? state.greetingSeeds[idx]
                                : null,
                            showNeeds: true,
                            showInventory: true,
                            onChanged: (next) {
                              while (state.greetingSeeds.length <= idx) {
                                state.greetingSeeds.add(null);
                              }
                              state.greetingSeeds[idx] = next;
                              state.notify();
                            },
                          ),
                        ],
                      ),
                    _dialogueCard(context),
                    CreatorTextCard(
                      title: 'System Prompt',
                      controller: state.systemPromptController,
                      maxLines: 4,
                    ),
                    ReviewLorebookSection(state: state),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// "How {they} answer": the pronoun from the Sex field, "they" when it
  /// says nothing the creator can read.
  String _they() {
    final sex = state.sexController.text.trim().toLowerCase();
    if (RegExp(r'^(f|female|woman|girl|she)\b').hasMatch(sex)) return 'she';
    if (RegExp(r'^(m|male|man|boy|he)\b').hasMatch(sex)) return 'he';
    return 'they';
  }

  Widget _dialogueCard(BuildContext context) {
    const kind = ReviewRewrite.dialogue;
    final r = state.review;
    final writing = r.writing(kind);
    final llm = Provider.of<LLMProvider>(context, listen: false);
    return CreatorTextCard(
      key: const ValueKey('review-dialogue'),
      title: 'Example dialogue',
      subtitle: 'How ${_they()} answer, learned from the interview',
      controller: state.exampleDialogueController,
      boxKey: const ValueKey('review-dialogue-box'),
      maxLines: 6,
      writingText: writing
          ? (r.dialogueText.isEmpty
                ? state.exampleDialogueController.text
                : r.dialogueText)
          : null,
      caret: writing && r.dialogueText.isNotEmpty,
      status: writing ? 'Writing…' : null,
      statusAmber: true,
      below: [
        ReviewRewriteRow(
          id: 'review-dialogue',
          steer: r.dialogueSteer,
          hint: 'Steer it (optional), e.g. shorter lines, more bite',
          action: 'Regenerate',
          writing: writing,
          onRun: () => state.regenerateExampleDialogue(llmProvider: llm),
          onStop: () => state.stopReviewRewrite(kind),
          error: r.errorOf(kind),
        ),
      ],
    );
  }
}
