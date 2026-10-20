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

import 'package:front_porch_ai/ui/theme/theme.dart';
import 'package:front_porch_ai/ui/widgets/widgets.dart';
import 'package:front_porch_ai/ui/widgets/group_alternate_greetings_editor.dart';

import 'create_group_chat_page.dart';

/// "Generate with Dynamics" button shared by the Opening and Review steps.
Widget generateWithDynamicsButton(
  BuildContext context, {
  required bool busy,
  required Future<void> Function() onPressed,
}) {
  return TextButton.icon(
    onPressed: onPressed,
    icon: busy
        ? const SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        : Icon(Icons.auto_awesome, color: AccentColors.amberOf(context)),
    label: Text(busy ? 'Generating...' : 'Generate with Dynamics'),
  );
}

/// Director Mode hint under the first-message field.
Widget directorOpeningNote(BuildContext context) {
  return Container(
    padding: const EdgeInsets.all(10),
    decoration: BoxDecoration(
      color: AccentColors.amberWash,
      borderRadius: BorderRadius.circular(8),
    ),
    child: Text(
      'Director Mode: generated opening will be a self-contained group scene.',
      style: TextStyle(fontSize: 13, color: AccentColors.amberOf(context)),
    ),
  );
}

class GroupOpeningStep extends StatelessWidget {
  const GroupOpeningStep({
    super.key,
    required this.draft,
    required this.actions,
  });

  final GroupWizardDraft draft;
  final GroupWizardActions actions;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Opening Scene',
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),

        // Dialogue subsection (groups): first message + alternate greetings.
        // Completely omits Example Dialogue (CharacterCard / mes_example concept only; no such field on GroupChat).
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.cardOf(context),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.borderOf(context)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.chat_bubble_outline,
                    color: AppColors.porchAmberOf(context),
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Dialogue',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: AppColors.porchAmberOf(context),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              Row(
                children: [
                  Expanded(
                    child: Text(
                      'First Message (optional)',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary(context),
                      ),
                    ),
                  ),
                  generateWithDynamicsButton(
                    context,
                    busy: draft.isGeneratingFirst,
                    onPressed: () async {
                      final dynamics = draft
                          .buildDynamicsContextForGeneration();
                      await actions.generateFirstMessage(
                        dynamicsContext: dynamics,
                      );
                    },
                  ),
                ],
              ),
              const SizedBox(height: 6),
              AppTextField(
                controller: draft.firstMessageController,
                maxLines: 8,
                decoration: const InputDecoration(
                  hintText: 'The scene opens with...',
                ),
              ),
              const SizedBox(height: 8),
              if (draft.directorMode) directorOpeningNote(context),

              const SizedBox(height: 20),
              GroupAlternateGreetingsEditor(
                greetings: draft.altGreetings,
                seeds: draft.altGreetingSeeds,
                showNeeds: true,
                onChanged: (g, s) {
                  draft.update(() {
                    draft.altGreetings = g;
                    draft.altGreetingSeeds = s;
                  });
                },
              ),
            ],
          ),
        ),

        const SizedBox(height: 20),

        Row(
          children: [
            Expanded(
              child: Text(
                'Scenario (optional)',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary(context),
                ),
              ),
            ),
            generateWithDynamicsButton(
              context,
              busy: draft.isGeneratingScenario,
              onPressed: () async {
                final dynamics = draft.buildDynamicsContextForGeneration();
                await actions.generateScenario(dynamicsContext: dynamics);
              },
            ),
          ],
        ),
        const SizedBox(height: 8),
        AppTextField(
          controller: draft.scenarioController,
          maxLines: 3,
          decoration: const InputDecoration(hintText: 'The group is...'),
        ),

        GroupWizardNavButtons(draft: draft, actions: actions, currentStep: 6),
      ],
    );
  }
}

class GroupPromptsStep extends StatelessWidget {
  const GroupPromptsStep({
    super.key,
    required this.draft,
    required this.actions,
  });

  final GroupWizardDraft draft;
  final GroupWizardActions actions;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // "Personality & World" subsection for groups (per spec): only group-applicable fields.
        // Omits Description/Personality (CharacterCard-only concepts). Scenario lives in Opening.
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.cardOf(context),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.borderOf(context)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.psychology_outlined,
                    color: AppColors.porchAmberOf(context),
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Personality & World',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: AppColors.porchAmberOf(context),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'Group-level equivalents to character personality live in the system prompt and scenario.',
                style: TextStyle(
                  fontSize: 13,
                  color: AppColors.textSecondary(context),
                  fontStyle: FontStyle.italic,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Group System Prompt',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary(context),
                ),
              ),
              const SizedBox(height: 6),
              AppTextField(
                controller: draft.groupSystemController,
                maxLines: 6,
                decoration: const InputDecoration(
                  hintText: 'Global instructions for this group...',
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),

        Text(
          'Per-Character Overrides (optional)',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        ...draft.members.map((c) {
          final id = draft.stableId(c);
          final ctrl = StyledTextController(
            preset: StyledTextPreset.prose,
            text: draft.characterSystemPrompts[id]?.text ?? '',
          );
          ctrl.addListener(() {
            draft.characterSystemPrompts[id] = ctrl;
          });
          return Card(
            margin: const EdgeInsets.only(bottom: 10),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      groupMemberAvatar(context, c, radius: 16),
                      const SizedBox(width: 8),
                      Text(
                        c.name,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  AppTextField(
                    controller: ctrl,
                    maxLines: 2,
                    decoration: const InputDecoration(
                      hintText:
                          'Extra instructions only for this character in this group',
                    ),
                  ),
                ],
              ),
            ),
          );
        }),
        if (draft.members.isEmpty)
          const Text('Add members first to configure per-character prompts.'),

        GroupWizardNavButtons(draft: draft, actions: actions, currentStep: 2),
      ],
    );
  }
}
