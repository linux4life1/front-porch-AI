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
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/theme/theme.dart';
import 'package:front_porch_ai/utils/utils.dart';
import 'persona_default_badge.dart';
import 'persona_hover_card.dart';

/// Persona grid card on the User Personas page. Tapping makes the persona
/// the default; the overflow menu routes to [onEdit] / [onExport] /
/// [onDelete] (delete only offered while more than one persona exists).
class PersonaGridCard extends StatelessWidget {
  const PersonaGridCard({
    super.key,
    required this.persona,
    required this.isDefault,
    required this.service,
    required this.onEdit,
    required this.onExport,
    required this.onDelete,
    this.onMakeCharacter,
  });

  final UserPersona persona;
  final bool isDefault;
  final UserPersonaService service;
  final ValueChanged<UserPersona> onEdit;
  final ValueChanged<UserPersona> onExport;

  /// Receives the card's context (the confirmation dialog anchors there).
  final void Function(BuildContext context, UserPersona persona) onDelete;

  /// "Make a Character" — hidden when null.
  final ValueChanged<UserPersona>? onMakeCharacter;

  @override
  Widget build(BuildContext context) {
    final cardColor = PersonaColors.getColorForPersona(persona.id);

    return PersonaHoverScaleCard(
      isActive: isDefault,
      accentColor: cardColor,
      onTap: () => service.setDefaultPersona(persona.id),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top row: avatar + actions
            Row(
              children: [
                PersonaColors.buildPersonaAvatar(
                  avatarPath: persona.avatarPath,
                  personaId: persona.id,
                  radius: 22,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        persona.displayLabel,
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                          color: AppColors.textPrimary(context),
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (persona.title.isNotEmpty)
                        Text(
                          persona.name,
                          style: TextStyle(
                            fontSize: 12,
                            color: cardColor.withValues(alpha: 0.7),
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                    ],
                  ),
                ),
                // Actions
                PopupMenuButton<String>(
                  icon: Icon(
                    Icons.more_vert,
                    size: 18,
                    color: AppColors.iconSecondary(context),
                  ),
                  color: AppColors.surfaceContainerOf(context),
                  onSelected: (action) {
                    switch (action) {
                      case 'edit':
                        onEdit(persona);
                        break;
                      case 'export':
                        onExport(persona);
                        break;
                      case 'make_character':
                        onMakeCharacter?.call(persona);
                        break;
                      case 'delete':
                        onDelete(context, persona);
                        break;
                    }
                  },
                  itemBuilder: (_) => [
                    PopupMenuItem(
                      value: 'edit',
                      child: Row(
                        children: [
                          Icon(
                            Icons.edit,
                            size: 16,
                            color: AppColors.iconPrimary(context),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Edit',
                            style: TextStyle(
                              fontSize: 13,
                              color: AppColors.textPrimary(context),
                            ),
                          ),
                        ],
                      ),
                    ),
                    PopupMenuItem(
                      value: 'export',
                      child: Row(
                        children: [
                          Icon(
                            Icons.upload,
                            size: 16,
                            color: AppColors.porchAmberOf(context),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Export JSON',
                            style: TextStyle(
                              fontSize: 13,
                              color: AppColors.textPrimary(context),
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (onMakeCharacter != null)
                      PopupMenuItem(
                        value: 'make_character',
                        child: Row(
                          children: [
                            Icon(
                              Icons.person_add_alt_1,
                              size: 16,
                              color: AppColors.porchAmberOf(context),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'Make a Character',
                              style: TextStyle(
                                fontSize: 13,
                                color: AppColors.textPrimary(context),
                              ),
                            ),
                          ],
                        ),
                      ),
                    if (service.personas.length > 1)
                      PopupMenuItem(
                        value: 'delete',
                        child: Row(
                          children: [
                            Icon(
                              Icons.delete,
                              size: 16,
                              color: StatusColors.dangerOf(context),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'Delete',
                              style: TextStyle(
                                fontSize: 13,
                                color: StatusColors.dangerOf(context),
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 10),
            // Description
            Expanded(
              child: Text(
                persona.persona.isNotEmpty ? persona.persona : 'No description',
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  color: persona.persona.isNotEmpty
                      ? AppColors.textSecondary(context)
                      : AppColors.textTertiary(context),
                  height: 1.5,
                ),
              ),
            ),
            const SizedBox(height: 8),
            // Bottom row
            Row(
              children: [
                if (!isDefault) ...[
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: cardColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: cardColor.withValues(alpha: 0.2),
                      ),
                    ),
                    child: Text(
                      'Make default',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: cardColor,
                      ),
                    ),
                  ),
                ] else ...[
                  const Spacer(),
                  PersonaDefaultBadge(color: cardColor),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// The no-personas landing state: Create Persona + Import JSON.
class PersonaEmptyState extends StatelessWidget {
  const PersonaEmptyState({
    super.key,
    required this.onCreate,
    required this.onImport,
  });

  final VoidCallback onCreate;
  final VoidCallback onImport;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 100,
            height: 100,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.porchAmberOf(context).withValues(alpha: 0.08),
              border: Border.all(
                color: AppColors.porchAmberOf(context).withValues(alpha: 0.15),
              ),
            ),
            child: Icon(
              Icons.person_add_alt_1,
              size: 44,
              color: AppColors.porchAmberOf(context),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'No personas yet',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: AppColors.textSecondary(context),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Create a persona to personalize your AI conversations,\nor import one from SillyTavern / Backyard AI.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              color: AppColors.textTertiary(context),
              height: 1.5,
            ),
          ),
          const SizedBox(height: 28),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              ElevatedButton.icon(
                onPressed: onCreate,
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Create Persona'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.porchAmberOf(context),
                  foregroundColor: AppColors.onAccentOf(context),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 14,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              OutlinedButton.icon(
                onPressed: onImport,
                icon: Icon(
                  Icons.download,
                  size: 18,
                  color: AppColors.porchAmberOf(context),
                ),
                label: Text(
                  'Import JSON',
                  style: TextStyle(color: AppColors.porchAmberOf(context)),
                ),
                style: OutlinedButton.styleFrom(
                  side: BorderSide(
                    color: AppColors.porchAmberOf(
                      context,
                    ).withValues(alpha: 0.3),
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 14,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
