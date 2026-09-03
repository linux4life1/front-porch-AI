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
// Manual creator steps 1-3: Identity, Personality, Dialogue.
// Extracted verbatim from create_character_page.dart (god-file campaign,
// Tranche A); `part of` the same library, so privates and the mandatory
// step-indicator wizard flow are unchanged.

part of 'create_character_page.dart';

extension _CreateCharacterCoreSteps on _CreateCharacterPageState {
  Widget _buildIdentityStep() {
    return Center(
      key: const ValueKey('identity'),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 700),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Character Identity',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary(context),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Set your character\'s name and tags. Portrait and avatars '
                'come in the final step, after your writing is safely saved.',
                style: TextStyle(
                  fontSize: 14,
                  color: AppColors.textSecondary(context),
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 32),

              // Name field
              _inputLabel('Character Name', required: true),
              const SizedBox(height: 8),
              TextFormField(
                controller: _nameController,
                style: TextStyle(
                  color: AppColors.textPrimary(context),
                  fontSize: 16,
                ),
                decoration: _inputDecoration('Enter character name'),
              ),
              const SizedBox(height: 24),

              // Tags
              _inputLabel('Tags', required: false),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  ..._tags.map(
                    (tag) => Chip(
                      label: Text(
                        tag,
                        style: TextStyle(
                          color: AppColors.textPrimary(context),
                          fontSize: 12,
                        ),
                      ),
                      backgroundColor: AppColors.surfaceContainerOf(context),
                      side: BorderSide.none,
                      deleteIcon: Icon(
                        Icons.close,
                        size: 14,
                        color: AppColors.iconSecondary(context),
                      ),
                      onDeleted: () => rebuildState(() => _tags.remove(tag)),
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _tagController,
                      style: TextStyle(
                        color: AppColors.textPrimary(context),
                        fontSize: 14,
                      ),
                      decoration: _inputDecoration('Add a tag...'),
                      onSubmitted: _addTag,
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    onPressed: () => _addTag(_tagController.text),
                    icon: const Icon(
                      Icons.add_circle,
                      color: AppColors.formMasterAccent,
                    ),
                    tooltip: 'Add tag',
                  ),
                ],
              ),

              _buildNavButtons(currentStep: 0),
            ],
          ),
        ),
      ),
    );
  }

  void _addTag(String value) {
    final tag = value.trim();
    if (tag.isNotEmpty && !_tags.contains(tag)) {
      rebuildState(() => _tags.add(tag));
      _tagController.clear();
    }
  }

  // ═══════════════════════════════════════════════════════════════
  //  STEP 1: PERSONALITY
  // ═══════════════════════════════════════════════════════════════

  Widget _buildPersonalityStep() {
    return Center(
      key: const ValueKey('personality'),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 700),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Personality & World',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary(context),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Define who your character is and the world they inhabit.',
                style: TextStyle(
                  fontSize: 14,
                  color: AppColors.textSecondary(context),
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 32),

              _expandableField(
                'Description',
                _descriptionController,
                hint: 'Physical appearance, backstory, key traits...',
                maxLines: 4,
              ),
              const SizedBox(height: 20),

              _expandableField(
                'Personality',
                _personalityController,
                hint: 'How they act, speak, think...',
                maxLines: 3,
              ),
              const SizedBox(height: 20),

              _expandableField(
                'Scenario',
                _scenarioController,
                hint: 'The setting, situation, or context...',
                maxLines: 3,
              ),
              const SizedBox(height: 24),

              // Advanced Prompts (collapsed)
              Theme(
                data: Theme.of(
                  context,
                ).copyWith(dividerColor: Colors.transparent),
                child: ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  title: Row(
                    children: [
                      Icon(
                        Icons.settings_suggest,
                        size: 18,
                        color: AppColors.iconSecondary(context),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Advanced Prompts (optional)',
                        style: TextStyle(
                          color: AppColors.textSecondary(context),
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                  children: [
                    const SizedBox(height: 8),
                    _expandableField(
                      'System Prompt',
                      _systemPromptController,
                      hint:
                          'Instructions for the AI about how to play this character...',
                      maxLines: 4,
                    ),
                    const SizedBox(height: 16),
                    _expandableField(
                      'Post-History Instructions',
                      _postHistoryController,
                      hint:
                          'Injected after chat history, before AI response...',
                      maxLines: 3,
                    ),
                  ],
                ),
              ),

              _buildNavButtons(currentStep: 1),
            ],
          ),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  //  STEP 2: DIALOGUE
  // ═══════════════════════════════════════════════════════════════

  Widget _buildDialogueStep() {
    return Center(
      key: const ValueKey('dialogue'),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 700),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Dialogue & Greetings',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary(context),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Configure the character\'s opening message and example dialogue.',
                style: TextStyle(
                  fontSize: 14,
                  color: AppColors.textSecondary(context),
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 32),

              _expandableField(
                'First Message',
                _firstMessageController,
                hint:
                    'The character\'s opening message when a conversation starts...',
                maxLines: 6,
              ),
              const SizedBox(height: 24),

              // Alternate Greetings
              Row(
                children: [
                  _inputLabel('Alternate Greetings', required: false),
                  const Spacer(),
                  TextButton.icon(
                    onPressed: () {
                      rebuildState(() {
                        final ctrl = StyledTextController(
                          preset: StyledTextPreset.prose,
                        );
                        ctrl.addListener(_updateTokenEstimate);
                        _altGreetingControllers.add(ctrl);
                        _altGreetingSeeds.add(null);
                      });
                    },
                    icon: const Icon(Icons.add, size: 16),
                    label: const Text('Add Greeting'),
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.formMasterAccent,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              ..._altGreetingControllers.asMap().entries.map((entry) {
                final idx = entry.key;
                final ctrl = entry.value;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: _expandableField(
                              'Greeting ${idx + 1}',
                              ctrl,
                              hint: 'Alternative opening message...',
                              maxLines: 4,
                            ),
                          ),
                          const SizedBox(width: 8),
                          IconButton(
                            onPressed: () {
                              rebuildState(() {
                                _altGreetingControllers[idx].dispose();
                                _altGreetingControllers.removeAt(idx);
                                if (idx < _altGreetingSeeds.length) {
                                  _altGreetingSeeds.removeAt(idx);
                                }
                              });
                            },
                            icon: const Icon(
                              Icons.remove_circle_outline,
                              color: Colors.redAccent,
                              size: 20,
                            ),
                            tooltip: 'Remove greeting',
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
              const SizedBox(height: 20),

              _expandableField(
                'Example Dialogue',
                _exampleDialogueController,
                hint: '<START>\n{{user}}: Hello!\n{{char}}: *smiles warmly*',
                maxLines: 6,
              ),

              _buildNavButtons(currentStep: 2),
            ],
          ),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  //  STEP 3: LOREBOOK
  // ═══════════════════════════════════════════════════════════════
}
