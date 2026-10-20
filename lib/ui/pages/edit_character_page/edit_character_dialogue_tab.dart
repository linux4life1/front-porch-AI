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
import 'package:front_porch_ai/ui/pages/edit_character_page/edit_character_draft.dart';
import 'package:front_porch_ai/ui/pages/edit_character_page/edit_character_form_kit.dart';
import 'package:front_porch_ai/ui/theme/theme.dart';
import 'package:front_porch_ai/ui/widgets/greeting_seed_form.dart';

/// The character editor's Dialogue tab: first message, alternate greetings
/// (each with its realism seed) and example dialogue.
class EditCharacterDialogueTab extends StatelessWidget {
  final EditCharacterDraft draft;
  final VoidCallback onChanged;

  const EditCharacterDialogueTab({
    super.key,
    required this.draft,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final d = draft;
    final kit = EditCharacterFormKit(context);
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── First Message ──
              kit.sectionCard(
                icon: Icons.chat_bubble_outline,
                title: 'First Message',
                color: AppColors.formAccentOf(context),
                children: [
                  kit.styledField(
                    controller: d.firstMessageController,
                    label: 'Opening Message',
                    maxLines: 6,
                    expandable: true,
                    hint:
                        'The character\'s opening line when a conversation starts...',
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // ── Alternate Greetings ──
              kit.sectionCard(
                icon: Icons.swap_horiz,
                title: 'Alternate Greetings',
                color: AppColors.porchHoneyOf(context),
                trailing: TextButton.icon(
                  onPressed: () {
                    d.addAltGreeting();
                    onChanged();
                  },
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text('Add'),
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.formAccentOf(context),
                  ),
                ),
                children: [
                  if (d.altGreetingControllers.isEmpty)
                    Container(
                      padding: const EdgeInsets.all(24),
                      child: Center(
                        child: Text(
                          'No alternate greetings yet',
                          style: TextStyle(
                            color: InkColors.washOf(context, 0.25, 0.25),
                            fontSize: 13,
                          ),
                        ),
                      ),
                    )
                  else
                    ...d.altGreetingControllers.asMap().entries.map((entry) {
                      final idx = entry.key;
                      final ctrl = entry.value;
                      return Padding(
                        padding: EdgeInsets.only(
                          bottom: idx < d.altGreetingControllers.length - 1
                              ? 12
                              : 0,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: kit.styledField(
                                    controller: ctrl,
                                    label: 'Greeting ${idx + 2}',
                                    maxLines: 4,
                                    expandable: true,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Padding(
                                  padding: const EdgeInsets.only(top: 26),
                                  child: IconButton(
                                    onPressed: () {
                                      d.removeAltGreeting(idx);
                                      onChanged();
                                    },
                                    icon: Icon(
                                      Icons.remove_circle_outline,
                                      color: AppColors.negativeAccentOf(
                                        context,
                                      ),
                                      size: 20,
                                    ),
                                    tooltip: 'Remove greeting',
                                  ),
                                ),
                              ],
                            ),
                            GreetingSeedForm(
                              seed: idx < d.altGreetingSeeds.length
                                  ? d.altGreetingSeeds[idx]
                                  : null,
                              showNeeds: true,
                              showInventory: true,
                              onChanged: (next) {
                                d.setAltGreetingSeed(idx, next);
                                onChanged();
                              },
                            ),
                          ],
                        ),
                      );
                    }),
                ],
              ),
              const SizedBox(height: 20),

              // ── Example Dialogue ──
              kit.sectionCard(
                icon: Icons.format_quote_outlined,
                title: 'Example Dialogue',
                color: AppColors.porchTerracottaOf(context),
                children: [
                  kit.styledField(
                    controller: d.mesExampleController,
                    label: 'Example Conversations',
                    maxLines: 6,
                    expandable: true,
                    hint:
                        '<START>\n{{user}}: Hello!\n{{char}}: *smiles warmly*',
                  ),
                ],
              ),

              const SizedBox(height: 80), // Space for token badge
            ],
          ),
        ),
      ),
    );
  }
}
