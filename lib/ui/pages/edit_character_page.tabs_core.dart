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
// The character editor's Details and Dialogue tabs.
// Extracted verbatim from edit_character_page.dart (god-file campaign,
// Tranche A); `part of` the same library — privates stay in scope.

part of 'edit_character_page.dart';

extension _EditCharacterCoreTabs on _EditCharacterPageState {
  Widget _buildDetailsTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Avatar (read-only). Portrait + expression images are managed
              //    in the Avatar Gallery (right-click a character on the home
              //    grid, or the chat sidebar) — no destructive change here.
              //    Display uses coverImageFileFor (★-aware), not raw imagePath.
              Builder(
                builder: (context) {
                  final cover = _avatarFile;
                  return Center(
                    child: Container(
                      width: 160,
                      height: 160,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(20),
                        color: AppColors.cardOf(context),
                        border: Border.all(
                          color: AppColors.borderOf(
                            context,
                          ).withValues(alpha: 0.45),
                        ),
                        image: cover != null
                            ? DecorationImage(
                                image: FileImage(cover),
                                fit: BoxFit.cover,
                              )
                            : null,
                      ),
                      child: cover == null
                          ? Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.person,
                                  size: 56,
                                  color: AppColors.resolve(
                                    context,
                                    Colors.white.withValues(alpha: 0.15),
                                    Colors.black.withValues(alpha: 0.15),
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'No avatar',
                                  style: TextStyle(
                                    color: AppColors.textTertiary(context),
                                    fontSize: 11,
                                  ),
                                ),
                              ],
                            )
                          : null,
                    ),
                  );
                },
              ),
              const SizedBox(height: 20),

              // ── Identity Section ──
              _sectionCard(
                icon: Icons.badge_outlined,
                title: 'Identity',
                color: AppColors.formMasterAccent,
                children: [
                  _styledField(controller: _nameController, label: 'Name'),
                  const SizedBox(height: 16),
                  // Tags
                  _fieldLabel('Tags'),
                  const SizedBox(height: 8),
                  if (_tags.isNotEmpty)
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: _tags
                          .map(
                            (tag) => Chip(
                              label: Text(
                                tag,
                                style: TextStyle(
                                  color: AppColors.textSecondary(context),
                                  fontSize: 12,
                                ),
                              ),
                              backgroundColor: AppColors.surfaceContainerOf(
                                context,
                              ),
                              side: BorderSide.none,
                              deleteIcon: Icon(
                                Icons.close,
                                size: 14,
                                color: AppColors.textTertiary(context),
                              ),
                              onDeleted: () =>
                                  rebuildState(() => _tags.remove(tag)),
                              visualDensity: VisualDensity.compact,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                          )
                          .toList(),
                    ),
                  if (_tags.isNotEmpty) const SizedBox(height: 8),
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
                          onSubmitted: (value) {
                            final trimmed = value.trim().toLowerCase();
                            if (trimmed.isNotEmpty &&
                                !_tags.contains(trimmed)) {
                              rebuildState(() {
                                _tags.add(trimmed);
                                _tagController.clear();
                              });
                            }
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        icon: const Icon(
                          Icons.add_circle,
                          color: AppColors.formMasterAccent,
                        ),
                        tooltip: 'Add tag',
                        onPressed: () {
                          final trimmed = _tagController.text
                              .trim()
                              .toLowerCase();
                          if (trimmed.isNotEmpty && !_tags.contains(trimmed)) {
                            rebuildState(() {
                              _tags.add(trimmed);
                              _tagController.clear();
                            });
                          }
                        },
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // ── Voice ──
              // A character voice OVERRIDES the global Settings voice, and
              // one can arrive without the user picking it (an imported card
              // carries `tts_voice`). It was invisible here until 2026-08-14,
              // which is how "I picked Adam and she still sounds female"
              // happened with nothing to click.
              _sectionCard(
                icon: Icons.record_voice_over_outlined,
                title: 'Voice',
                color: AppColors.porchAmberOf(context),
                children: [
                  _fieldLabel('Text-to-speech voice'),
                  const SizedBox(height: 8),
                  CharacterVoicePicker(
                    value: _ttsVoice,
                    onChanged: (v) => rebuildState(() => _ttsVoice = v),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _ttsVoice.isEmpty
                        ? 'Following the voice set in Settings → '
                              'Text-to-Speech. Pick one here to give '
                              '${_nameController.text.trim().isEmpty ? 'this character' : _nameController.text.trim()} '
                              'their own voice instead.'
                        : 'This character speaks in their own voice — the '
                              'Settings voice does not apply to them. Choose '
                              '"Use the global voice" to follow Settings again.',
                    style: TextStyle(
                      color: AppColors.textTertiary(context),
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // ── Personality & World ──
              _sectionCard(
                icon: Icons.psychology_outlined,
                title: 'Personality & World',
                color: AppColors.porchHoneyOf(context),
                children: [
                  _styledField(
                    controller: _descriptionController,
                    label: 'Description',
                    maxLines: 4,
                    expandable: true,
                    hint: 'Physical appearance, backstory, key traits...',
                  ),
                  const SizedBox(height: 16),
                  _styledField(
                    controller: _personalityController,
                    label: 'Personality',
                    maxLines: 3,
                    expandable: true,
                    hint: 'How they act, speak, think...',
                  ),
                  const SizedBox(height: 16),
                  _styledField(
                    controller: _scenarioController,
                    label: 'Scenario',
                    maxLines: 3,
                    expandable: true,
                    hint: 'The setting, situation, or context...',
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // ── Advanced Prompts ──
              _sectionCard(
                icon: Icons.settings_suggest_outlined,
                title: 'Advanced Prompts',
                color: AppColors.textTertiary(context),
                collapsed: true,
                children: [
                  _styledField(
                    controller: _systemPromptController,
                    label: 'System Prompt',
                    maxLines: 4,
                    expandable: true,
                    hint: 'Custom system prompt for this character...',
                  ),
                  const SizedBox(height: 16),
                  _styledField(
                    controller: _postHistoryController,
                    label: 'Post-History Instructions',
                    maxLines: 3,
                    expandable: true,
                    hint: 'Injected after chat history (jailbreak/reminder)...',
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // ── The card-authored identity lists (Living Time §6 +
              //    Likes & Dislikes) ──
              // Chips, not newline-encoded TextFields: this is who the
              // character IS, and the approved sketch gives it one phrase per
              // chip. See ChipListEditor for why the old shape misled authors.
              // One shared widget (identity_chip_lists.dart) so the editor,
              // both creators and the web form cannot drift apart.
              // Gated on the same flag as the SAVE below, and that is the whole
              // point of the condition. These chips used to render
              // unconditionally while `_saveCharacter` wrote them only under
              // `showRealismTab` (edit_character_page.dart), so opening a group
              // MEMBER from Group Settings gave you fully editable Ambitions,
              // Likes and Dislikes that were thrown away the moment you pressed
              // Save — no error, no hint, the chips simply gone on reopen. A
              // member's extensions are group state and are deliberately left
              // untouched there; showing an editor for them was the bug.
              if (widget.showRealismTab)
                IdentityChipLists(
                  ambitions: _ambitions,
                  onAmbitionsChanged: (v) =>
                      rebuildState(() => _ambitions = v),
                  planLines: _planLines,
                  onPlanLinesChanged: (v) =>
                      rebuildState(() => _planLines = v),
                  occupation: _occupation,
                  onOccupationChanged: (v) =>
                      rebuildState(() => _occupation = v),
                  hours: _hours,
                  onHoursChanged: (v) =>
                      rebuildState(() => _hours = v),
                  likes: _likes,
                  onLikesChanged: (v) => rebuildState(() => _likes = v),
                  dislikes: _dislikes,
                  onDislikesChanged: (v) => rebuildState(() => _dislikes = v),
                  intimateInto: _intimateInto,
                  onIntimateIntoChanged: (v) =>
                      rebuildState(() => _intimateInto = v),
                  intimateNotInto: _intimateNotInto,
                  onIntimateNotIntoChanged: (v) =>
                      rebuildState(() => _intimateNotInto = v),
                  // The install's 18+ master switch — the same one that shows
                  // or hides the After Dark group in Settings.
                  showIntimate: adultThemesEnabledOf(context),
                  worn: _worn,
                  onWornChanged: (v) => rebuildState(() => _worn = v),
                  carrying: _carrying,
                  onCarryingChanged: (v) => rebuildState(() => _carrying = v),
                ),

              // ── Realism Engine Summary ── (hidden for group members, whose
              // realism/needs are group state edited in Group Settings)
              if (widget.showRealismTab) _buildRealismSection(),

              const SizedBox(height: 80), // Space for token badge
            ],
          ),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  //  TAB 2: DIALOGUE
  // ═══════════════════════════════════════════════════════════════

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
                        child: Row(
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
                                  });
                                },
                                icon: Icon(
                                  Icons.remove_circle_outline,
                                  color: AppColors.negativeAccentOf(context),
                                  size: 20,
                                ),
                                tooltip: 'Remove greeting',
                              ),
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

  // ═══════════════════════════════════════════════════════════════
  //  TAB 3: LOREBOOK
  // ═══════════════════════════════════════════════════════════════
}
