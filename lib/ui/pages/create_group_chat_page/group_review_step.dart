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
import 'package:front_porch_ai/ui/widgets/widgets.dart';

import 'create_group_chat_page.dart';

class GroupReviewStep extends StatelessWidget {
  const GroupReviewStep({
    super.key,
    required this.draft,
    required this.actions,
  });

  final GroupWizardDraft draft;
  final GroupWizardActions actions;

  @override
  Widget build(BuildContext context) {
    final d = draft;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Review & Opening',
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),

        // Scenario + First Message moved here (last step) so AI generation
        // can use the hidden relationships from the Group Dynamics step.
        Row(
          children: [
            Expanded(
              child: Text(
                'Scenario (optional)',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
            ),
            generateWithDynamicsButton(
              context,
              busy: d.isGeneratingScenario,
              onPressed: () async {
                final dynamics = d.buildDynamicsContextForGeneration();
                await actions.generateScenario(dynamicsContext: dynamics);
              },
            ),
          ],
        ),
        const SizedBox(height: 8),
        AppTextField(
          controller: d.scenarioController,
          maxLines: 3,
          decoration: const InputDecoration(hintText: 'The group is...'),
        ),
        const SizedBox(height: 20),

        Row(
          children: [
            Expanded(
              child: Text(
                'First Message (optional)',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
            ),
            generateWithDynamicsButton(
              context,
              busy: d.isGeneratingFirst,
              onPressed: () async {
                final dynamics = d.buildDynamicsContextForGeneration();
                await actions.generateFirstMessage(dynamicsContext: dynamics);
              },
            ),
          ],
        ),
        const SizedBox(height: 8),
        AppTextField(
          controller: d.firstMessageController,
          maxLines: 8,
          decoration: const InputDecoration(
            hintText: 'The scene opens with...',
          ),
        ),
        const SizedBox(height: 8),
        if (d.directorMode) directorOpeningNote(context),

        const SizedBox(height: 24),

        // Single group summary
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.cardOf(context),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                d.nameController.text.isEmpty
                    ? 'Unnamed Group'
                    : d.nameController.text,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                children: d.members
                    .map((c) => Chip(label: Text(c.name)))
                    .toList(),
              ),
              const SizedBox(height: 12),
              Text(
                '${d.members.length} members • ${d.groupLoreEntries.length} lore entries • ${d.worldIds.length} worlds',
              ),
              if (d.chaosModeEnabled)
                Text(
                  'Chaos Mode enabled',
                  style: TextStyle(
                    color: AppColors.resolve(
                      context,
                      const Color(0xFFFFD166),
                      const Color(0xFFB45309),
                    ),
                  ),
                ),
              if (d.directorMode)
                Text(
                  'Director Mode',
                  style: TextStyle(
                    color: AppColors.resolve(
                      context,
                      Colors.amberAccent,
                      Colors.amber.shade700,
                    ),
                  ),
                ),
              Text(
                d.realismEnabled
                    ? 'Realism Engine: Enabled for group'
                    : 'Realism Engine: Disabled for group',
                style: TextStyle(
                  color: d.realismEnabled
                      ? AppColors.resolve(
                          context,
                          Colors.tealAccent,
                          Colors.teal.shade700,
                        )
                      : AppColors.textSecondary(context),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),

        ElevatedButton.icon(
          onPressed: () => actions.createGroup(enterChat: true),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.porchAmberOf(context),
            foregroundColor: AppColors.onAccentOf(context),
            minimumSize: const Size.fromHeight(52),
          ),
          icon: const Icon(Icons.check),
          label: const Text(
            'Create Group & Enter Chat',
            style: TextStyle(fontSize: 16),
          ),
        ),
        const SizedBox(height: 8),
        OutlinedButton(
          onPressed: () => actions.createGroup(enterChat: false),
          style: OutlinedButton.styleFrom(
            minimumSize: const Size.fromHeight(44),
          ),
          child: const Text('Create Only (don\'t enter chat yet)'),
        ),
      ],
    );
  }
}
