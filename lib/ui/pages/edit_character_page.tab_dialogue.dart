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
//
// The character editor's Dialogue tab.

part of 'edit_character_page.dart';

extension _EditCharacterDialogueTab on _EditCharacterPageState {
  Widget _buildDialogueTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── First Message ──
              _sectionCard(
                icon: Icons.chat_bubble_outline,
                title: 'First Message',
                color: AppColors.formMasterAccent,
                children: [
                  _styledField(
                    controller: _firstMessageController,
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
              _sectionCard(
                icon: Icons.swap_horiz,
                title: 'Alternate Greetings',
                color: AppColors.porchHoneyOf(context),
                trailing: TextButton.icon(
                  onPressed: () {
                    rebuildState(() {
                      final c = StyledTextController(
                        preset: StyledTextPreset.prose,
                      );
                      c.addListener(_updateTokenCount);
                      _altGreetingControllers.add(c);
                      _altGreetingSeeds.add(null);
                    });
                  },
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text('Add'),
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.formMasterAccent,
                  ),
                ),
                children: [
                  if (_altGreetingControllers.isEmpty)
                    Container(
                      padding: const EdgeInsets.all(24),
                      child: Center(
                        child: Text(
                          'No alternate greetings yet',
                          style: TextStyle(
                            color: AppColors.resolve(
                              context,
                              Colors.white.withValues(alpha: 0.25),
                              Colors.black.withValues(alpha: 0.25),
                            ),
                            fontSize: 13,
                          ),
                        ),
                      ),
                    )
                  else
                    ..._altGreetingControllers.asMap().entries.map((entry) {
                      final idx = entry.key;
                      final ctrl = entry.value;
                      return Padding(
                        padding: EdgeInsets.only(
                          bottom: idx < _altGreetingControllers.length - 1
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
                                  child: _styledField(
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
                                      rebuildState(() {
                                        _altGreetingControllers[idx].dispose();
                                        _altGreetingControllers.removeAt(idx);
                                        if (idx < _altGreetingSeeds.length) {
                                          _altGreetingSeeds.removeAt(idx);
                                        }
                                      });
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
                              seed: idx < _altGreetingSeeds.length
                                  ? _altGreetingSeeds[idx]
                                  : null,
                              showNeeds: true,
                              showInventory: true,
                              onChanged: (next) {
                                rebuildState(() {
                                  while (_altGreetingSeeds.length <= idx) {
                                    _altGreetingSeeds.add(null);
                                  }
                                  _altGreetingSeeds[idx] = next;
                                });
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
              _sectionCard(
                icon: Icons.format_quote_outlined,
                title: 'Example Dialogue',
                color: AppColors.porchTerracottaOf(context),
                children: [
                  _styledField(
                    controller: _mesExampleController,
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
