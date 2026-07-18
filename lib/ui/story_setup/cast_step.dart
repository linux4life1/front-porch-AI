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
// but WITHOUT ANY WARRANTY, without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
// GNU Affero General Public License for more details.
//
// You should have received a copy of the GNU Affero General Public License
// along with Front Porch AI. If not, see <https://www.gnu.org/licenses/>.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:front_porch_ai/services/character_repository.dart';
import 'package:front_porch_ai/services/user_persona_service.dart';
import 'package:front_porch_ai/ui/story_setup/setup_widgets.dart';
import 'package:front_porch_ai/ui/story_setup/story_setup_draft.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';

/// Wizard step: seed the story from your characters — chat-history import,
/// per-character roles, and the optional self-insert persona.
class CastStep extends StatelessWidget {
  final StorySetupDraft draft;
  final VoidCallback onChanged;

  const CastStep({super.key, required this.draft, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SetupSectionHeader(
          'Cast & Canon',
          Icons.groups,
          subtitle:
              'Optional — build the story around your characters and what '
              'actually happened in your chats',
        ),
        const SizedBox(height: 12),
        SetupToggleTile(
          title: 'Chat History Integration',
          subtitle: 'Weave past character conversations into the story',
          icon: Icons.history,
          value: draft.useChatHistory,
          onChanged: (v) {
            draft.useChatHistory = v;
            onChanged();
          },
        ),
        if (draft.useChatHistory) ...[
          const SizedBox(height: 12),
          _buildCharacterPicker(context),
          if (draft.selectedCharacterIds.isNotEmpty) ...[
            const SizedBox(height: 12),
            _buildRoleAssignment(context),
          ],
          const SizedBox(height: 12),
          _buildUserPersonaToggle(context),
        ],
      ],
    );
  }

  Widget _buildCharacterPicker(BuildContext context) {
    final charRepo = Provider.of<CharacterRepository>(context, listen: false);
    final accent = AppColors.porchHoneyOf(context);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.cardOf(context),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: accent.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Select characters whose chat history to include:',
            style: TextStyle(
              color: AppColors.textSecondary(context),
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: charRepo.characters.where((c) => c.dbId != null).map((
              char,
            ) {
              final charDbId = char.dbId!;
              final isSelected = draft.selectedCharacterIds.contains(charDbId);
              return FilterChip(
                selected: isSelected,
                label: Text(char.name),
                selectedColor: accent.withValues(alpha: 0.25),
                checkmarkColor: accent,
                labelStyle: TextStyle(
                  color: isSelected
                      ? AppColors.textPrimary(context)
                      : AppColors.textSecondary(context),
                  fontSize: 12,
                ),
                backgroundColor: AppColors.surfaceContainerOf(context),
                side: BorderSide(
                  color: isSelected
                      ? accent
                      : AppColors.borderOf(context).withValues(alpha: 0.5),
                ),
                onSelected: (selected) {
                  if (selected) {
                    draft.selectedCharacterIds.add(charDbId);
                    // Default the first pick to Protagonist.
                    if (draft.selectedCharacterIds.length == 1) {
                      draft.characterRoles[charDbId] = 'Protagonist';
                    } else {
                      draft.characterRoles.putIfAbsent(
                        charDbId,
                        () => 'Supporting',
                      );
                    }
                  } else {
                    draft.selectedCharacterIds.remove(charDbId);
                    draft.characterRoles.remove(charDbId);
                  }
                  onChanged();
                },
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildRoleAssignment(BuildContext context) {
    final charRepo = Provider.of<CharacterRepository>(context, listen: false);
    final accent = AppColors.porchTerracottaOf(context);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.cardOf(context),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: accent.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.theater_comedy, size: 16, color: accent),
              const SizedBox(width: 8),
              Text(
                'Assign Roles',
                style: TextStyle(
                  color: accent,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ...charRepo.characters
              .where(
                (c) =>
                    c.dbId != null &&
                    draft.selectedCharacterIds.contains(c.dbId),
              )
              .map(
                (char) => _roleRow(
                  context,
                  avatarLetter: char.name[0],
                  name: char.name,
                  accent: accent,
                  value: draft.characterRoles[char.dbId!] ?? 'Supporting',
                  onChanged: (v) {
                    draft.characterRoles[char.dbId!] = v ?? 'Supporting';
                    onChanged();
                  },
                ),
              ),
        ],
      ),
    );
  }

  Widget _buildUserPersonaToggle(BuildContext context) {
    final personaService = Provider.of<UserPersonaService>(
      context,
      listen: false,
    );
    final persona = personaService.persona;
    final accent = AppColors.porchHoneyOf(context);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.cardOf(context),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: draft.includeUserPersona
              ? accent.withValues(alpha: 0.4)
              : AppColors.borderOf(context).withValues(alpha: 0.5),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.person_pin,
                size: 18,
                color: draft.includeUserPersona
                    ? accent
                    : AppColors.iconSecondary(context),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Play as a character?',
                  style: TextStyle(
                    color: draft.includeUserPersona
                        ? accent
                        : AppColors.textSecondary(context),
                    fontSize: 13,
                  ),
                ),
              ),
              Switch(
                value: draft.includeUserPersona,
                activeThumbColor: accent,
                onChanged: (v) {
                  draft.includeUserPersona = v;
                  onChanged();
                },
              ),
            ],
          ),
          if (draft.includeUserPersona) ...[
            const SizedBox(height: 8),
            _roleRow(
              context,
              avatarLetter: persona.name.isEmpty ? '?' : persona.name[0],
              name: persona.name,
              subtitle: persona.persona.isEmpty ? null : persona.persona,
              accent: accent,
              value: draft.userPersonaRole,
              onChanged: (v) {
                draft.userPersonaRole = v ?? 'Protagonist';
                onChanged();
              },
            ),
          ],
        ],
      ),
    );
  }

  /// One "avatar · name · role dropdown" row, shared by character role
  /// assignment and the persona picker.
  Widget _roleRow(
    BuildContext context, {
    required String avatarLetter,
    required String name,
    String? subtitle,
    required Color accent,
    required String value,
    required ValueChanged<String?> onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          CircleAvatar(
            radius: 14,
            backgroundColor: accent.withValues(alpha: 0.25),
            child: Text(
              avatarLetter,
              style: TextStyle(color: accent, fontSize: 12),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: TextStyle(
                    color: AppColors.textPrimary(context),
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                if (subtitle != null)
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: AppColors.textTertiary(context),
                      fontSize: 11,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),
          DropdownButton<String>(
            value: value,
            dropdownColor: AppColors.surfaceContainerOf(context),
            underline: Container(
              height: 1,
              color: AppColors.borderOf(context).withValues(alpha: 0.5),
            ),
            style: TextStyle(
              color: AppColors.textSecondary(context),
              fontSize: 12,
            ),
            items: storyRoleOptions
                .map(
                  (r) => DropdownMenuItem(
                    value: r,
                    child: Text(r, style: const TextStyle(fontSize: 12)),
                  ),
                )
                .toList(),
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}
