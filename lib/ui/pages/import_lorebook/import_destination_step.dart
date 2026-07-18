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

import 'package:front_porch_ai/models/character_card.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';
import 'package:front_porch_ai/ui/widgets/app_text_field.dart';
import 'package:front_porch_ai/ui/widgets/warm_card.dart';

/// Where an imported lorebook can land.
enum LoreImportDestination { world, characters, group, chat }

/// Destination step: four warm option cards with per-option configuration.
/// The page owns the state; this widget renders and reports changes.
class ImportDestinationStep extends StatelessWidget {
  final LoreImportDestination selected;
  final ValueChanged<LoreImportDestination> onSelect;

  final TextEditingController worldNameCtrl;
  final TextEditingController worldDescCtrl;

  final List<CharacterCard> allCharacters;
  final Set<String> selectedCharacterIds;
  final void Function(String dbId, bool selected) onToggleCharacter;

  final String? activeGroupName;
  final bool chatAvailable;

  const ImportDestinationStep({
    super.key,
    required this.selected,
    required this.onSelect,
    required this.worldNameCtrl,
    required this.worldDescCtrl,
    required this.allCharacters,
    required this.selectedCharacterIds,
    required this.onToggleCharacter,
    required this.activeGroupName,
    required this.chatAvailable,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Where should this lorebook live?',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.bold,
              color: AppColors.textPrimary(context),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'A book has one home — attaching never copies.',
            style: TextStyle(
              fontSize: 12.5,
              color: AppColors.textTertiary(context),
            ),
          ),
          const SizedBox(height: 14),
          _option(
            context,
            dest: LoreImportDestination.world,
            icon: Icons.public,
            title: 'New World',
            body:
                'Goes into your shared library. Attach it to any character, '
                'group, or chat whenever you like.',
            config: Column(
              children: [
                const SizedBox(height: 10),
                AppTextField(
                  controller: worldNameCtrl,
                  decoration: _dec(context, 'World name'),
                ),
                const SizedBox(height: 8),
                AppTextField(
                  controller: worldDescCtrl,
                  decoration: _dec(context, 'Description (optional)'),
                ),
              ],
            ),
          ),
          _option(
            context,
            dest: LoreImportDestination.characters,
            icon: Icons.person,
            title: 'Into character(s)',
            body: 'Becomes part of their card and travels with them when '
                'exported.',
            config: allCharacters.isEmpty
                ? Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      'No characters in your library yet.',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.textTertiary(context),
                      ),
                    ),
                  )
                : Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final c in allCharacters)
                          if (c.dbId != null)
                            FilterChip(
                              label: Text(c.name),
                              selected: selectedCharacterIds.contains(c.dbId),
                              onSelected: (v) => onToggleCharacter(c.dbId!, v),
                              selectedColor: AppColors.porchAmberOf(context)
                                  .withValues(alpha: 0.25),
                              checkmarkColor:
                                  AppColors.porchAmberOf(context),
                            ),
                      ],
                    ),
                  ),
          ),
          if (activeGroupName != null)
            _option(
              context,
              dest: LoreImportDestination.group,
              icon: Icons.groups,
              title: 'This group — $activeGroupName',
              body: 'Shared by everyone in the current group chat.',
            ),
          if (chatAvailable)
            _option(
              context,
              dest: LoreImportDestination.chat,
              icon: Icons.chat_bubble_outline,
              title: 'This chat only',
              body: 'Try a book in one conversation without touching the '
                  'character or your library.',
            ),
        ],
      ),
    );
  }

  InputDecoration _dec(BuildContext context, String hint) => InputDecoration(
        isDense: true,
        filled: true,
        fillColor: AppColors.surfaceContainerOf(context),
        hintText: hint,
        hintStyle:
            TextStyle(fontSize: 12.5, color: AppColors.textTertiary(context)),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide.none,
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      );

  Widget _option(
    BuildContext context, {
    required LoreImportDestination dest,
    required IconData icon,
    required String title,
    required String body,
    Widget? config,
  }) {
    final amber = AppColors.porchAmberOf(context);
    final isSel = selected == dest;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: WarmCard(
        accent: isSel ? amber : null,
        onTap: () => onSelect(dest),
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  isSel
                      ? Icons.radio_button_checked
                      : Icons.radio_button_unchecked,
                  size: 18,
                  color: isSel ? amber : AppColors.iconSecondary(context),
                ),
                const SizedBox(width: 10),
                Icon(icon, size: 18, color: AppColors.iconSecondary(context)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      color: AppColors.textPrimary(context),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Padding(
              padding: const EdgeInsets.only(left: 28),
              child: Text(
                body,
                style: TextStyle(
                  fontSize: 12.5,
                  color: AppColors.textSecondary(context),
                  height: 1.4,
                ),
              ),
            ),
            if (isSel && config != null)
              Padding(
                padding: const EdgeInsets.only(left: 28),
                child: config,
              ),
          ],
        ),
      ),
    );
  }
}
