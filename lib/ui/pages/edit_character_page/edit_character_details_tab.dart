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

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/services/chat/chat.dart' show BirthdayMath;
import 'package:front_porch_ai/ui/pages/edit_character_page/edit_character_draft.dart';
import 'package:front_porch_ai/ui/pages/edit_character_page/edit_character_form_kit.dart';
import 'package:front_porch_ai/ui/pages/edit_character_page/edit_character_realism_section.dart';
import 'package:front_porch_ai/ui/pages/edit_character_page/member_group_view.dart';
import 'package:front_porch_ai/ui/theme/theme.dart';
import 'package:front_porch_ai/ui/widgets/widgets.dart';
import 'package:front_porch_ai/ui/widgets/realism_form_section/realism_form_section.dart'
    show MemberEditorNote;

/// Card face for the editor: the ★ starred gallery look when set, else the
/// library portrait — same resolution as the home grid / export cover
/// (issue #171: used to read raw `imagePath` only, so Add avatar + ★ left
/// this page stuck on "No avatar" while chat already showed the look).
///
/// Cost: once per Details rebuild via the repo's cover cache (not a chat
/// bubble hot path). Prefer this over a raw existsSync on imagePath.
/// Falls back to raw `imagePath` when CharacterRepository is not above this
/// widget (widget goldens / rare embeds that only provide StorageService).
File? editCharacterAvatarFile(BuildContext context, CharacterCard character) {
  try {
    final repo = Provider.of<CharacterRepository>(context, listen: false);
    final cover = repo.coverImageFileFor(character);
    if (cover != null) return cover;
  } on ProviderNotFoundException {
    // Fall through to imagePath.
  }
  final img = character.imagePath;
  if (img == null || img.isEmpty) return null;
  if (p.isAbsolute(img)) return File(img);
  try {
    final storage = Provider.of<StorageService>(context, listen: false);
    return File(p.join(storage.charactersDir.path, img));
  } on ProviderNotFoundException {
    return File(img);
  }
}

/// The character editor's Details tab: avatar, identity, voice, prompts,
/// the identity chip lists and the Realism section.
class EditCharacterDetailsTab extends StatelessWidget {
  final CharacterCard character;
  final EditCharacterDraft draft;
  final VoidCallback onChanged;

  /// The group this card is a member of, when it is a member's own copy.
  final String? memberOfGroup;

  /// The member's group, and where they start in its new chats.
  final MemberGroupView? memberGroup;

  /// What the group does with this member's Scenario.
  final String? scenarioNote;
  final GroupMemberStart? start;
  final ValueChanged<GroupMemberStart>? onStartChanged;

  const EditCharacterDetailsTab({
    super.key,
    required this.character,
    required this.draft,
    required this.onChanged,
    this.memberOfGroup,
    this.memberGroup,
    this.scenarioNote,
    this.start,
    this.onStartChanged,
  });

  void _edit(VoidCallback fn) {
    fn();
    onChanged();
  }

  void _addTag(String value) {
    final trimmed = value.trim().toLowerCase();
    if (trimmed.isNotEmpty && !draft.tags.contains(trimmed)) {
      _edit(() {
        draft.tags.add(trimmed);
        draft.tagController.clear();
      });
    }
  }

  /// The member's name as the editor has it now, so a rename shows at once.
  String get _memberName {
    final typed = draft.nameController.text.trim();
    return typed.isEmpty ? character.name : typed;
  }

