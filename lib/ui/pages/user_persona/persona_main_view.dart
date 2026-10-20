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
import 'package:provider/provider.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/theme/theme.dart';
import 'package:front_porch_ai/utils/utils.dart';
import 'persona_default_badge.dart';
import 'persona_list_cards.dart';

/// The persona list landing view: the hero header for the active persona
/// plus the "All Personas" grid section, or [PersonaEmptyState] when the
/// library is empty. [glow] drives the header's breathing accent.
class PersonaMainView extends StatelessWidget {
  const PersonaMainView({
    super.key,
    required this.glow,
    required this.onEdit,
    required this.onExport,
    required this.onDelete,
    required this.onCreate,
    required this.onImport,
    this.onMakeCharacter,
  });

  final Animation<double> glow;
  final ValueChanged<UserPersona> onEdit;
  final ValueChanged<UserPersona> onExport;
  final void Function(BuildContext context, UserPersona persona) onDelete;
  final VoidCallback onCreate;
  final VoidCallback onImport;
  final ValueChanged<UserPersona>? onMakeCharacter;

  @override
  Widget build(BuildContext context) {
    return Consumer<UserPersonaService>(
      builder: (context, service, child) {
        if (service.personas.isEmpty) {
          return PersonaEmptyState(onCreate: onCreate, onImport: onImport);
        }

        final defaultPersona = service.defaultPersona;
        final accentColor = PersonaColors.getColorForPersona(defaultPersona.id);

        return CustomScrollView(
          slivers: [
            // Hero header
            SliverToBoxAdapter(
              child: _PersonaHeroHeader(
                glow: glow,
                defaultPersona: defaultPersona,
                accentColor: accentColor,
                service: service,
                onEdit: onEdit,
              ),
            ),

            // Section label
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(28, 24, 28, 12),
                child: Row(
                  children: [
                    Container(
                      width: 3,
                      height: 18,
                      decoration: BoxDecoration(
                        color: AppColors.porchAmberOf(context),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      'All Personas (${service.personas.length})',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textSecondary(context),
                        letterSpacing: 0.3,
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // Persona grid
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
              sliver: SliverGrid(
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 340,
                  childAspectRatio: 1.35,
                  crossAxisSpacing: 16,
                  mainAxisSpacing: 16,
                ),
                delegate: SliverChildBuilderDelegate((context, index) {
                  final persona = service.personas[index];
                  final isDefault = persona.id == defaultPersona.id;
                  return PersonaGridCard(
                    persona: persona,
                    isDefault: isDefault,
                    service: service,
                    onEdit: onEdit,
                    onExport: onExport,
                    onDelete: onDelete,
                    onMakeCharacter: onMakeCharacter,
                  );
                }, childCount: service.personas.length),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _PersonaHeroHeader extends StatelessWidget {
  const _PersonaHeroHeader({
    required this.glow,
    required this.defaultPersona,
    required this.accentColor,
    required this.service,
    required this.onEdit,
  });

  final Animation<double> glow;
  final UserPersona defaultPersona;
  final Color accentColor;
  final UserPersonaService service;
  final ValueChanged<UserPersona> onEdit;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: glow,
      builder: (context, child) {
        return Container(
          margin: const EdgeInsets.fromLTRB(24, 8, 24, 0),
          padding: const EdgeInsets.all(28),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                accentColor.withValues(alpha: 0.08 + glow.value * 0.06),
                AppColors.cardOf(context).withValues(alpha: 0.9),
                AppColors.backgroundOf(context).withValues(alpha: 0.95),
              ],
            ),
            border: Border.all(
              color: accentColor.withValues(alpha: 0.15 + glow.value * 0.1),
            ),
            boxShadow: [
              BoxShadow(
                color: accentColor.withValues(alpha: 0.06),
                blurRadius: 30,
                spreadRadius: -8,
              ),
            ],
          ),
          child: Row(
            children: [
              // Avatar with glow
              Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: accentColor.withValues(
                        alpha: 0.25 + glow.value * 0.15,
                      ),
                      blurRadius: 24,
                      spreadRadius: -2,
                    ),
                  ],
                ),
                child: PersonaColors.buildPersonaAvatar(
                  avatarPath: defaultPersona.avatarPath,
                  personaId: defaultPersona.id,
                  radius: 44,
                  iconSize: 36,
                ),
              ),
              const SizedBox(width: 24),
              // Info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            defaultPersona.displayLabel,
                            style: TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                              color: AppColors.textPrimary(context),
                              letterSpacing: -0.3,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 10),
                        PersonaDefaultBadge(color: accentColor),
                      ],
                    ),
                    if (defaultPersona.title.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        defaultPersona.name,
                        style: TextStyle(
                          fontSize: 14,
                          color: accentColor.withValues(alpha: 0.8),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                    if (defaultPersona.persona.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(
                        defaultPersona.persona,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13,
                          color: AppColors.textSecondary(context),
                          height: 1.4,
                        ),
                      ),
                    ],
                    const SizedBox(height: 14),
                    // Stats chips
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: [
                        _PersonaStatChip(
                          icon: Icons.people_outline,
                          label:
                              '${service.personas.length} persona${service.personas.length != 1 ? 's' : ''}',
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              // Edit button
              IconButton(
                icon: Icon(
                  Icons.edit_outlined,
                  color: accentColor.withValues(alpha: 0.7),
                ),
                tooltip: 'Edit active persona',
                onPressed: () => onEdit(defaultPersona),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _PersonaStatChip extends StatelessWidget {
  const _PersonaStatChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: InkColors.washOf(context, 0.05, 0.04),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: InkColors.chipEdgeOf(context)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: AppColors.textTertiary(context)),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              color: AppColors.textTertiary(context),
            ),
          ),
        ],
      ),
    );
  }
}
