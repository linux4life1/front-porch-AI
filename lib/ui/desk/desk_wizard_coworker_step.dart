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

import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';

class DeskWizardCoworkerStep extends StatelessWidget {
  const DeskWizardCoworkerStep({
    super.key,
    required this.characters,
    required this.selected,
    required this.onSelected,
  });

  final List<CharacterCard> characters;
  final CharacterCard? selected;
  final ValueChanged<CharacterCard> onSelected;

  @override
  Widget build(BuildContext context) {
    final amber = AppColors.porchAmberOf(context);
    if (characters.isEmpty) {
      return Center(
        child: Text(
          'Create a character first — Desk needs a coworker.',
          style: TextStyle(color: AppColors.textSecondary(context)),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Coworker',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              color: AppColors.textPrimary(context),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'One tap selects. Identity only — no lorebook, no Needs.',
            style: TextStyle(color: AppColors.textSecondary(context)),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: ListView.separated(
              itemCount: characters.length,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (context, i) {
                final card = characters[i];
                final isSelected =
                    identical(card, selected) ||
                    (selected != null && selected!.name == card.name);
                final clip = card.personality.trim();
                return Material(
                  color: isSelected
                      ? amber.withValues(alpha: 0.15)
                      : AppColors.cardOf(context),
                  borderRadius: BorderRadius.circular(12),
                  child: ListTile(
                    onTap: () => onSelected(card),
                    leading: _portrait(card),
                    title: Text(card.name),
                    subtitle: clip.isEmpty
                        ? null
                        : Text(
                            clip,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                    selected: isSelected,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: BorderSide(
                        color: isSelected ? amber : AppColors.borderOf(context),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _portrait(CharacterCard card) {
    final path = card.imagePath;
    if (path == null || path.isEmpty) {
      return const CircleAvatar(child: Icon(Icons.person));
    }
    return CircleAvatar(
      backgroundImage: FileImage(File(path)),
      onBackgroundImageError: (_, _) {},
    );
  }
}