  /// Says whose copy this is: edits stay in the group.
  Widget _memberBanner(BuildContext context, String group) {
    final name = _memberName;
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.formAccentOf(context).withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: AppColors.formAccentOf(context).withValues(alpha: 0.25),
        ),
      ),
      child: Text(
        '$name in $group. Changes apply to $name in this group; the library '
        'card and its other chats stay as they are.',
        key: const Key('group-member-editor-banner'),
        style: TextStyle(color: AppColors.textPrimary(context), fontSize: 13),
      ),
    );
  }

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
              if (memberOfGroup != null) _memberBanner(context, memberOfGroup!),
              // ── Avatar (read-only). Portrait + expression images are managed
              //    in the Avatar Gallery (right-click a character on the home
              //    grid, or the chat sidebar) — no destructive change here.
              //    Display uses coverImageFileFor (★-aware), not raw imagePath.
              Builder(
                builder: (context) {
                  final cover = editCharacterAvatarFile(context, character);
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
                                  color: InkColors.washOf(context, 0.15, 0.15),
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

              CharacterStatsSection(
                characterId: character.dbId,
                wrap: (content) => Padding(
                  padding: const EdgeInsets.only(bottom: 20),
                  child: kit.sectionCard(
                    icon: Icons.insights_outlined,
                    title: 'Your chats together',
                    color: AppColors.porchAmberOf(context),
                    children: [content],
                  ),
                ),
              ),

              // ── Identity Section ──
              kit.sectionCard(
                icon: Icons.badge_outlined,
                title: 'Identity',
                color: AppColors.formAccentOf(context),
                children: [
                  kit.styledField(controller: d.nameController, label: 'Name'),
                  const SizedBox(height: 16),
                  // Tags
                  kit.fieldLabel('Tags'),
                  const SizedBox(height: 8),
                  if (d.tags.isNotEmpty)
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: d.tags
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
                              onDeleted: () => _edit(() => d.tags.remove(tag)),
                              visualDensity: VisualDensity.compact,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                          )
                          .toList(),
                    ),
                  if (d.tags.isNotEmpty) const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: d.tagController,
                          style: TextStyle(
                            color: AppColors.textPrimary(context),
                            fontSize: 14,
                          ),
                          decoration: kit.inputDecoration('Add a tag...'),
                          onSubmitted: _addTag,
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        icon: Icon(
                          Icons.add_circle,
                          color: AppColors.formAccentOf(context),
                        ),
                        tooltip: 'Add tag',
                        onPressed: () => _addTag(d.tagController.text),
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
              kit.sectionCard(
                icon: Icons.record_voice_over_outlined,
                title: 'Voice',
                color: AppColors.porchAmberOf(context),
                children: [
                  kit.fieldLabel('Text-to-speech voice'),
                  const SizedBox(height: 8),
                  CharacterVoicePicker(
                    value: d.ttsVoice,
                    onChanged: (v) => _edit(() => d.ttsVoice = v),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    d.ttsVoice.isEmpty
                        ? 'Following the voice set in Settings → '
                              'Text-to-Speech. Pick one here to give '
                              '${d.nameController.text.trim().isEmpty ? 'this character' : d.nameController.text.trim()} '
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
              kit.sectionCard(
                icon: Icons.psychology_outlined,
                title: 'Personality & World',
                color: AppColors.porchHoneyOf(context),
                children: [
                  kit.styledField(
                    controller: d.descriptionController,
                    label: 'Description',
                    maxLines: 4,
                    expandable: true,
                    hint: 'Physical appearance, backstory, key traits...',
                  ),
                  const SizedBox(height: 16),
                  kit.styledField(
                    controller: d.personalityController,
                    label: 'Personality',
                    maxLines: 3,
                    expandable: true,
                    hint: 'How they act, speak, think...',
                  ),
                  const SizedBox(height: 16),
                  kit.styledField(
                    controller: d.scenarioController,
                    label: 'Scenario',
                    maxLines: 3,
                    expandable: true,
                    hint: 'The setting, situation, or context...',
                  ),
                  if (scenarioNote != null) ...[
                    const SizedBox(height: 8),
                    MemberEditorNote(scenarioNote!),
                  ],
                ],
              ),
              const SizedBox(height: 20),

              // ── Advanced Prompts ──
              kit.sectionCard(
                icon: Icons.settings_suggest_outlined,
                title: 'Advanced Prompts',
                color: AppColors.textTertiary(context),
                collapsed: true,
                children: [
                  kit.styledField(
                    controller: d.systemPromptController,
                    label: 'System Prompt',
                    maxLines: 4,
                    expandable: true,
                    hint: 'Custom system prompt for this character...',
                  ),
                  const SizedBox(height: 16),
                  kit.styledField(
                    controller: d.postHistoryController,
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
              IdentityChipLists(
                ambitions: d.ambitions,
                onAmbitionsChanged: (v) => _edit(() => d.ambitions = v),
                planLines: d.planLines,
                onPlanLinesChanged: (v) => _edit(() => d.planLines = v),
                occupation: d.occupation,
                onOccupationChanged: (v) => _edit(() => d.occupation = v),
                occupationBrief: d.occupationBrief,
                onOccupationBriefChanged: (v) =>
                    _edit(() => d.occupationBrief = v),
                hours: d.hours,
                onHoursChanged: (v) => _edit(() => d.hours = v),
                workDays: d.workDays,
                onWorkDaysChanged: (v) => _edit(() => d.workDays = v),
                birthday: d.birthday,
                onBirthdayChanged: (v) => _edit(() => d.birthday = v),
                birthdayAgeAsOf: BirthdayMath.ageAsOfStory(
                  d.realismStoryStartDate,
                ),
                likes: d.likes,
                onLikesChanged: (v) => _edit(() => d.likes = v),
                dislikes: d.dislikes,
                onDislikesChanged: (v) => _edit(() => d.dislikes = v),
                intimateInto: d.intimateInto,
                onIntimateIntoChanged: (v) => _edit(() => d.intimateInto = v),
                intimateNotInto: d.intimateNotInto,
                onIntimateNotIntoChanged: (v) =>
                    _edit(() => d.intimateNotInto = v),
                // The install's 18+ master switch — the same one that shows
                // or hides the After Dark group in Settings.
                showIntimate: adultThemesEnabledOf(context),
                worn: d.worn,
                onWornChanged: (v) => _edit(() => d.worn = v),
                carrying: d.carrying,
                onCarryingChanged: (v) => _edit(() => d.carrying = v),
                pocketsEnabled: d.realismPocketsEnabled,
                onPocketsEnabledChanged: (v) => _edit(() {
                  d.realismPocketsEnabled = v;
                  d.realismSettingsModified = true;
                }),
              ),

              // ── Realism Engine Summary ── (a member's own settings only, in
              // a group member's editor)
              EditCharacterRealismSection(
                draft: d,
                onChanged: onChanged,
                memberName: memberOfGroup == null ? null : _memberName,
                group: memberGroup,
                start: start,
                onStartChanged: onStartChanged,
                lite: memberOfGroup != null && character.isLite,
              ),

              const SizedBox(height: 80), // Space for token badge
            ],
          ),
        ),
      ),
    );
  }
}
